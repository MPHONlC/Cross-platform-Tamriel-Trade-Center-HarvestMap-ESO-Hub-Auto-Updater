<div align="center">

# Tamriel Trade Center, HarvestMap, ESO-Hub, ESOUI Auto-Updater

*An interactive, cross-platform script that fully automates your TTC, HarvestMap, and ESO-Hub data syncing without ever needing to run their respective "Client.exe" files via Proton, Wine, or Java.*

![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20SteamDeck-blue?style=flat-square) ![License](https://img.shields.io/badge/license-All%20Rights%20Reserved-fa9c1b?style=flat-square) ![Game](https://img.shields.io/badge/Game-ESO-orange?style=flat-square)

</div>

I originally built this because getting the TTC Client to run flawlessly on Proton/Wine/Lutris was a massive headache. I found myself having to run 2 or 3 different background clients just to keep my trading and harvesting data updated. What started as a personal Linux workaround has now evolved into a completely cross-platform utility for everyone.

The script automatically finds your game directory, detects your active addons, sets up your Steam Launch options, and runs silently in the background alongside your game.

## What This Tool Does For You

- **Uploads Your Sales:** Automatically detects and extracts your local TTC and ESO-Hub sales/listings data **every hour** and pushes them to the servers.
- **Downloads Daily PriceTables:** Fetches the newest PriceTable files **daily** so your in-game price tooltips are always accurate.
- **HarvestMap Syncing:** Uploads your newly discovered resource nodes, downloads the server database, and merges them seamlessly.
- **Market Analytics:** Uses an outlier-elimination algorithm to calculate a true "Suggested Price" from your history, filtering out troll listings and low-ballers to give you the real market value.
- **Database Browser:** Builds a 30-day local history of your Sold, Purchased, Listed, Cancelled, and Expired items. Search it by item, guild, player or trader town, sort it by date, price or name, look back at what your last scan found, and track your top grossing items directly from the terminal.
- **Same Tool On Every System:** The Linux, macOS, Steamdeck and Windows scripts have the same menus and features and give the same results from the same data.
- **Keeps Your Add-Ons Up To Date** <sub>*(optional)*</sub>**:** Checks the add-ons and libraries in your AddOns folder against ESOUI every 6 hours and installs newer versions, keeping the previous copy in `Backups/AddOns`. Linked folders, HarvestMapData and the ESO-Hub add-ons are left alone. Setup asks whether you want it.
- **ESO-Hub Interactive Map Links & UESP Links:** Generates exact coordinate ESO-Hub Map Links for trader locations, and provides direct UESP Wiki Links so you can see what they look like before you buy or sell them.
- **Targeted Tracking:** Set an exact @Username to filter and view your personal Top Selling and Highest Grossing stats while ignoring global data.
- **Time & Source Filters:** Narrow database searches down to the past 1, 2, or 3 weeks, and explicitly filter by TTC or ESO-Hub data sources.
- **Auto Setup:** Scans your drives to locate game folders and can automatically and carefully inject Steam launch options into Steam's `localconfig.vdf`.

## Required Addons

[Tamriel Trade Centre](https://www.esoui.com/downloads/info1245-TamrielTradeCentre.html) • [HarvestMap](https://www.esoui.com/downloads/info57-HarvestMap.html) • [HarvestMap-Data](https://www.esoui.com/downloads/info3034-HarvestMap-Data.html) • [ESO-Hub Trading](https://www.esoui.com/downloads/info4095-ESO-HubTrading.html)

> [!IMPORTANT]
> **Windows Terminal requirements** <sub>*(for clickable links)*</sub>: to use the clickable rich-text URLs on Windows, you must run this script inside the modern [Windows Terminal](https://apps.microsoft.com/store/detail/windows-terminal/9N0DX20HK701) app <sub>*(default on Windows 11, free via the Microsoft Store on Windows 10)*</sub>. Hold <kbd>Ctrl</kbd> and <kbd>Left-Click</kbd> to open a link. Standard Windows 10 PowerShell or Command Prompt *(CMD)* hosts do not support the modern hyperlink standard, so links appear as plain text there instead.

## What You Need

Nothing extra to download or install:

- **Windows 10 (version 1803 or newer) and Windows 11:** it runs on Windows PowerShell and `curl.exe`. Windows Terminal is optional and only gives you clickable links.
- **macOS:** everything it uses (`bash`, `curl`, `unzip`, `awk`, `perl`, `osascript`).
- **Linux and Steam Deck:** it needs `bash`, `curl`, `unzip`, `awk`, `sed`, `grep` and `find`, which come with most desktop Linux installs. If one is missing, the script tells you which one and stops. `perl` is only used when setup adds the Steam launch options for you; without it, setup shows the line for you to paste into Steam yourself.

## Installation & Usage

**Linux / Steam Deck** *(Desktop Mode)*:
1. Download `Linux_Tamriel_Trade_Center.sh` <sub>*(from the `dist/` folder)*</sub>.
2. Open your terminal/Konsole and navigate to the file.
3. Make it executable: `chmod +x Linux_Tamriel_Trade_Center.sh`
4. Run it: `./Linux_Tamriel_Trade_Center.sh`
5. Follow the interactive setup. The script handles Steam Deck-specific Proton paths automatically.

**macOS:**
1. Download `macOS_Tamriel_Trade_Center.sh` <sub>*(from the `dist/` folder)*</sub>.
2. Open Terminal, navigate to the folder, and run: `chmod +x macOS_Tamriel_Trade_Center.sh && ./macOS_Tamriel_Trade_Center.sh`
3. Follow the setup prompts.

**Windows:**
1. Download `Windows_Tamriel_Trade_Center.bat` <sub>*(from the `dist/` folder)*</sub>.
2. Double-click to run. <sub>*(Uses a native PowerShell wrapper for background tasks and System Tray support)*</sub>

## Command Line Arguments & Steam Launch Options

| Argument | Effect |
|---|---|
| <kbd>--silent</kbd> | Runs with no window and no output and keeps going in the background. Without <kbd>--steam</kbd>, it keeps its hourly cycle going whether or not ESO is open. |
| <kbd>--task</kbd> | Used by the Windows scheduled task: runs hidden and shows the tray icon. On Linux and macOS it does the same as <kbd>--silent</kbd>. |
| <kbd>--auto</kbd> | Skips the setup prompt and runs with your saved settings. Any other option does this too. |
| <kbd>--steam</kbd> | Tells the script Steam started it, so it closes when ESO closes. |
| <kbd>--na</kbd> / <kbd>--eu</kbd> / <kbd>--both</kbd> | Picks which Tamriel Trade Centre megaserver price tables to keep updated. |
| <kbd>--loop</kbd> | Runs continuously with a 60-minute refresh cycle. Press <kbd>B</kbd> during the countdown to browse your database. |
| <kbd>--once</kbd> | Performs a single update and exits. |
| <kbd>--addon-dir "/path/"</kbd> | Manually overrides the auto-detection folder. |
| <kbd>--setup</kbd> | Clears your saved settings and opens the setup wizard again. |
| <kbd>--desktop</kbd> | Added by the desktop shortcut so the log shows how the script was started. |

## How It Works & Data Safety

Everything the updater keeps for itself lives in one folder in your Documents: `Linux_Tamriel_Trade_Center` on Linux and Steam Deck, `Unix_Tamriel_Trade_Center` on macOS and `Windows_Tamriel_Trade_Center` on Windows. Everything in its `Temp` folder is cleared after every cycle.

```
Documents/Linux_Tamriel_Trade_Center/
|-- Linux_Tamriel_Trade_Center.sh   the installed copy that shortcuts and Steam start
|-- lttc_updater.conf               your setup answers and settings
|-- Backups/                        Steam localconfig.vdf copies, and AddOns/ with the previous version of each updated add-on
|-- Cache/                          saved Top 10 and price results for the database browser
|-- Database/                       LTTC_Database.db (item names), LTTC_History.db (30-day history), LTTC_AddonUpdates.db (what the add-on updater installed)
|-- Logs/                           the log file, the last scan and the last screen
|-- Snapshots/                      copies used to tell whether your SavedVariables changed
`-- Temp/                           downloads in progress, emptied after every cycle
```

- **What it changes in your game folder:** your TTC and ESO-Hub SavedVariables are only read and uploaded, never changed. It does change these: HarvestMap's own zone files in `SavedVariables` are moved aside before new HarvestMap data is downloaded, exactly as HarvestMap's `DownloadNewData` script does; add-ons it installs or updates are written to your AddOns folder, with the previous copy kept in `Backups/AddOns`; and an add-on it installs for you is switched on in `AddOnSettings.txt`.
- **Metadata & Snapshots:** Compares file timestamps against its own snapshots, so data is only uploaded when something actually changed. A failed upload is retried on the next cycle.
- **Add-on updates only when there is one:** an add-on is updated only when ESOUI's AddOnVersion is higher than yours, when ESOUI has a newer upload of an add-on the updater installed, or when both version numbers have the same format and ESOUI's is higher. Anything else is left alone and noted in the log, and nothing is ever downgraded. When several ESOUI listings ship the same folder, Discontinued & Outdated ones are skipped, the one matching the version you have installed comes first, and otherwise the most recent upload wins.
- **Shared trade history:** the database template on ESOUI also carries the last 30 days of trade history. When a newer template comes out, its listings and sales are merged into your own history without counting anything twice.
- **Automatic Steam Backups:** Before injecting any launch options into Steam, a timestamped backup of your `localconfig.vdf` is safely stored in the `Backups` folder.
- **Permissions & System Integrity:**
  - *Linux / macOS / Steam Deck:* Operates entirely within user-space and **never requires root/sudo access**. It will not touch system files.
  - *Windows:* Standard operation **does not require Administrator privileges**.

> [!NOTE]
> For Windows it will only ask for a UAC prompt if you explicitly tell it to run as a scheduled system task.

## File Structure

The three scripts people download are built from the modules in `src/`:

<details>
<summary>Show the file structure</summary>

```
Tamriel Trade Center, HarvestMap, ESO-Hub, ESOUI Auto-Updater/
|-- dist/                           the three ready-to-run scripts
|   |-- Linux_Tamriel_Trade_Center.sh
|   |-- macOS_Tamriel_Trade_Center.sh
|   `-- Windows_Tamriel_Trade_Center.bat
|-- src/
|   |-- linux/, macos/              main.sh, which loads the folders below
|   |   |-- lib/                    paths, settings, command-line options, logging, spinner, single-instance lock,
|   |   |                           required-tool check, ESOUI downloads, game and AddOns folder detection, screen output
|   |   |-- data/                   trader locations and item quality tables
|   |   `-- features/
|   |       |-- setup/              first-run wizard and the startup prompt
|   |       |-- self/               updating the updater from ESOUI
|   |       |-- addons/             installing missing add-ons and the optional add-on updater
|   |       |-- database/           item database sync, history merge, 30-day prune, repair and the database browser
|   |       |-- ttc/                TTC upload, price table download and sales extraction
|   |       |-- esohub/             ESO-Hub upload, ESO-Hub add-on updates and scan extraction
|   |       |-- harvestmap/         HarvestMap upload and data download
|   |       `-- cycle/              start of each cycle, cleanup and the countdown to the next one
|   `-- windows/                    main.ps1, launcher.bat (the part cmd runs), dev.bat (runs straight from src/),
|                                   and the same lib/, data/ and features/ folders, plus the tray icon,
|                                   single-instance and console helpers
|-- scripts/
|   |-- build.sh                    bundles src/ into dist/; --check fails when dist/ is out of date
|   |-- bump-version.sh             stamps a new date-based version into VERSION, the scripts and CHANGELOG.md
|   `-- build-template.sh           builds the ESOUI database template (item database + 30-day history) with a date-based version
|-- tests/
|   |-- run.sh                      builds, then checks that Linux, macOS and Windows give the same results
|   |-- lib/                        one test runner per platform, plus a stand-in for the ESOUI server
|   `-- fixtures/                   made-up SavedVariables, databases, ESOUI add-on list and AddOns folder
|-- CHANGELOG.md                    what changed in each version
|-- VERSION                         the current version
|-- Makefile                        make build, make check, make test, make version, make template
|-- .shellcheckrc                   lets the shell-script checker read the module files
`-- icon.ico                        the icon shortcuts use
```

</details>

`make build`, `make check`, `make test`, `make version` and `make template` run those scripts. The Windows side of `make test` needs `pwsh`.

## Settings

Setup writes `lttc_updater.conf` in the updater's Documents folder. Besides the setup answers, you can change:

| Setting | Effect |
|---|---|
| `ENABLE_ADDON_UPDATES=true` | Keeps your other add-ons and libraries up to date from ESOUI. |
| `ADDON_UPDATE_SKIP="FolderA FolderB"` | Add-on folders that are never updated. |
| `AUTO_SELF_UPDATE=false` | Stops the updater from updating itself. |

## Troubleshooting / Force Quit

<details>
<summary>Show how to stop the updater</summary>

> [!CAUTION]
> If the script is running hidden in the background and you need to stop it:
>
> **Linux, Steam Deck and macOS** (Terminal):
> ```bash
> pkill -f "Tamriel_Trade_Center"
> rm -rf /tmp/ttc_updater*
> ```
>
> **Windows** (Command Prompt):
> ```cmd
> powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*Tamriel_Trade_Center*' -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
> ```

`pkill -f` also closes anything else with `Tamriel_Trade_Center` in its command line, such as an editor that has the script open. The older `wmic` command no longer works on current Windows 11, where Microsoft removed `wmic`.

**Last resort (Windows):** close every Windows PowerShell window and task instead:
```cmd
taskkill /F /IM powershell.exe /T
```

> [!WARNING]
> This closes ALL Windows PowerShell windows you might have open, not just this script's.

</details>

## Autorun Setup

<details>
<summary>Show how to start the updater at login</summary>

In the examples below, replace `YOU` with your user name. Setup already installs the script at the path shown.

**Windows:** setup question 10 does this for you, with a hidden scheduled task or a Startup-folder shortcut.

**Linux / Steam Deck** *(Desktop Mode; Gaming Mode does not run autostart entries, so use the Steam launch options there)*

*Visible terminal at login:* copy the shortcut setup made into your autostart folder:
```bash
mkdir -p ~/.config/autostart
cp ~/.local/share/applications/Linux_Tamriel_Trade_Center.desktop ~/.config/autostart/
```
or create `~/.config/autostart/Linux_Tamriel_Trade_Center.desktop` yourself:
```ini
[Desktop Entry]
Type=Application
Name=Linux Tamriel Trade Center
Exec=/home/YOU/Documents/Linux_Tamriel_Trade_Center/Linux_Tamriel_Trade_Center.sh --loop
Terminal=true
```

*Hidden at login:* create `~/.config/autostart/Linux_Tamriel_Trade_Center_Hidden.desktop`:
```ini
[Desktop Entry]
Type=Application
Name=Linux Tamriel Trade Center (Hidden)
Exec=/home/YOU/Documents/Linux_Tamriel_Trade_Center/Linux_Tamriel_Trade_Center.sh --silent --loop
Terminal=false
```

**macOS**

*Visible Terminal at login:* open **System Settings > General > Login Items**, click **+** and pick `macOS_Tamriel_Trade_Center.command` on your Desktop (setup's shortcut). Without that shortcut, copy the script, rename the copy to end in `.command` and pick that.

*Hidden at login:* create `~/Library/LaunchAgents/com.lttc.autoupdater.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.lttc.autoupdater</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/YOU/Documents/Unix_Tamriel_Trade_Center/macOS_Tamriel_Trade_Center.sh</string>
        <string>--silent</string>
        <string>--loop</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
```
Then run `launchctl load ~/Library/LaunchAgents/com.lttc.autoupdater.plist` in Terminal. It starts now and at every login. If macOS asks whether `bash` may access your Documents folder, allow it; the updater keeps its files there.

</details>

## License

Copyright © 2021-2026 @APHONlC. All rights reserved. See LICENSE.md

For permissions or inquiries, contact @APHONlC on ESOUI.

**Disclaimer:**
- **Data Sources:** Tamriel Trade Centre, HarvestMap, and ESO-Hub. This tool is a third-party utility and is not officially affiliated with the addon authors.
- **Licensing Boundary:** The all-rights-reserved terms above cover only this script's own code and logic. I do not claim ownership of the names, trademarks, or brands of the third-party providers integrated here <sub>*(TTC, ESO-Hub, HarvestMap, and UESP)*</sub>, nor does this license grant any rights to those addons or override their respective Terms of Service.
- **Liability:** Provided "as is." Always back up your SavedVariables folder!

**Testers & Suggestions:**

<!-- TESTERS:START -->
- @Drakius192
- @Hyborem
- @AHB182
- @cyxui
- @Woeler
- @HeyIt'sAmber
- @mccalli
- @dbojan
<!-- TESTERS:END -->

**Check out my other addons/projects:**

- [Auto Lua Memory Cleaner](https://www.esoui.com/downloads/fileinfo.php?id=4388#info)
- [Permanent Memento](https://www.esoui.com/downloads/fileinfo.php?id=4116#info)
- [Tamriel Trade Center, HarvestMap, ESO-Hub, ESOUI Auto-Updater](https://www.esoui.com/downloads/fileinfo.php?id=3249#info) <sub>*(Linux, macOS, SteamDeck, & Windows)*</sub>

If this project has been useful to you, consider supporting its development. Thank you!

[![Buy Me A Coffee](https://img.shields.io/badge/Support-Buy%20Me%20A%20Coffee-FFDD00?style=flat&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/aph0nlc)

### Bug Reports

If you encounter any issues, please submit a report here
