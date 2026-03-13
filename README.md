<div align="center">

# [Tamriel Trade Center, HarvestMap & ESO-Hub Auto-Updater (Linux, macOS, SteamDeck, & Windows)](https://www.esoui.com/downloads/info3249-TamrielTradeCenterHarvestMapampESO-HubAuto-UpdaterLinuxmacOSSteamDeckampWindows.html)

![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20SteamDeck-blue) ![License](https://img.shields.io/badge/license-All%20Rights%20Reserved-red) ![Game](https://img.shields.io/badge/Game-ESO-orange)

</div>

---

Hey everyone! This is an **interactive, cross-platform script** designed to fully automate your TTC, HarvestMap, and ESO-Hub data syncing without ever needing to run their respective "Client.exe" files via Proton, Wine, or Java.

I originally built this because getting the TTC Client to run flawlessly on Proton/Wine/Lutris was a massive headache. I found myself having to run 2 or 3 different background clients just to keep my trading and harvesting data updated. What started as a personal Linux workaround but has now evolved to be completely cross-platform utility for everyone.

The script automatically finds your game directory, detects your active addons, sets up your Steam Launch options, and runs silently in the background alongside your game.

**Dependencies:**
This addon requires the following addons to fully function:
* [Tamriel Trade Centre](https://www.esoui.com/downloads/info1245-TamrielTradeCentre.html)
* [HarvestMap](https://www.esoui.com/downloads/info57-HarvestMap.html)
* [HarvestMap-Data](https://www.esoui.com/downloads/info3034-HarvestMap-Data.html)
* [ESO-Hub Trading](https://www.esoui.com/downloads/info4095-ESO-HubTrading.html)

<a id="tool-title"></a>
<div align="center">

[![What This Tool Actually Does For You](https://img.shields.io/badge/What%20This%20Tool%20Actually%20Does%20For%20You-D4A017?style=for-the-badge)](#tool-title)
</div>

* <a id="uploads-sales"></a>[![Uploads Your Sales](https://img.shields.io/badge/Uploads%20Your%20Sales-forestgreen?style=flat-square)](#uploads-sales) : Automatically detects and extracts your local TTC and ESO-Hub sales/listings data **every hour** and pushes them to the servers.
* <a id="downloads-price"></a>[![Downloads Daily PriceTables](https://img.shields.io/badge/Downloads%20Daily%20PriceTables-forestgreen?style=flat-square)](#downloads-price) : Fetches the newest PriceTable files **DAILY** so your in-game price tooltips are always accurate.
* <a id="harvestmap-sync"></a>[![HarvestMap Syncing](https://img.shields.io/badge/HarvestMap%20Syncing-forestgreen?style=flat-square)](#harvestmap-sync) : Uploads your newly discovered resource nodes, downloads the server database, and merges them seamlessly.
* <a id="market-analytics"></a>[![Market Analytics](https://img.shields.io/badge/Market%20Analytics-forestgreen?style=flat-square)](#market-analytics) : Uses an **Outlier-Elimination Math** algorithm to calculate a true "Suggested Price" from your history, filtering out troll listings and low-ballers to give you the real market value.
* <a id="database-browser"></a>[![Database Browser](https://img.shields.io/badge/Database%20Browser-forestgreen?style=flat-square)](#database-browser) : Builds a 30 day local history of your Sold, Purchased, Listed, Cancelled, and Expired items. Track your **Top Grossing Items** and search your entire trade history directly from the terminal!
* <a id="map-links"></a>[![ESO-Hub Interactive Map links (with Pings) & UESP Links](https://img.shields.io/badge/ESO--Hub%20Interactive%20Map%20links%20%28with%20Pings%29%20%26%20UESP%20Links-forestgreen?style=flat-square)](#map-links) : Generates exact coordinate **ESO-Hub Map Links** for trader locations, and provides direct **UESP Wiki Links** for Furniture Plans and Motifs so you can see what they look like before you buy or sell them.
* <a id="auto-setup"></a>[![Auto Setup](https://img.shields.io/badge/Auto%20Setup-forestgreen?style=flat-square)](#auto-setup) : Scans your drives to locate game folders and can automatically and carefully inject steam launch options into Steam's `localconfig.vdf`.

---

**Required Addons:**
[Tamriel Trade Centre](https://www.esoui.com/downloads/info1245-TamrielTradeCentre.html) • [HarvestMap](https://www.esoui.com/downloads/info57-HarvestMap.html) • [HarvestMap-Data](https://www.esoui.com/downloads/info3034-HarvestMap-Data.html) • [ESO-Hub Trading](https://www.esoui.com/downloads/info4095-ESO-HubTrading.html)

> [!IMPORTANT]
> **Windows Terminal Requirements** <sub>*(For Clickable Links!)*</sub>:
> * **INFO:** To use the **clickable rich-text URLs** on Windows, you must run this script inside the modern [Windows Terminal](https://apps.microsoft.com/store/detail/windows-terminal/9N0DX20HK701) app.<br><sub>*(it comes default on Windows 11, and is available for free via the Microsoft Store for Windows 10)*</sub>
> * **Usage:** To click links in the terminal, simply hold <kbd>Ctrl</kbd> and <kbd>Left-Click</kbd>.
> * **Note:** Standard Windows 10 PowerShell or Command Prompt <sub>*(CMD)*</sub> hosts *do not* support the modern hyperlink standard, so links will just appear as plain text there.

---

<a id="install-title"></a>
<div align="center">

[![INSTALLATION & USAGE](https://img.shields.io/badge/INSTALLATION%20%26%20USAGE-purple?style=for-the-badge)](#install-title)
</div>

**For Linux / Steam Deck** *(Desktop Mode)*:
1. Download `Linux_Tamriel_Trade_Center.sh`.
2. Open your terminal/Konsole and navigate to the file.
3. Make it executable: `chmod +x Linux_Tamriel_Trade_Center.sh`
4. Run it: `./Linux_Tamriel_Trade_Center.sh`
5. Follow the interactive setup! The script will handle specific Proton paths for the Steam Deck automatically.

**For macOS:**
1. Download `Linux_Tamriel_Trade_Center.sh`.
2. Open Terminal, navigate to the folder, and run: `chmod +x Linux_Tamriel_Trade_Center.sh && ./Linux_Tamriel_Trade_Center.sh`
3. Follow the setup prompts.

**For Windows:**
1. Download `Windows_Tamriel_Trade_Center.bat`.
2. Double-click to run. <sub>*(The script uses a native PowerShell wrapper for background tasks and System Tray support)*</sub>.

---

<a id="args-title"></a>
<div align="center">

[![Command Line Arguments & Steam Launch Options](https://img.shields.io/badge/Command%20Line%20Arguments%20%26%20Steam%20Launch%20Options-orange?style=for-the-badge)](#args-title)
</div>

* <a id="silent"></a>[<kbd>--silent</kbd>](#silent) : Hides the terminal window completely.
* <a id="task"></a>[<kbd>--task</kbd>](#task) : Used for invisible background tasks and activates the System Tray icon on Windows.
* <a id="auto"></a>[<kbd>--auto</kbd>](#auto) : Skips the setup wizard and runs immediately with your saved configs.
* <a id="steam"></a>[<kbd>--steam</kbd>](#steam) : Signals the script that it was launched via Steam; it will automatically close when ESO is closed.
* <a id="na"></a>[<kbd>--na</kbd>](#na) or <a id="eu"></a>[<kbd>--eu</kbd>](#eu) : Forces a specific megaserver for Tamriel Trade Centre.
* <a id="loop"></a>[<kbd>--loop</kbd>](#loop) : Runs continuously with a 60 minute refresh cycle. *(Press <kbd>B</kbd> during the countdown to browse your database!)*
* <a id="once"></a>[<kbd>--once</kbd>](#once) : Performs a single update and exits.
* <a id="addon-dir"></a>[<kbd>--addon-dir "/path/"</kbd>](#addon-dir) : Manually overrides the auto detection folder.

---

<a id="works-title"></a>
<div align="center">

[![HOW IT WORKS & DATA SAFETY](https://img.shields.io/badge/HOW%20IT%20WORKS%20%26%20DATA%20SAFETY-D4A017?style=for-the-badge)](#works-title)
</div>

I designed this script to be safe and clean. It completely isolates its environment into a dedicated folder within your **Documents** directory, utilizing structured subfolders <sub>*(\Database, \Logs, \Temp, \Backups, \Snapshots)*</sub> so it never pollutes your system. All contents in the <sub>*(\Temp)*</sub> folder are automatically nuked after every cycle to keep things tidy!

* <a id="ro-safety"></a>[![100% Read-Only Safety](https://img.shields.io/badge/100%25%20Read--Only%20Safety-blue?style=flat-square)](#ro-safety) : The script parses your `SavedVariables` to extract trade data, but it **never** writes to or modifies your original game data.
* <a id="metadata"></a>[![Metadata & Snapshots](https://img.shields.io/badge/Metadata%20%26%20Snapshots-blue?style=flat-square)](#metadata) : Uses instant timestamp checks and MD5 hashes to ensure data is only uploaded when actual changes are detected.
* <a id="backups"></a>[![Automatic Steam Backups](https://img.shields.io/badge/Automatic%20Steam%20Backups-blue?style=flat-square)](#backups) : Before injecting any launch options into Steam, a timestamped backup of your `localconfig.vdf` is safely stored in the `\Backups` folder.
* <a id="perms"></a>[![Permissions & System Integrity](https://img.shields.io/badge/Permissions%20%26%20System%20Integrity-blue?style=flat-square)](#perms) :
  * <a id="linux-perms"></a>[![Linux / macOS / Steamdeck](https://img.shields.io/badge/Linux%20%2F%20macOS%20%2F%20Steamdeck-blue?style=flat-square)](#linux-perms) : Operates entirely within user-space and **never requires root/sudo access**. It will not touch system files.
  * <a id="win-perms"></a>[![Windows](https://img.shields.io/badge/Windows-blue?style=flat-square)](#win-perms) : Standard operation **does not require Administrator privileges**.

> [!CAUTION]
> <sub>*(It will only ask for a UAC prompt if you explicitly tell it run as a scheduled system task)*</sub>.

---

<a id="quit-title"></a>
<div align="center">

[![TROUBLESHOOTING / FORCE QUIT](https://img.shields.io/badge/TROUBLESHOOTING%20%2F%20FORCE%20QUIT-red?style=for-the-badge)](#quit-title)
</div>

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
> Open **Command Prompt** <sub>*(CMD)*</sub> and run:
> ```cmd
> wmic process where "CommandLine like '%Tamriel_Trade_Center%'" call terminate
> ```

> [!CAUTION]
> > *Secondary Option: If the command above fails, you can terminate all PowerShell tasks.*
>
> ```cmd
> taskkill /F /IM powershell.exe /T
> ```

> [!WARNING]
> ***(Warning: Secondary Option will close ALL PowerShell windows you might have open)***.

---

<a id="autorun-title"></a>
<div align="center">

[![AUTORUN SETUP](https://img.shields.io/badge/AUTORUN%20SETUP-D4A017?style=for-the-badge)](#autorun-title)
</div>

**Method 1: Visible Terminal** *(Pops up when you log in)*
> [!NOTE]
> **Linux / Steam Deck:** Create a file at `~/.config/autostart/auto-updater.desktop` and paste this:
> ```ini
> [Desktop Entry]
> Type=Application
> Name=Linux/Unix Auto-Updater for TTC, HarvestMap & ESO-Hub
> Exec=/path/to/Linux_Tamriel_Trade_Center.sh --auto
> Terminal=true
> ```

* **macOS:**
  1. Rename the script to end in **.command** *(e.g., `Linux_Tamriel_Trade_Center.command`)*.
  2. Open **System Settings > General > Login Items**.
  3. Click the [+] and add your script.

**Method 2: Completely Hidden** *(Runs silently in the background)*
> [!NOTE]
> **Linux / Steam Deck:** Create a file at `~/.config/autostart/auto-updater-hidden.desktop` and paste this:
> ```ini
> [Desktop Entry]
> Type=Application
> Name=Linux/Unix Auto-Updater for TTC, HarvestMap & ESO-Hub (Hidden)
> Exec=/path/to/Linux_Tamriel_Trade_Center.sh --auto --silent
> Terminal=false
> ```

* **macOS:** Create a file at `~/Library/LaunchAgents/com.lttc.autoupdater.plist` and paste this:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "[http://www.apple.com/DTDs/PropertyList-1.0.dtd](http://www.apple.com/DTDs/PropertyList-1.0.dtd)">
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

---

<a id="license-title"></a>
<div align="center">

[![LICENSE CREDITS & USAGE](https://img.shields.io/badge/LICENSE%20CREDITS%20%26%20USAGE-red?style=for-the-badge)](#license-title)
</div>

**Copyright (c) 2021-2026 @APHONlC. All rights reserved.**

* **No Redistribution:** Please do not re-upload, mirror, or distribute this script to other platforms *(ESOUI, NexusMods, etc.)* without my explicit written permission.
* **No Public Modifications:** You may not modify, transform, or build upon this code for the purpose of public release.
* **Personal Use:** You are 100% free to tweak and modify the code for your own private, personal use.

*For permissions or inquiries, contact @APHONlC on ESOUI or GitHub.*

**How to Attribute This Work:**
<sub>*If you use, redistribute, or modify this script in your own private project, please use the following attribution:*</sub>
* **Project Name:** Tamriel Trade Center, HarvestMap & ESO-Hub Auto-Updater
* **Author:** @APHONlC
* **License:** Apache License 2.0

**Disclaimer:**
* **Data Sources:** Tamriel Trade Centre, HarvestMap, and ESO-Hub. This tool is a third-party utility and is not officially affiliated with the addon authors.
* **Licensing Boundary:** This script is licensed under **Apache 2.0**, but please note this license applies *only* to the script's code and logic I've written. I do not claim ownership of the names, trademarks, or brands of the third-party providers I've integrated <sub>*(TTC, ESO-Hub, HarvestMap, and UESP)*</sub>, nor does this license grant any rights to those addons or override their respective Terms of Service.
* **Liability:** Provided "as is." Always back up your SavedVariables folder!

---

<div align="center">

**📂 Check out my other addons:**
[Auto Lua Memory Cleaner](https://www.esoui.com/downloads/fileinfo.php?id=4388#info) • [Permanent Memento](https://www.esoui.com/downloads/fileinfo.php?id=4116#info)

<br>
<a id="bug-title"></a>

[![BUG REPORTS](https://img.shields.io/badge/BUG%20REPORTS-ff3300?style=for-the-badge)](#bug-title)

If you encounter any issues, please submit a report here or at:

**[ESOUI Bug Portal](https://www.esoui.com/portal.php?id=360&a=listbugs)**

<a id="support"></a>

[![SUPPORT](https://img.shields.io/badge/SUPPORT-ff3300?style=for-the-badge)](#support)

If this project has been useful to you, consider supporting its development:<br>
<br>
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-FFDD00?style=for-the-badge&logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/aph0nlc)

</div>
