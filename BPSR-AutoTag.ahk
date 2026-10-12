#Requires AutoHotkey v2.0
#SingleInstance Force

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
    gameExecutables: ["BPSR_STEAM.exe", "BPSR_EPIC.exe", "BPSR.exe"],
    points: {
        leader: { x: 1485, y: 1015, color: 0xE8E8E8 },
        players: { x: 1675, y: 1025, color: 0xE8E8E8, clickX: 1735, clickY: 1025 },
        sharedFirst: { x: 925, y: 1000, color: 0xE8E8E8 },
        sharedSecond: { x: 910, y: 1000, color: 0xE8E8E8, clickX: 960, clickY: 1000 }
    }
}

global State := {
    role: "players",
    enabled: false,
    busy: false,
    phase: "stopped",
    phaseDeadline: 0,
    nextLeaderPressAt: 0,
    lastWindowNoticeAt: 0
}

OnExit(Cleanup)

F8::ToggleRole()
F9::ToggleAutomation()
F10::ExitScript()

ShowStatus("AutoTag listo | F8: rol | F9: activar/pausar | F10: salir", 5000)

ToggleRole(*) {
    global State

    State.role := (State.role = "leader") ? "players" : "leader"
    State.phase := "detect-start"
    State.phaseDeadline := 0
    State.nextLeaderPressAt := 0

    ShowStatus("Rol: " . RoleLabel() . (State.enabled ? " | flujo reiniciado" : ""))
}

ToggleAutomation(*) {
    global Config, State

    if State.enabled {
        State.enabled := false
        SetTimer(CheckLogic, 0)
        ShowStatus("AutoTag pausado")
        return
    }

    State.enabled := true
    if (State.phase = "stopped")
        State.phase := "detect-start"
    SetTimer(CheckLogic, Config.pollIntervalMs)
    ShowStatus("AutoTag activado | Rol: " . RoleLabel())
}

ExitScript(*) {
    global State

    State.enabled := false
    SetTimer(CheckLogic, 0)
    ExitApp()
}

CheckLogic(*) {
    global State

    if !State.enabled || State.busy
        return

    State.busy := true
    try {
        game := GetActiveGameWindow()
        if !IsObject(game) {
            now := A_TickCount
            if (State.lastWindowNoticeAt = 0 || now - State.lastWindowNoticeAt >= 3000) {
                ShowStatus("Activa la ventana del juego para continuar")
                State.lastWindowNoticeAt := now
            }
            return
        }

        State.lastWindowNoticeAt := 0
        ProcessPhase(game)
    } catch as e {
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
            ShowStatus("Reanudado en el primer paso compartido")
        } else if PixelMatches(game, Config.points.sharedSecond) {
            State.phase := "shared-second"
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
                ShowStatus("Party Mode pulsado | comprobando en 3 s")
            }
        } else if (State.nextLeaderPressAt = 0 || now >= State.nextLeaderPressAt) {
            if WinActive("ahk_id " . game.hwnd) {
                Send("{f}")
                State.nextLeaderPressAt := now + Config.leaderPressIntervalMs
            }
        }
        return
    }

    if (State.phase = "leader-verify") {
        if (now >= State.phaseDeadline) {
            if PixelMatches(game, Config.points.leader) {
                if ClickGamePoint(game, Config.points.leader) {
                    State.phaseDeadline := now + Config.partyModeRetryMs
                    ShowStatus("Party Mode sigue visible | reintentando en 3 s")
                }
            } else {
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
            if ClickGamePoint(game, Config.points.leader)
                ShowStatus("Party Mode reapareció | comprobando en 3 s")
            return
        }

        if (now >= State.phaseDeadline) {
            State.phase := "shared-first"
            ShowStatus("Buscando el primer paso compartido")
        }
        return
    }

    if (State.phase = "shared-first") {
        if (PixelMatches(game, Config.points.sharedFirst)
            && ClickGamePoint(game, Config.points.sharedFirst)) {
            State.phase := "shared-second-delay"
            State.phaseDeadline := now + Config.betweenSharedClicksMs
            ShowStatus("Next pulsado | esperando 2 s antes de Leave")
        }
        return
    }

    if (State.phase = "shared-second-delay") {
        if (now >= State.phaseDeadline) {
            State.phase := "shared-second"
            ShowStatus("Buscando Leave")
        }
        return
    }

    if (State.phase = "shared-second") {
        if (PixelMatches(game, Config.points.sharedSecond)
            && ClickGamePoint(game, Config.points.sharedSecond, Config.points.sharedSecond.clickX, Config.points.sharedSecond.clickY)) {
            State.phase := "shared-second-verify"
            State.phaseDeadline := now + Config.sharedClickRetryMs
            ShowStatus("Leave pulsado | comprobando en 1,5 s")
        }
        return
    }

    if (State.phase = "shared-second-verify" && now >= State.phaseDeadline) {
        if PixelMatches(game, Config.points.sharedSecond) {
            if ClickGamePoint(game, Config.points.sharedSecond, Config.points.sharedSecond.clickX, Config.points.sharedSecond.clickY) {
                State.phaseDeadline := now + Config.sharedClickRetryMs
                ShowStatus("Leave sigue visible | reintentando")
            }
        } else {
            State.phase := "cycle-wait"
            State.phaseDeadline := now + Config.cycleWaitMs
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
    ShowStatus("Acción del rol completada | esperando 1 min")
}

StartRolePhase() {
    global State

    State.phase := (State.role = "leader") ? "leader-action" : "players-action"
    State.phaseDeadline := 0
    State.nextLeaderPressAt := 0
}

GetActiveGameWindow() {
    global Config

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

        return {
            hwnd: hwnd,
            x: clientX,
            y: clientY,
            w: clientW,
            h: clientH
        }
    } catch {
        return false
    }
}

PixelMatches(game, point) {
    global Config

    x := game.x + Round(point.x * game.w / Config.baseWidth)
    y := game.y + Round(point.y * game.h / Config.baseHeight) - Config.buttonYOffsetPx
    try {
        color := PixelGetColor(x, y, "RGB")
    } catch {
        return false
    }

    return ColorCloseEnough(color, point.color, Config.colorTolerance)
}

ColorCloseEnough(color, target, tolerance) {
    return (Abs(((color >> 16) & 0xFF) - ((target >> 16) & 0xFF)) <= tolerance
        && Abs(((color >> 8) & 0xFF) - ((target >> 8) & 0xFF)) <= tolerance
        && Abs((color & 0xFF) - (target & 0xFF)) <= tolerance)
}

ClickGamePoint(game, point, clickX := 0, clickY := 0) {
    global Config

    if !WinActive("ahk_id " . game.hwnd)
        return false

    targetX := (clickX != 0) ? clickX : point.x
    targetY := (clickY != 0) ? clickY : point.y
    x := game.x + Round(targetX * game.w / Config.baseWidth)
    y := game.y + Round(targetY * game.h / Config.baseHeight) - Config.buttonYOffsetPx
    Click(x, y)
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

Cleanup(*) {
    SetTimer(CheckLogic, 0)
    ToolTip()
}
