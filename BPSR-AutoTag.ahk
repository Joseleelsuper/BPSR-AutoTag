#Requires AutoHotkey v2.0
#SingleInstance Force

global AppVersion := "1.7"

SendMode("Input")
CoordMode("Pixel", "Screen")
CoordMode("Mouse", "Screen")

global Config := {
    baseWidth: 1920,
    baseHeight: 1080,
    buttonYOffsetPx: 30,
    pollIntervalMs: 100,
    colorTolerance: 10,
    leaderPressIntervalMs: 500,
    partyModeRetryMs: 3000,
    sharedWaitMs: 60000,
    betweenSharedClicksMs: 2000,
    sharedClickRetryMs: 1500,
    cycleWaitMs: 5000,
    logLevels: { debug: "DEBUG", info: "INFO", warning: "WARNING", error: "ERROR" },
    log: { filePath: A_ScriptDir "\BPSR-AutoTag.log", timeFormat: "HH:mm:ss", encoding: "UTF-8" },
    leaderProgressLogIntervalMs: 10000,
    gameExecutables: ["BPSR_STEAM.exe", "BPSR_EPIC.exe", "BPSR.exe"],
    points: {
        leader: { name: "Party Mode", x: 1485, y: 1015, color: 0xE8E8E8 },
        players: { name: "Confirm", x: 1675, y: 1025, color: 0xE8E8E8, clickX: 1735, clickY: 1025 },
        sharedFirst: { name: "Next", x: 925, y: 1000, color: 0xE8E8E8 },
        sharedSecond: { name: "Leave", x: 910, y: 1000, color: 0xE8E8E8, clickX: 960, clickY: 1000 }
    }
}

global State := {
    role: "players",
    enabled: false,
    busy: false,
    phase: "stopped",
    phaseDeadline: 0,
    nextLeaderPressAt: 0,
    lastWindowNoticeAt: 0,
    windowMissing: false,
    windowInspectionErrorLogged: false,
    logicErrorActive: false,
    leaderPressCount: 0,
    lastLeaderProgressAt: 0,
    pixelReadErrors: Map(),
    inactiveClickWarnings: Map()
}

OnExit(Cleanup)

ShowStatus("AutoTag listo | F8: rol | F9: activar/pausar | F10: salir", 5000)
WriteLog(Config.logLevels.info, "BPSR-AutoTag v" . AppVersion . " iniciado")

F8::ToggleRole()
F9::ToggleAutomation()
F10::ExitScript()

WriteLog(level, message) {
    global Config

    timestamp := FormatTime(A_Now, Config.log.timeFormat)
    FileAppend("[" . timestamp . "] [" . level . "] " . message . "`r`n", Config.log.filePath, Config.log.encoding)
}

ToggleRole(*) {
    global Config, State

    previousRole := RoleLabel()
    State.role := (State.role = "leader") ? "players" : "leader"
    State.phase := "detect-start"
    State.phaseDeadline := 0
    State.nextLeaderPressAt := 0

    WriteLog(Config.logLevels.info, "Rol cambiado de " . previousRole . " a " . RoleLabel() . "; reiniciando flujo")
    ShowStatus("Rol: " . RoleLabel() . (State.enabled ? " | flujo reiniciado" : ""))
}

ToggleAutomation(*) {
    global Config, State

    if State.enabled {
        State.enabled := false
        SetTimer(CheckLogic, 0)
        WriteLog(Config.logLevels.info, "AutoTag pausado en fase " . State.phase)
        ShowStatus("AutoTag pausado")
        return
    }

    State.enabled := true
    if (State.phase = "stopped")
        State.phase := "detect-start"
    SetTimer(CheckLogic, Config.pollIntervalMs)
    WriteLog(Config.logLevels.info, "AutoTag activado; rol " . RoleLabel() . ", fase " . State.phase)
    ShowStatus("AutoTag activado | Rol: " . RoleLabel())
}

ExitScript(*) {
    global Config, State

    State.enabled := false
    SetTimer(CheckLogic, 0)
    WriteLog(Config.logLevels.info, "Salida solicitada con F10")
    ExitApp()
}

