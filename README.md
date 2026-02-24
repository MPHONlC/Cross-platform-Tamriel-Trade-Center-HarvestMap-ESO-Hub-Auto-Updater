# Tamriel Trade Center, HarvestMap & ESO-Hub Auto-Updater for Linux, macOS, SteamDeck, & Windows

An **interactive script** to fully automate your TTC, HarvestMap, and ESO-Hub data syncing without ever needing to run their respective "Client.exe" via Proton, Wine, or Java.

I originally created this because getting the TTC Client to run flawlessly on Proton/Wine/Lutris was often a hassle and I had to run not just 1 but 2 to 3 clients just to update those data (TTC, HarvestMap, and ESO-Hub). It was mainly created for Linux but has now evolved to be completely cross-platform. 

The script will automatically find your game directory, detect your addons folder, set up Steam Launch options, extract and display recent sales & listings with item qualities, generate links to their respective websites, and run silently in the background alongside the game.

## Features Include
* **Uploads Your Listings:** Automatically detects & extracts your local TTC/ESO-Hub sales/listings data **every hour** and uploads them to the TTC/ESO-Hub Servers.
* **Downloads Latest PriceTables:** Detects if there is a new version of the PriceTable and downloads it from TTC/ESO-Hub Servers **DAILY**.
* **HarvestMap Data Sync:** Uploads and merges your node data with the server's database.
* **Auto Setup:** Scans drives to locate your game and addon folders automatically, and checks *AddOnSettings.txt* to skip disabled addons.
* **Native OS Notifications:** Sends clean system notifications (Windows Action Center, Linux `notify-send`, macOS `osascript`) to summarize update statuses.

