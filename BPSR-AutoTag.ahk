#Requires AutoHotkey v2.0
#SingleInstance Force
SendMode("Input")
CoordMode("Pixel", "Screen")
CoordMode("Mouse", "Screen")
SetTitleMatchMode(2)

global Config := Map()
global State := Map()

OnExit(Cleanup)

F8:: ToggleRole()
F9:: ToggleAutomation()
F10:: ExitScript()

Init() {
    global Config, State

    Config["BaseWidth"] := 1920
    Config["BaseHeight"] := 1080
    Config["TimerInterval"] := 500
    Config["ScreenResetDelay"] := 1800
    Config["GameExecutables"] := ["BPSR_STEAM.exe", "BPSR_EPIC.exe", "BPSR.exe"]

    ; Coordenadas relativas al cliente 1920x1080; los clics se escalan al tamano real.
    ; Lider: Wondrous Tag (1535,635) y Party Mode (1485,983).
    ; Todos: Confirm (1740,982), Next/Leave (960,968).
    Config["Screens"] := Map(
        "npc-tag", {
            leaderOnly: true,
            clickX: 1535,
            clickY: 635,
            retryMs: 5000,
            signature: {
                required: 3,
                points: [{ x: 1420, y: 565, color: 0xFFFFFF, tolerance: 40 }, { x: 1426, y: 635, color: 0xCACACA,
                    tolerance: 55 }, { x: 1490, y: 635, color: 0x040C0F, tolerance: 18 }, { x: 1600, y: 635, color: 0x071216,
                        tolerance: 18 }
                ]
            }
        },
        "party-mode", {
            leaderOnly: true,
            clickX: 1485,
            clickY: 983,
            retryMs: 8000,
            signature: {
                required: 2,
                points: [{ x: 1390, y: 240, color: 0x7692C3, tolerance: 35 }, { x: 1500, y: 240, color: 0x7893C3,
                    tolerance: 35 }, { x: 1485, y: 983, color: 0xE8E8E8, tolerance: 20 }, { x: 1800, y: 1000, color: 0xE8E8E8,
                        tolerance: 20 }
                ]
            }
        },
        "confirm-entry", {
            leaderOnly: false,
            clickX: 1740,
            clickY: 982,
            retryMs: 2500,
            signature: {
                required: 2,
                points: [{ x: 600, y: 70, color: 0xFFFFFF, tolerance: 45 }, { x: 200, y: 700, color: 0xF1F4F1,
                    tolerance: 45 }, { x: 980, y: 890, color: 0xC1C1C1, tolerance: 55 }, { x: 1740, y: 968, color: 0xE8E8E8,
                        tolerance: 20 }
                ]
            }
        },
        "match-results", {
            leaderOnly: false,
            clickX: 960,
            clickY: 968,
            retryMs: 4500,
            signature: {
                required: 3,
                points: [{ x: 400, y: 390, color: 0xDADADA, tolerance: 15 }, { x: 750, y: 390, color: 0xDADADA,
                    tolerance: 15 }, { x: 750, y: 570, color: 0xDADADA, tolerance: 15 }, { x: 850, y: 968, color: 0xE8E8E8,
                        tolerance: 20 }
                ]
            }
        },
        "rewards", {
            leaderOnly: false,
            clickX: 960,
            clickY: 968,
            retryMs: 4500,
            signature: {
                required: 2,
                points: [{ x: 800, y: 120, color: 0xFFF9F3, tolerance: 35 }, { x: 960, y: 139, color: 0xFFF9F3,
                    tolerance: 35 }, { x: 850, y: 968, color: 0xE8E8E8, tolerance: 20 }, { x: 960, y: 968, color: 0x323232,
                        tolerance: 25 }
                ]
            }
        }
    )

    State["Role"] := "participant"
    State["Enabled"] := false
    State["Busy"] := false
    State["CurrentScreen"] := ""
    State["LastActionAt"] := 0
    State["NoScreenSince"] := 0

    ShowStatus("AutoTag listo | F8: rol | F9: activar | F10: salir", 5000)
}

Init()

ToggleRole(*) {
    global State

    State["Role"] := State["Role"] = "leader" ? "participant" : "leader"
        roleLabel := State["Role"] = "leader"
            ? "LIDER (5 pantallas)"
                : "PARTICIPANTE (3 pantallas)"
        ShowStatus("Rol: " . roleLabel, 3000)
}

