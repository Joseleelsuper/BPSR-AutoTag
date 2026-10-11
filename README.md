# BPSR-AutoTag

Automates entry and screen interactions for Wondrous Tag in Blue Protocol: Star Resonance using pixel signatures and scaled coordinates.

## What it does

- The leader handles the NPC interaction, selects Wondrous Tag, and opens Party Mode.
- The leader detects all five supported screens. Participants detect the final three screens.
- If a click does not advance the flow, the script retries after a short pause.
- When enabled, it recognizes the screen already open and continues from there.

## Quick start

1. Download and run **BPSR-AutoTag.exe** from the [latest release](https://github.com/Joseleelsuper/BPSR-AutoTag/releases/latest).
2. Open the game. The default role is **Participant**. The leader should stand near the Tag Ambassador NPC.
3. Press **F8** to switch roles, then **F9** to start or pause automation. Press **F10** to exit the script.

## Hotkeys

- **F8**: switch between Participant and Leader.
- **F9**: start or pause automation.
- **F10**: exit the script.

## Requirements and compatibility

- Windows.
- To run the source file, install [AutoHotkey v2.0.19](https://github.com/AutoHotkey/AutoHotkey/releases/tag/v2.0.19).
- Pixel signatures use a 1920x1080 client area as their base and scale to the game window size. Keep the game window active while automation runs.

## License

This project is licensed under the MIT License. See [LICENSE](./LICENSE).

## Support

Join the [DaoPalace Discord server](https://discord.gg/brwaAZktrn) and find Joseleelsuper.