## Dependencies
This script requires the following addons to fully function:
* [Tamriel Trade Centre](https://www.esoui.com/downloads/info1245-TamrielTradeCentre.html)
* [HarvestMap](https://www.esoui.com/downloads/info57-HarvestMap.html)
* [HarvestMap-Data](https://www.esoui.com/downloads/info3034-HarvestMap-Data.html)
* [ESO-Hub Trading](https://www.esoui.com/downloads/info4095-ESO-HubTrading.html)

---

## Installation & Usage

### For Linux
1. Download the `Linux_Tamriel_Trade_Center.sh` script.
2. Open your terminal, navigate to where you downloaded it (e.g., `cd ~/Downloads`).
3. Make it executable by typing: `chmod +x Linux_Tamriel_Trade_Center.sh`
4. Run it by typing: `./Linux_Tamriel_Trade_Center.sh`
5. Follow the interactive setup.

### For Steam Deck
1. Switch your Steam Deck to **Desktop Mode**.
2. Download the `Linux_Tamriel_Trade_Center.sh` script.
3. Open the **Konsole** application and navigate to your downloads (e.g., `cd ~/Downloads`).
4. Make it executable by typing: `chmod +x Linux_Tamriel_Trade_Center.sh`
5. Run it by typing: `./Linux_Tamriel_Trade_Center.sh`
6. Follow the setup. When finished, you can safely return to Gaming Mode.

### For macOS
1. Download the `Linux_Tamriel_Trade_Center.sh` script.
2. Open the **Terminal** app and navigate to your download location (e.g., `cd ~/Downloads`).
3. Make it executable by typing: `chmod +x Linux_Tamriel_Trade_Center.sh`
4. Run it by typing: `./Linux_Tamriel_Trade_Center.sh`
5. Follow the interactive setup.

### For Windows
1. Download the `Windows_Tamriel_Trade_Center.bat` file.
2. Double-click the file to run it. 
3. Follow the interactive setup.

---

## Command Line Arguments & Steam Launch Options

* **`--silent`**
  Hides the terminal window and suppresses all text output. Useful for running the script invisibly in the background.
* **`--task`**
  Used internally for invisible background startup tasks (activates the System Tray icon on Windows).
* **`--auto`**
  Skips the interactive setup questions. It forces the script to run immediately using your saved configuration or defaults.
* **`--steam`**
  Signals the script that it was launched via Steam. It will track your game process and automatically shut down when you close ESO.
* **`--na`** or **`--eu`**
  Forces the script to download price data from the North American (US) or European (EU) Tamriel Trade Centre server.
* **`--loop`**
  Runs the updater continuously. It will update your data, wait for 60 minutes, and then update again as long as the script is open.
* **`--once`**
  Runs the updater exactly one time and then immediately closes the script.
* **`--addon-dir "/path/to/folder"`**
  Manually overrides the auto-detection and forces the script to use a specific folder for your AddOns.

---

## How It Works & Where Files Go

To keep your system clean, the script completely isolates its environment. It installs itself into a dedicated folder in your system's **Documents** directory.

* **Configuration & Database:** `lttc_updater.conf` and a local item database are saved here to remember your server, terminal preferences, and extracted data.
* **Snapshots:** Snapshot files (e.g., `lttc_ttc_snapshot.lua`) are created to compare file hashes so the script only uploads data when actual changes occur.
* **Logs:** A `.log` file is generated here tracking script events, uploads, and detailed item extractions if enabled.
* **Steam Injection & Backups:** If you choose to automatically apply the Steam Launch commands, the script modifies your `localconfig.vdf`. A timestamped backup of your original Steam config is always saved to a "Backups" folder first.

> **⚠️ NOTE:** To avoid rate-limits and "Too many requests" blocks, the background loop timer for downloading data is strictly set to update a maximum of once every 60 minutes (either way they only update daily). This timer also affects uploads, and uploads only happen when there is actual data to be uploaded.

---

## Additional Information & Default Paths

The script automatically scans your system for the following default Addon locations to speed up setup. If yours is not found, you can always enter it manually:

**Windows:**
```text
C:\Users\%USERPROFILE%\Documents\Elder Scrolls Online\live\AddOns
C:\Users\%USERPROFILE%\OneDrive\Documents\Elder Scrolls Online\live\AddOns
C:\Users\Public\Documents\Elder Scrolls Online\live\AddOns
```

**macOS:**
```text
~/Documents/Elder Scrolls Online/live/AddOns
```

**Steam Deck & Linux Native Steam:**
```text
~/.local/share/Steam/steamapps/compatdata/306130/pfx/drive_c/users/steamuser/My Documents/Elder Scrolls Online/live/AddOns/
~/.steam/steam/steamapps/compatdata/306130/pfx/drive_c/users/steamuser/My Documents/Elder Scrolls Online/live/AddOns/
```

**Flatpak Steam:**
```text
~/.var/app/com.valvesoftware.Steam/.steam/root/steamapps/compatdata/306130/pfx/drive_c/users/steamuser/My Documents/Elder Scrolls Online/live/AddOns/
```

**PortProton:**
```text
~/PortProton/prefixes/DEFAULT/drive_c/users/steamuser/My Documents/Elder Scrolls Online/live/AddOns/
```

**Lutris / Standard Wine / Bottles:**
```text
~/Games/elder-scrolls-online/drive_c/users/$USER/My Documents/Elder Scrolls Online/live/AddOns/
~/.wine/drive_c/users/$USER/My Documents/Elder Scrolls Online/live/AddOns/
~/.var/app/com.usebottles.bottles/data/bottles/bottles/NAME-OF-YOUR-BOTTLE/drive_c/users/$USER/My Documents/Elder Scrolls Online/live/AddOns/
```

## FOR (TROUBLESHOOTING)

If the updater ever gets stuck running in the background (hidden), or if you need to force quit the background loop immediately, you can use these commands to safely terminate the script on any platform.

**For Linux & Steam Deck:**
Open your Terminal (or the **Konsole** app in Steam Deck's Desktop Mode) and run this command:
```bash
pkill -f "Tamriel_Trade_Center"
rm -rf /tmp/ttc_updater*
```

**For macOS:**
Open the **Terminal** app (found in Applications > Utilities) and run:
```bash
pkill -f "Tamriel_Trade_Center"
```

**For Windows:**
Because the Windows version spawns a hidden PowerShell process, finding it in the standard Task Manager can be tricky. Open **Command Prompt (cmd)** and run this command to safely terminate only the updater:
```cmd
wmic process where "CommandLine like '%Tamriel_Trade_Center%'" call terminate
```

*Secondary Option (Windows only):* If the precise command above doesn't work for some reason, you can immediately wipe out all background PowerShell tasks by running this in the Command Prompt. 
```cmd
taskkill /F /IM powershell.exe /T
``` 
*(Warning: this will close ALL PowerShell windows you might have open).*

---

<div align="center">

### 🐞 BUG REPORTS
If you encounter any issues, please submit a report here or at:
**[ESOUI Bug Portal](https://www.esoui.com/portal.php?id=360&a=listbugs)**

</div>
