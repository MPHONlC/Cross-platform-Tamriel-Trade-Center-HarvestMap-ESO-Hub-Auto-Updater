<div align="center">

# Tamriel Trade Center, HarvestMap & ESO-Hub Auto-Updater

*An interactive, cross-platform script that fully automates your TTC, HarvestMap, and ESO-Hub data syncing without ever needing to run their respective "Client.exe" files via Proton, Wine, or Java.*

![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20SteamDeck-blue?style=flat-square) ![License](https://img.shields.io/badge/license-GPLv3-fa9c1b?style=flat-square) ![Game](https://img.shields.io/badge/Game-ESO-orange?style=flat-square)

</div>

I originally built this because getting the TTC Client to run flawlessly on Proton/Wine/Lutris was a massive headache. I found myself having to run 2 or 3 different background clients just to keep my trading and harvesting data updated. What started as a personal Linux workaround has now evolved into a completely cross-platform utility for everyone.

The script automatically finds your game directory, detects your active addons, sets up your Steam Launch options, and runs silently in the background alongside your game.

## What This Tool Does For You

- **Uploads Your Sales:** Automatically detects and extracts your local TTC and ESO-Hub sales/listings data **every hour** and pushes them to the servers.
- **Downloads Daily PriceTables:** Fetches the newest PriceTable files **daily** so your in-game price tooltips are always accurate.
- **HarvestMap Syncing:** Uploads your newly discovered resource nodes, downloads the server database, and merges them seamlessly.
- **Market Analytics:** Uses an outlier-elimination algorithm to calculate a true "Suggested Price" from your history, filtering out troll listings and low-ballers to give you the real market value.
- **Database Browser:** Builds a 30-day local history of your Sold, Purchased, Listed, Cancelled, and Expired items. Track your top grossing items and search your entire trade history directly from the terminal.
- **ESO-Hub Interactive Map Links & UESP Links:** Generates exact coordinate ESO-Hub Map Links for trader locations, and provides direct UESP Wiki Links for Furniture Plans and Motifs so you can see what they look like before you buy or sell them.
- **Targeted Username Tracking:** Set an exact @Username to filter and view your personal Top Selling and Highest Grossing stats while ignoring global data.
- **Time & Source Filters:** Narrow database searches down to the past 1, 2, or 3 weeks, and explicitly filter by TTC or ESO-Hub data sources.
- **Auto Setup:** Scans your drives to locate game folders and can automatically and carefully inject Steam launch options into Steam's `localconfig.vdf`.

## Required Addons

[Tamriel Trade Centre](https://www.esoui.com/downloads/info1245-TamrielTradeCentre.html) • [HarvestMap](https://www.esoui.com/downloads/info57-HarvestMap.html) • [HarvestMap-Data](https://www.esoui.com/downloads/info3034-HarvestMap-Data.html) • [ESO-Hub Trading](https://www.esoui.com/downloads/info4095-ESO-HubTrading.html)

> [!IMPORTANT]
> **Windows Terminal requirements** <sub>*(for clickable links)*</sub>: to use the clickable rich-text URLs on Windows, you must run this script inside the modern [Windows Terminal](https://apps.microsoft.com/store/detail/windows-terminal/9N0DX20HK701) app <sub>*(default on Windows 11, free via the Microsoft Store on Windows 10)*</sub>. Hold <kbd>Ctrl</kbd> and <kbd>Left-Click</kbd> to open a link. Standard Windows 10 PowerShell or Command Prompt *(CMD)* hosts do not support the modern hyperlink standard, so links appear as plain text there instead.

## Installation & Usage

**Linux / Steam Deck** *(Desktop Mode)*:
1. Download `Linux_Tamriel_Trade_Center.sh`.
2. Open your terminal/Konsole and navigate to the file.
3. Make it executable: `chmod +x Linux_Tamriel_Trade_Center.sh`
4. Run it: `./Linux_Tamriel_Trade_Center.sh`
5. Follow the interactive setup - the script handles Steam Deck-specific Proton paths automatically.

**macOS:**
1. Download `Linux_Tamriel_Trade_Center.sh`.
2. Open Terminal, navigate to the folder, and run: `chmod +x Linux_Tamriel_Trade_Center.sh && ./Linux_Tamriel_Trade_Center.sh`
3. Follow the setup prompts.

**Windows:**
1. Download `Windows_Tamriel_Trade_Center.bat`.
2. Double-click to run. <sub>*(Uses a native PowerShell wrapper for background tasks and System Tray support)*</sub>

## Command Line Arguments & Steam Launch Options

| Argument | Effect |
|---|---|
| <kbd>--silent</kbd> | Hides the terminal window completely. |
| <kbd>--task</kbd> | Used for invisible background tasks and activates the System Tray icon on Windows. |
| <kbd>--auto</kbd> | Skips the setup wizard and runs immediately with your saved configs. |
| <kbd>--steam</kbd> | Signals the script that it was launched via Steam; it will automatically close when ESO is closed. |
| <kbd>--na</kbd> / <kbd>--eu</kbd> | Forces a specific megaserver for Tamriel Trade Centre. |
| <kbd>--loop</kbd> | Runs continuously with a 60-minute refresh cycle. Press <kbd>B</kbd> during the countdown to browse your database. |
| <kbd>--once</kbd> | Performs a single update and exits. |
| <kbd>--addon-dir "/path/"</kbd> | Manually overrides the auto-detection folder. |

## How It Works & Data Safety

This script is designed to be safe and clean. It completely isolates its environment into a dedicated folder within your Documents directory, using structured subfolders <sub>*(\Database, \Logs, \Temp, \Backups, \Snapshots)*</sub> so it never pollutes your system. Everything in the <sub>*(\Temp)*</sub> folder is automatically cleared after every cycle.

- **100% Read-Only Safety:** The script parses your `SavedVariables` to extract trade data, but it **never** writes to or modifies your original game data.
- **Metadata & Snapshots:** Uses timestamp checks and MD5 hashes to ensure data is only uploaded when actual changes are detected.
- **Automatic Steam Backups:** Before injecting any launch options into Steam, a timestamped backup of your `localconfig.vdf` is safely stored in the `\Backups` folder.
- **Permissions & System Integrity:**
  - *Linux / macOS / Steam Deck:* Operates entirely within user-space and **never requires root/sudo access**. It will not touch system files.
  - *Windows:* Standard operation **does not require Administrator privileges**.

> [!NOTE]
> It will only ask for a UAC prompt if you explicitly tell it to run as a scheduled system task.

## Troubleshooting / Force Quit

> [!CAUTION]
> If the script is running hidden in the background and you need to kill it:
>
> **Linux & Steam Deck:**
> ```bash
> pkill -f "Tamriel_Trade_Center"
> rm -rf /tmp/ttc_updater*
> ```
>
> **macOS:**
> ```bash
> pkill -f "Tamriel_Trade_Center"
> ```
>
> **Windows:**
> Open **Command Prompt** *(CMD)* and run:
> ```cmd
> wmic process where "CommandLine like '%Tamriel_Trade_Center%'" call terminate
> ```

**Secondary option (Windows):** if the command above fails, terminate all PowerShell tasks instead:
```cmd
taskkill /F /IM powershell.exe /T
```

> [!WARNING]
> This closes ALL PowerShell windows you might have open, not just this script's.

## Autorun Setup

**Method 1: Visible Terminal** *(pops up when you log in)*

> [!NOTE]
> **Linux / Steam Deck:** create a file at `~/.config/autostart/auto-updater.desktop` and paste this:
> ```ini
> [Desktop Entry]
> Type=Application
> Name=Linux/Unix Auto-Updater for TTC, HarvestMap & ESO-Hub
> Exec=/path/to/Linux_Tamriel_Trade_Center.sh --auto
> Terminal=true
> ```

**macOS:**
1. Rename the script to end in `.command` *(e.g., `Linux_Tamriel_Trade_Center.command`)*.
2. Open **System Settings > General > Login Items**.
3. Click the [+] and add your script.

**Method 2: Completely Hidden** *(runs silently in the background)*

> [!NOTE]
> **Linux / Steam Deck:** create a file at `~/.config/autostart/auto-updater-hidden.desktop` and paste this:
> ```ini
> [Desktop Entry]
> Type=Application
> Name=Linux/Unix Auto-Updater for TTC, HarvestMap & ESO-Hub (Hidden)
> Exec=/path/to/Linux_Tamriel_Trade_Center.sh --auto --silent
> Terminal=false
> ```

**macOS:** create a file at `~/Library/LaunchAgents/com.lttc.autoupdater.plist` and paste this:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.lttc.autoupdater</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/your/Linux_Tamriel_Trade_Center.sh</string>
        <string>--auto</string>
        <string>--silent</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
```
*Then run `launchctl load ~/Library/LaunchAgents/com.lttc.autoupdater.plist` in Terminal.*

## License

GNU General Public License v3.0 (GPLv3). Copyright 2021-2026 @APHONlC.

> [!NOTE]
> A personal ask, not a license term: instead of making "another version," please give me a heads-up before mirroring/re-uploading this elsewhere or publishing your own modified version, even though GPLv3 doesn't legally require it.
>
> We can probably work on a patch or collaborate on an update instead of creating another version of the same source.
>
> Separately: AI agents, LLMs, and automated bots are not authorized to read, ingest, or train on this code - see NOTICE.md for details.

> [!NOTE]
> This tool is not created by, affiliated with, or sponsored by ZeniMax Media Inc. or its affiliates. The Elder Scrolls® and related logos are registered trademarks or trademarks of ZeniMax Media Inc. in the United States and/or other countries. All rights reserved.

For permissions or inquiries, contact @APHONlC on ESOUI or GitHub.

**Disclaimer:**
- **Data Sources:** Tamriel Trade Centre, HarvestMap, and ESO-Hub. This tool is a third-party utility and is not officially affiliated with the addon authors.
- **Licensing Boundary:** This script is licensed under GPLv3, but that license applies only to the script's own code and logic. I do not claim ownership of the names, trademarks, or brands of the third-party providers integrated here <sub>*(TTC, ESO-Hub, HarvestMap, and UESP)*</sub>, nor does this license grant any rights to those addons or override their respective Terms of Service.
- **Liability:** Provided "as is." Always back up your SavedVariables folder!

**Check out my other addons/projects:**

- [Auto Lua Memory Cleaner](https://www.esoui.com/downloads/fileinfo.php?id=4388#info)
- [Permanent Memento](https://www.esoui.com/downloads/fileinfo.php?id=4116#info)
- [Tamriel Trade Center, HarvestMap & ESO-Hub Auto-Updater](https://www.esoui.com/downloads/fileinfo.php?id=3249#info) <sub>*(Linux, macOS, SteamDeck, & Windows)*</sub>

If this project has been useful to you, consider supporting its development. Thank you!

[![Buy Me A Coffee](https://img.shields.io/badge/Support-Buy%20Me%20A%20Coffee-FFDD00?style=flat&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/aph0nlc)

### Bug Reports

If you encounter any issues, please submit a report here:
[ESOUI Bug Portal](https://www.esoui.com/portal.php?id=360&a=listbugs) | [GitHub Issue Tracker](https://github.com/MPHONlC/Cross-platform-Tamriel-Trade-Center-HarvestMap-ESO-Hub-Auto-Updater/issues)