CheckLogic(*) {
    global Config, State

    if !State.enabled || State.busy
        return

    State.busy := true
    try {
        game := GetActiveGameWindow()
        if !IsObject(game) {
            if !State.windowMissing {
                WriteLog(Config.logLevels.error, "No se detectó la ventana del juego; AutoTag espera")
                State.windowMissing := true
            }
            now := A_TickCount
            if (State.lastWindowNoticeAt = 0 || now - State.lastWindowNoticeAt >= 3000) {
                ShowStatus("Activa la ventana del juego para continuar")
                State.lastWindowNoticeAt := now
            }
            return
        }

        if State.windowMissing {
            WriteLog(Config.logLevels.info, "Ventana del juego detectada de nuevo; cliente " . game.w . "x" . game.h)
            State.windowMissing := false
        }
        State.lastWindowNoticeAt := 0
        ProcessPhase(game)
        if State.logicErrorActive {
            WriteLog(Config.logLevels.info, "La automatización se recuperó de un error")
            State.logicErrorActive := false
        }
    } catch as e {
        if !State.logicErrorActive {
            WriteLog(Config.logLevels.error, "Error en CheckLogic: " . e.Message . " | archivo: " . e.File . " | línea: " . e.Line)
            State.logicErrorActive := true
        }
        ShowStatus("AutoTag: " . e.Message, 4000)
    } finally {
        State.busy := false
    }
}

