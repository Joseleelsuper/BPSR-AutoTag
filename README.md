# BPSR-AutoTag

Automates the Leader and Players button flow for Wondrous Tag in Blue Protocol: Star Resonance using pixel colors and scaled coordinates.

## Quick start

1. Download and run **BPSR-AutoTag.exe** from the [latest release](https://github.com/Joseleelsuper/BPSR-AutoTag/releases/latest).
2. Open the game and keep its window active. The default role is **Players**; press **F8** to select **Leader**.
3. Press **F9** to start or pause automation. Press **F10** to exit.

## What it automates

- **Leader:** repeatedly presses **F** until `#E8E8E8` is detected at `(1485, 1015)`, then clicks that point.
- **Players:** waits for `#CCCCCC` at `(1675, 1025)`, then clicks that point.
- **Shared flow:** waits 1 minute, clicks `#E8E8E8` at `(925, 1000)`, waits for and clicks `#E8E8E8` at `(910, 1000)`, then waits 5 seconds before repeating the selected role flow.

Color checks allow a small per-channel tolerance to account for rendering differences. If the script starts while either shared-flow point is visible, it resumes from that step. Pressing **F9** to pause and resume preserves the current phase while the script remains open.

## Hotkeys

- **F8**: switch between Players and Leader.
- **F9**: start or pause automation.
- **F10**: exit the script.

## Requirements and compatibility

- Windows.
- To run the source file, install [AutoHotkey v2.0.19](https://github.com/AutoHotkey/AutoHotkey/releases/tag/v2.0.19).
- The coordinates use a 1920x1080 game client area as their base and scale to the active game window. Keep the game window active while automation runs.

## License

This project is licensed under the MIT License. See [LICENSE](./LICENSE).

## Support

Join the [DaoPalace Discord server](https://discord.gg/brwaAZktrn) and find Joseleelsuper.