ToggleAutomation(*) {
    global Config, State

    State["Enabled"] := !State["Enabled"]
    if State["Enabled"] {
        ; El primer ciclo detecta la pantalla visible aunque se active a mitad del flujo.
        State["CurrentScreen"] := ""
        State["LastActionAt"] := 0
        State["NoScreenSince"] := 0
        SetTimer(CheckLogic, Config["TimerInterval"])
        ShowStatus("AutoTag ACTIVADO | " . RoleLabel() . " | F9: pausar", 3000)
        return
    }

    SetTimer(CheckLogic, 0)
    State["CurrentScreen"] := ""
    State["LastActionAt"] := 0
    State["NoScreenSince"] := 0
    ShowStatus("AutoTag pausado", 2000)
}

ExitScript(*) {
    global State

    State["Enabled"] := false
    SetTimer(CheckLogic, 0)
    ExitApp()
}

CheckLogic() {
    global Config, State

    if !State["Enabled"] || State["Busy"]
        return

    State["Busy"] := true
    try {
        game := GetActiveGameWindow()
        if !IsObject(game)
            return

        screenName := DetectScreen(game)
        if (screenName = "") {
            if (State["CurrentScreen"] != "") {
                if (State["NoScreenSince"] = 0) {
                    State["NoScreenSince"] := A_TickCount
                } else if (A_TickCount - State["NoScreenSince"] >= Config["ScreenResetDelay"]) {
                    State["CurrentScreen"] := ""
                    State["LastActionAt"] := 0
                    State["NoScreenSince"] := 0
                }
            }
            return
        }

        State["NoScreenSince"] := 0
        screen := Config["Screens"][screenName]
        if (State["CurrentScreen"] != screenName) {
            State["CurrentScreen"] := screenName
            State["LastActionAt"] := 0
        }

        if (State["LastActionAt"] != 0
            && A_TickCount - State["LastActionAt"] < screen.retryMs)
            return

        if ClickGamePoint(game, screen)
            State["LastActionAt"] := A_TickCount
    } catch as e {
        ShowStatus("AutoTag: " . e.Message, 3000)
    } finally {
        State["Busy"] := false
    }
}

GetActiveGameWindow() {
    global Config

    hwnd := WinExist("A")
    if !hwnd
        return false

    try {
        processName := StrLower(WinGetProcessName("ahk_id " . hwnd))
        isGame := false
        for _, exeName in Config["GameExecutables"] {
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

DetectScreen(game) {
    global Config, State

    ; Se reconocen primero las pantallas posteriores para permitir empezar en cualquier punto.
    if IsSignatureVisible("rewards", game)
        return "rewards"
    if IsSignatureVisible("match-results", game)
        return "match-results"
    if IsSignatureVisible("confirm-entry", game)
        return "confirm-entry"

    if (State["Role"] = "leader") {
        if IsSignatureVisible("party-mode", game)
            return "party-mode"
        if IsSignatureVisible("npc-tag", game)
            return "npc-tag"
    }

    return ""
}

IsSignatureVisible(screenName, game) {
    global Config

    screen := Config["Screens"][screenName]
    signature := screen.signature
    matches := 0

    for _, point in signature.points {
        x := game.x + Round(point.x * game.w / Config["BaseWidth"])
        y := game.y + Round(point.y * game.h / Config["BaseHeight"])
        try {
            color := PixelGetColor(x, y, "RGB")
        } catch {
            continue
        }

        if ColorCloseEnough(color, point.color, point.tolerance)
            matches += 1
    }

    return matches >= signature.required
}

ColorCloseEnough(color1, color2, tolerance) {
    return Abs(((color1 >> 16) & 0xFF) - ((color2 >> 16) & 0xFF)) <= tolerance
    && Abs(((color1 >> 8) & 0xFF) - ((color2 >> 8) & 0xFF)) <= tolerance
    && Abs((color1 & 0xFF) - (color2 & 0xFF)) <= tolerance
}

ClickGamePoint(game, screen) {
    global Config

    if !WinActive("ahk_id " . game.hwnd)
        return false

    x := game.x + Round(screen.clickX * game.w / Config["BaseWidth"])
    y := game.y + Round(screen.clickY * game.h / Config["BaseHeight"])
    Click(x, y)
    return true
}

RoleLabel() {
    global State
    return State["Role"] = "leader" ? "lider" : "participante"
}

ShowStatus(message, durationMs := 2500) {
    ToolTip(message, 10, 10)
    SetTimer(HideStatus, -durationMs)
}

HideStatus(*) {
    ToolTip()
}

Cleanup(*) {
    SetTimer(CheckLogic, 0)
    ToolTip()
}