ProcessPhase(game) {
    global Config, State

    now := A_TickCount

    if (State.phase = "detect-start") {
        if PixelMatches(game, Config.points.sharedFirst) {
            State.phase := "shared-first"
            WriteLog(Config.logLevels.info, "Inicio/reanudación detectó Next visible")
            ShowStatus("Reanudado en el primer paso compartido")
        } else if PixelMatches(game, Config.points.sharedSecond) {
            State.phase := "shared-second"
            WriteLog(Config.logLevels.info, "Inicio/reanudación detectó Leave visible")
            ShowStatus("Reanudado en el segundo paso compartido")
        } else {
            StartRolePhase()
            ShowStatus("Rol: " . RoleLabel())
        }
        return
    }

    if (State.phase = "leader-action") {
        if PixelMatches(game, Config.points.leader) {
            if ClickGamePoint(game, Config.points.leader) {
                State.phase := "leader-verify"
                State.phaseDeadline := now + Config.partyModeRetryMs
                State.nextLeaderPressAt := 0
                WriteLog(Config.logLevels.info, "Comprobando Party Mode en 3 segundos")
                ShowStatus("Party Mode pulsado | comprobando en 3 s")
            }
        } else if (State.nextLeaderPressAt = 0 || now >= State.nextLeaderPressAt) {
            if WinActive("ahk_id " . game.hwnd) {
                Send("{f}")
                State.nextLeaderPressAt := now + Config.leaderPressIntervalMs
                State.leaderPressCount += 1
                if (State.lastLeaderProgressAt = 0
                    || now - State.lastLeaderProgressAt >= Config.leaderProgressLogIntervalMs) {
                    WriteLog(Config.logLevels.debug, "Buscando Party Mode: F enviada " . State.leaderPressCount . " veces; botón aún no detectado")
                    State.lastLeaderProgressAt := now
                }
            }
        }
        return
    }

    if (State.phase = "leader-verify") {
        if (now >= State.phaseDeadline) {
            if PixelMatches(game, Config.points.leader) {
                if ClickGamePoint(game, Config.points.leader) {
                    State.phaseDeadline := now + Config.partyModeRetryMs
                    WriteLog(Config.logLevels.warning, "Party Mode sigue visible; se volverá a comprobar en 3 segundos")
                    ShowStatus("Party Mode sigue visible | reintentando en 3 s")
                }
            } else {
                WriteLog(Config.logLevels.info, "Party Mode ya no está visible; termina la acción Leader")
                BeginSharedWait()
            }
        }
        return
    }

    if (State.phase = "players-action") {
        if (PixelMatches(game, Config.points.players)
            && ClickGamePoint(game, Config.points.players, Config.points.players.clickX, Config.points.players.clickY)) {
            BeginSharedWait()
        }
        return
    }

    if (State.phase = "shared-wait") {
        if (State.role = "leader" && PixelMatches(game, Config.points.leader)) {
            State.phase := "leader-verify"
            State.phaseDeadline := now + Config.partyModeRetryMs
            WriteLog(Config.logLevels.info, "Party Mode reapareció durante la espera compartida")
            if ClickGamePoint(game, Config.points.leader)
                ShowStatus("Party Mode reapareció | comprobando en 3 s")
            return
        }

        if (now >= State.phaseDeadline) {
            State.phase := "shared-first"
            WriteLog(Config.logLevels.info, "Terminó la espera compartida de 1 minuto; buscando Next")
            ShowStatus("Buscando el primer paso compartido")
        }
        return
    }

    if (State.phase = "shared-first") {
        if (PixelMatches(game, Config.points.sharedFirst)
            && ClickGamePoint(game, Config.points.sharedFirst)) {
            State.phase := "shared-second-delay"
            State.phaseDeadline := now + Config.betweenSharedClicksMs
            WriteLog(Config.logLevels.info, "Next completado; esperando 2 segundos antes de buscar Leave")
            ShowStatus("Next pulsado | esperando 2 s antes de Leave")
        }
        return
    }

    if (State.phase = "shared-second-delay") {
        if (now >= State.phaseDeadline) {
            State.phase := "shared-second"
            WriteLog(Config.logLevels.info, "Terminó la espera entre Next y Leave")
            ShowStatus("Buscando Leave")
        }
        return
    }

    if (State.phase = "shared-second") {
        if (PixelMatches(game, Config.points.sharedSecond)
            && ClickGamePoint(game, Config.points.sharedSecond, Config.points.sharedSecond.clickX, Config.points.sharedSecond.clickY)) {
            State.phase := "shared-second-verify"
            State.phaseDeadline := now + Config.sharedClickRetryMs
            WriteLog(Config.logLevels.info, "Comprobando Leave en 1,5 segundos")
            ShowStatus("Leave pulsado | comprobando en 1,5 s")
        }
        return
    }

    if (State.phase = "shared-second-verify" && now >= State.phaseDeadline) {
        if PixelMatches(game, Config.points.sharedSecond) {
            if ClickGamePoint(game, Config.points.sharedSecond, Config.points.sharedSecond.clickX, Config.points.sharedSecond.clickY) {
                State.phaseDeadline := now + Config.sharedClickRetryMs
                WriteLog(Config.logLevels.warning, "Leave sigue visible; se volverá a pulsar en 1,5 segundos")
                ShowStatus("Leave sigue visible | reintentando")
            }
        } else {
            State.phase := "cycle-wait"
            State.phaseDeadline := now + Config.cycleWaitMs
            WriteLog(Config.logLevels.info, "Leave desapareció; esperando 5 segundos antes del siguiente ciclo")
            ShowStatus("Leave completado | esperando 5 s")
        }
        return
    }

    if (State.phase = "cycle-wait" && now >= State.phaseDeadline) {
        StartRolePhase()
        ShowStatus("Nuevo ciclo | Rol: " . RoleLabel())
    }
}

BeginSharedWait() {
    global Config, State

    State.phase := "shared-wait"
    State.phaseDeadline := A_TickCount + Config.sharedWaitMs
    State.nextLeaderPressAt := 0
    WriteLog(Config.logLevels.info, "Acción " . RoleLabel() . " completada; esperando 1 minuto antes del flujo compartido")
    ShowStatus("Acción del rol completada | esperando 1 min")
}

StartRolePhase() {
    global Config, State

    State.phase := (State.role = "leader") ? "leader-action" : "players-action"
    State.phaseDeadline := 0
    State.nextLeaderPressAt := 0
    State.leaderPressCount := 0
    State.lastLeaderProgressAt := 0
    if (State.role = "leader")
        WriteLog(Config.logLevels.info, "Iniciando fase Leader: buscando Party Mode y enviando F mientras no aparezca")
    else
        WriteLog(Config.logLevels.info, "Iniciando fase Players: buscando el botón Confirm")
}

