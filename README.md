# 🛡️ [Tamriel Trade Center, HarvestMap & ESO-Hub Auto-Updater (Linux, macOS, SteamDeck, & Windows)](https://www.esoui.com/downloads/info3249-TamrielTradeCenterHarvestMapampESO-HubAuto-UpdaterLinuxmacOSSteamDeckampWindows.html)
### For 🐧 Linux, 🍎 macOS, 🎮 SteamDeck, & 🪟 Windows

![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20SteamDeck-blue)
![License](https://img.shields.io/badge/license-All%20Rights%20Reserved-red)
![Game](https://img.shields.io/badge/Game-ESO-orange)

An **interactive script** to fully automate your TTC, HarvestMap, and ESO-Hub data syncing without ever needing to run their respective "Client.exe" via Proton, Wine, or Java.

I originally created this because getting the TTC Client to run flawlessly on Proton/Wine/Lutris was often a hassle and I had to run not just 1 but 2 to 3 clients just to update those data (TTC, HarvestMap, and ESO-Hub). It was mainly created for Linux but has now evolved to be a completely cross-platform with the addition of market analytics.

The script will automatically find your game directory, detect your addons folder, set up Steam Launch options, extract and display recent scanned sales & listings with links to their respective sources, and run silently in the background alongside the game.

## ✨ Features Include
* 📤 **Uploads Your Listings:** Automatically detects and extracts your local TTC/ESO-Hub sales and listings data **every hour** and uploads them to their respective servers.
* 📥 **Downloads Latest PriceTables:** Automatically fetches the newest PriceTable files **DAILY** to ensure your in-game prices are accurate.
* 📍 **HarvestMap Data Sync:** Automatically uploads your newly discovered nodes and downloads the server version of the database then merges them.
* 📊 **Market Analytics:** Uses **Outlier-Elimination Math** to calculate "Suggested Prices" from your history, filtering out troll listings and low ball outliers to give you the true market value.
* 🗺️ **Interactive ESO-Hub Map:** Generates **ESO-Hub Map Links** for trader locations, allowing you to click and see exactly where a specific Guild Kiosk is located in the in-game world map.
* 💾 **Offline Database Browser:** Builds a 30 day local history of your Sold, Purchased, Listed, Cancelled, and Expired items. Track your **Top Grossing Items** and search your entire trade history directly from the terminal.
* ⚙️ **Auto Setup & Steam Integration:** Scans drives to locate game folders and can automatically inject launch arguments into Steam's *localconfig.vdf* (with automatic backups).

## 📦 Dependencies
This utility requires the following addons to function:
* [Tamriel Trade Centre](https://www.esoui.com/downloads/info1245-TamrielTradeCentre.html)
* [HarvestMap](https://www.esoui.com/downloads/info57-HarvestMap.html)
* [HarvestMap-Data](https://www.esoui.com/downloads/info3034-HarvestMap-Data.html)
* [ESO-Hub Trading](https://www.esoui.com/downloads/info4095-ESO-HubTrading.html)

---

> [!IMPORTANT]
> **Windows Terminal Requirements (Clickable Links):**
> * **INFO:** To utilize the **clickable links** feature on Windows, you must run this script inside the modern [Windows Terminal](https://apps.microsoft.com/store/detail/windows-terminal/9N0DX20HK701) app (default on Windows 11, available via Microsoft Store for Windows 10).
> * **Usage:** To click links in the terminal, you must hold **"Ctrl"** and **Left-Click**.
> * **Note:** Standard Windows 10 PowerShell or Command Prompt (CMD) hosts *do not* support the OSC-8 hyperlink standard and links will appear as plain text.

---

## 🚀 INSTALLATION & USAGE

### 🐧 For Linux / Steam Deck (Desktop Mode)
1. Download `Linux_Tamriel_Trade_Center.sh`.
2. Open your terminal/Konsole and navigate to the file.
3. Make it executable: `chmod +x Linux_Tamriel_Trade_Center.sh`
4. Run it: `./Linux_Tamriel_Trade_Center.sh`
5. Follow the interactive setup. The script will handle specific Proton paths for Steam Deck automatically.

### 🍎 For macOS
1. Download `Linux_Tamriel_Trade_Center.sh`.
2. Open Terminal, navigate to the folder, and run: `chmod +x Linux_Tamriel_Trade_Center.sh && ./Linux_Tamriel_Trade_Center.sh`
3. Follow the setup prompts.

### 🪟 For Windows
1. Download `Windows_Tamriel_Trade_Center.bat`.
2. Double-click to run. (The script uses a native PowerShell wrapper for background tasks and System Tray support).

---

## 💻 Command Line Arguments & Steam Launch Options
* `--silent` - Hides the terminal window.
* `--task` - Used for invisible background tasks and System Tray initialization (activates the System Tray icon on Windows).
* `--auto` - Skips setup and runs immediately with saved configs or defaults.
* `--steam` - Signals the script that it was launched via Steam; the script closes automatically when ESO is closed.
* `--na` or `--eu` - Forces a specific megaserver for Tamriel Trade Centre.
* `--loop` - Runs continuously with a 60 minute refresh cycle. *(Press 'B' during the countdown to browse your database!)*
* `--once` - Performs a single update and exits.
* `--addon-dir "/path/"` - Manually overrides the auto-detection folder.

---

## 🛠️ HOW IT WORKS & DATA SAFETY

To keep your system clean, the script completely isolates its environment in a dedicated folder within your **Documents** directory.

* **Read-Only Safety:** The script parses *SavedVariables* to extract trade data but **never** writes to or modifies your original data.
* **Snapshots & Logs:** Uses file hashing to ensure data is only uploaded when changes are detected, saving bandwidth.
* **Steam Backups:** Before modifying any Steam files, a timestamped backup of your `localconfig.vdf` is created in the "Backups" folder.
* **Database:** Local data is stored in a structured format allowing for 30 days of offline search.
* **Permissions & System Integrity:**
    * **Linux / macOS / Steam Deck:** The script operates entirely within user-space and **never requires root/sudo access**. It does not modify system files.
    * **Windows:** Standard operation **does not require Administrator privileges**. However, if you choose specific automated features (such as generating certain types of system shortcuts), the script will explicitly request a UAC prompt for that task only.
    * **Note:** On all platforms, the script is designed to be non-intrusive and will not interfere with your host OS or other running applications besides the Steam client for steam launch option injection.

---

## 🛑 TROUBLESHOOTING / FORCE QUIT

If the script is running hidden and you need to kill it:

### 🐧 Linux & Steam Deck:
```bash
pkill -f "Tamriel_Trade_Center"
rm -rf /tmp/ttc_updater*
```

### 🍎 macOS:
```bash
pkill -f "Tamriel_Trade_Center"
```

### 🪟 Windows:
Open **Command Prompt (CMD)** and run:
```cmd
wmic process where "CommandLine like '%Tamriel_Trade_Center%'" call terminate
```
*Secondary Option (Windows only): If the command above fails, you can terminate all PowerShell tasks. **(Warning: this will close ALL PowerShell windows you might have open).***
```cmd
taskkill /F /IM powershell.exe /T
```

---

## ⚙️ MANUAL AUTORUN CONFIGURATION

### **How to Autorun (Visible Terminal):**
Use this if you want the terminal window to pop up and stay visible when you log in.

* **Linux / Steam Deck:** Create a file at `~/.config/autostart/ttc-updater.desktop` and paste this:
```ini
[Desktop Entry]
Type=Application
Name=Linux/Unix Auto-Updater for TTC, HarvestMap & ESO-Hub
Exec=/path/to/Linux_Tamriel_Trade_Center.sh --auto
Terminal=true
```

* **macOS:** 1. Rename the script to end in **.command** (e.g., `Linux_Tamriel_Trade_Center.command`).
  2. Open **System Settings > General > Login Items**.
  3. Click the [+] and add your script.

### **How to Autorun:**
Use this if you want the script to run silently in the background without any windows appearing.

* **Linux / Steam Deck:** Create a file at `~/.config/autostart/ttc-updater-hidden.desktop` and paste this:
```ini
[Desktop Entry]
Type=Application
Name=Linux/Unix Auto-Updater for TTC, HarvestMap & ESO-Hub (Hidden)
Exec=/path/to/Linux_Tamriel_Trade_Center.sh --auto --silent
Terminal=false
```

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

## 📜 LICENSE

**Copyright 2021-2026 @APHONlC**

Licensed under the **Apache License, Version 2.0** (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at:

[http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, **WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND**, either express or implied. See the License for the specific language governing permissions and limitations under the License.

*For permissions or inquiries, contact @APHONlC on ESOUI or GitHub.*

---

## ⚖️ How to Attribute This Work

If you use, redistribute, or modify this script in your own project, please use the following attribution format:

* **Project Name:** Tamriel Trade Center, HarvestMap & ESO-Hub Auto-Updater
* **Author:** @APHONlC
* **License:** [Apache License 2.0](http://www.apache.org/licenses/LICENSE-2.0)
* **Original Source:** [Tamriel Trade Center, HarvestMap & ESO-Hub Auto-Updater (Linux, macOS, SteamDeck, & Windows)](https://www.esoui.com/downloads/info3249-TamrielTradeCenterHarvestMapampESO-HubAuto-UpdaterLinuxmacOSSteamDeckampWindows.html)

### Example Notice for Derived Works:
> This work includes code from the "Tamriel Trade Center, HarvestMap & ESO-Hub Auto-Updater (Linux, macOS, SteamDeck, & Windows)" by @APHONlC, licensed under the Apache License 2.0.

---

### 🎖️ Credits & Disclaimer
* **Data Sources:** Tamriel Trade Centre, HarvestMap, and ESO-Hub. This tool is a third-party utility and is not officially affiliated with the addon authors.
* **Licensing Boundary:** This script is licensed under **Apache 2.0**. This license applies *only* to the script's code and logic. It does not grant any rights to the third-party addons it interacts with, nor does it override the Terms of Service of the data providers (TTC/ESO-Hub/HarvestMap).
* **Liability:** Provided "as is." Always back up your **SavedVariables** folder.

**Check out my other addons:**
* [Auto Lua Memory Cleaner](https://www.esoui.com/downloads/fileinfo.php?id=4388#info) - Intelligent LUA garbage collection.
* [Permanent Memento](https://www.esoui.com/downloads/fileinfo.php?id=4116#info) - Automate your favorite mementos.

<div align="center">

### 🐞 BUG REPORTS
If you encounter any issues, please submit a report here or at:
**[ESOUI Bug Portal](https://www.esoui.com/portal.php?id=360&a=listbugs)**

</div>