GetActiveGameWindow() {
    global Config, State

    hwnd := WinExist("A")
    if !hwnd
        return false

    try {
        processName := StrLower(WinGetProcessName("ahk_id " . hwnd))
        isGame := false
        for _, exeName in Config.gameExecutables {
            if (processName = StrLower(exeName)) {
                isGame := true
                break
            }
        }

        if !isGame {
            title := StrLower(WinGetTitle("ahk_id " . hwnd))
            if !InStr(title, "blue protocol: star resonance")
                return false
        }

        if (WinGetMinMax("ahk_id " . hwnd) = -1)
            return false

        WinGetClientPos(&clientX, &clientY, &clientW, &clientH, "ahk_id " . hwnd)
        if (clientW < 640 || clientH < 360)
            return false

        if State.windowInspectionErrorLogged {
            WriteLog(Config.logLevels.info, "Inspección de la ventana del juego recuperada")
            State.windowInspectionErrorLogged := false
        }

        return {
            hwnd: hwnd,
            x: clientX,
            y: clientY,
            w: clientW,
            h: clientH
        }
    } catch as e {
        if !State.windowInspectionErrorLogged {
            WriteLog(Config.logLevels.error, "No se pudo inspeccionar la ventana activa: " . e.Message)
            State.windowInspectionErrorLogged := true
        }
        return false
    }
}

PixelMatches(game, point) {
    global Config, State

    x := game.x + Round(point.x * game.w / Config.baseWidth)
    y := game.y + Round(point.y * game.h / Config.baseHeight) - Config.buttonYOffsetPx
    try {
        color := PixelGetColor(x, y, "RGB")
    } catch as e {
        if !State.pixelReadErrors.Has(point.name) {
            WriteLog(Config.logLevels.error, "No se pudo leer el píxel de " . point.name . ": " . e.Message)
            State.pixelReadErrors[point.name] := true
        }
        return false
    }

    if State.pixelReadErrors.Has(point.name) {
        State.pixelReadErrors.Delete(point.name)
        WriteLog(Config.logLevels.info, "Lectura del píxel de " . point.name . " recuperada")
    }
    return ColorCloseEnough(color, point.color, Config.colorTolerance)
}

ColorCloseEnough(color, target, tolerance) {
    return (Abs(((color >> 16) & 0xFF) - ((target >> 16) & 0xFF)) <= tolerance
        && Abs(((color >> 8) & 0xFF) - ((target >> 8) & 0xFF)) <= tolerance
        && Abs((color & 0xFF) - (target & 0xFF)) <= tolerance)
}

ClickGamePoint(game, point, clickX := 0, clickY := 0) {
    global Config, State

    if !WinActive("ahk_id " . game.hwnd) {
        if !State.inactiveClickWarnings.Has(point.name) {
            WriteLog(Config.logLevels.warning, "Se omitió el clic en " . point.name . ": el juego dejó de estar activo")
            State.inactiveClickWarnings[point.name] := true
        }
        return false
    }

    targetX := (clickX != 0) ? clickX : point.x
    targetY := (clickY != 0) ? clickY : point.y
    x := game.x + Round(targetX * game.w / Config.baseWidth)
    y := game.y + Round(targetY * game.h / Config.baseHeight) - Config.buttonYOffsetPx
    Click(x, y)
    if State.inactiveClickWarnings.Has(point.name) {
        State.inactiveClickWarnings.Delete(point.name)
        WriteLog(Config.logLevels.info, "El juego recuperó el foco para el clic en " . point.name)
    }
    WriteLog(Config.logLevels.info, "Clic en " . point.name . " en coordenadas de pantalla (" . x . ", " . y . ")")
    return true
}

RoleLabel() {
    global State
    return (State.role = "leader") ? "Leader" : "Players"
}

ShowStatus(message, durationMs := 2500) {
    ToolTip(message, 10, 10)
    SetTimer(HideStatus, 0)
    SetTimer(HideStatus, -durationMs)
}

HideStatus(*) {
    ToolTip()
}

Cleanup(exitReason, *) {
    global Config

    SetTimer(CheckLogic, 0)
    ToolTip()
    WriteLog(Config.logLevels.info, "AutoTag detenido (" . exitReason . ")")
}
