[SIZE="5"][COLOR="SeaGreen"]Tamriel Trade Center, HarvestMap, ESO-Hub, ESOUI Auto-Updater[/COLOR] for [COLOR="RoyalBlue"]Linux, macOS, SteamDeck, & Windows[/COLOR][/SIZE]

[i]An interactive, cross-platform script that fully automates your TTC, HarvestMap, and ESO-Hub data syncing without ever needing to run their respective "Client.exe" files via Proton, Wine, or Java.[/i]

I originally built this because getting the TTC Client to run flawlessly on Proton/Wine/Lutris was a massive headache. I found myself having to run 2 or 3 different background clients just to keep my trading and harvesting data updated. What started as a personal Linux workaround has now evolved into a completely cross-platform utility for everyone.

The script automatically finds your game directory, detects your active addons, sets up your Steam Launch options, and runs silently in the background alongside your game.

[SIZE="4"][COLOR="Yellow"]What This Tool Does For You[/COLOR][/SIZE]
[LIST]
[*] [b][COLOR="Lime"]Uploads Your Sales:[/COLOR][/b] Automatically detects and extracts your local TTC and ESO-Hub sales/listings data [b]every hour[/b] and pushes them to the servers.
[*] [b][COLOR="Lime"]Downloads Daily PriceTables:[/COLOR][/b] Fetches the newest PriceTable files [b]daily[/b] so your in-game price tooltips are always accurate.
[*] [b][COLOR="Lime"]HarvestMap Syncing:[/COLOR][/b] Uploads your newly discovered resource nodes, downloads the server database, and merges them seamlessly.
[*] [b][COLOR="Lime"]Market Analytics:[/COLOR][/b] Uses an outlier-elimination algorithm to calculate a true "Suggested Price" from your history, filtering out troll listings and low-ballers to give you the real market value.
[*] [b][COLOR="Lime"]Database Browser:[/COLOR][/b] Builds a 30-day local history of your Sold, Purchased, Listed, Cancelled, and Expired items. Search it by item, guild, player or trader town, sort it by date, price or name, look back at what your last scan found, and track your top grossing items directly from the terminal.
[*] [b][COLOR="Lime"]Same Tool On Every System:[/COLOR][/b] The Linux, macOS, Steamdeck and Windows scripts have the same menus and features and give the same results from the same data.
[*] [b][COLOR="Lime"]Keeps Your Add-Ons Up To Date[/COLOR][/b] [COLOR="Gray"][i](optional)[/i][/COLOR][b][COLOR="Lime"]:[/COLOR][/b] Checks the add-ons and libraries in your AddOns folder against ESOUI every 6 hours and installs newer versions, keeping the previous copy in Backups/AddOns. Linked folders, HarvestMapData and the ESO-Hub add-ons are left alone. Setup asks whether you want it.
[*] [b][COLOR="Lime"]ESO-Hub Interactive Map Links & UESP Links:[/COLOR][/b] Generates exact coordinate [b]ESO-Hub Map Links[/b] for trader locations, and provides direct [b]UESP Wiki Links[/b] so you can see what they look like before you buy or sell them.
[*] [b][COLOR="Lime"]Targeted Tracking:[/COLOR][/b] Set an exact @Username to filter and view your personal Top Selling and Highest Grossing stats while ignoring global data.
[*] [b][COLOR="Lime"]Time & Source Filters:[/COLOR][/b] Narrow database searches down to the past 1, 2, or 3 weeks, and explicitly filter by TTC or ESO-Hub data sources.
[*] [b][COLOR="Lime"]Auto Setup:[/COLOR][/b] Scans your drives to locate game folders and can automatically and carefully inject Steam launch options into Steam's [i]localconfig.vdf[/i].
[/LIST]

[SIZE="4"][COLOR="Yellow"]Required Addons[/COLOR][/SIZE]
[URL="https://www.esoui.com/downloads/info1245-TamrielTradeCentre.html"][color=orange]Tamriel Trade Centre[/color][/URL] • [URL="https://www.esoui.com/downloads/info57-HarvestMap.html"][color=orange]HarvestMap[/color][/URL] • [URL="https://www.esoui.com/downloads/info3034-HarvestMap-Data.html"][color=orange]HarvestMap-Data[/color][/URL] • [URL="https://www.esoui.com/downloads/info4095-ESO-HubTrading.html"][color=orange]ESO-Hub Trading[/color][/URL]

[b][COLOR="Orange"]Windows Terminal requirements[/COLOR][/b] [COLOR="Gray"][i](for clickable links)[/i][/COLOR][b][COLOR="Orange"]:[/COLOR][/b] to use the clickable rich-text URLs on Windows, you must run this script inside the modern [URL="https://apps.microsoft.com/store/detail/windows-terminal/9N0DX20HK701"][color=cyan]Windows Terminal[/color][/URL] app [COLOR="Gray"][i](default on Windows 11, free via the Microsoft Store on Windows 10)[/i][/COLOR]. Hold [b]Ctrl[/b] and [b]Left-Click[/b] to open a link. Standard Windows 10 PowerShell or Command Prompt [COLOR="Gray"][i](CMD)[/i][/COLOR] hosts do not support the modern hyperlink standard, so links appear as plain text there instead.

[SIZE="4"][COLOR="Orange"]What You Need[/COLOR][/SIZE]
Nothing extra to download or install:
[LIST]
[*] [b]Windows 10 [COLOR="Gray"][i](version 1803 or newer)[/i][/COLOR] and Windows 11:[/b] it runs on Windows PowerShell and [COLOR="Plum"]curl.exe[/COLOR]. Windows Terminal is optional and only gives you clickable links.
[*] [b]macOS:[/b] everything it uses [COLOR="Gray"][i](bash, curl, unzip, awk, perl, osascript)[/i][/COLOR].
[*] [b]Linux and Steam Deck:[/b] it needs bash, curl, unzip, awk, sed, grep and find, which come with most desktop Linux installs. If one is missing, the script tells you which one and stops. perl is only used when setup adds the Steam launch options for you; without it, setup shows the line for you to paste into Steam yourself.
[/LIST]

[SIZE="5"][COLOR="DarkOrchid"]Installation & Usage[/COLOR][/SIZE]

[b][COLOR="RoyalBlue"]Linux / Steam Deck[/COLOR][/b] [COLOR="Gray"][i](Desktop Mode)[/i][/COLOR][b][COLOR="RoyalBlue"]:[/COLOR][/b]
1. Download [COLOR="Plum"]Linux_Tamriel_Trade_Center.sh[/COLOR].
2. Open your terminal/Konsole and navigate to the file.
3. Make it executable: [COLOR="Plum"]chmod +x Linux_Tamriel_Trade_Center.sh[/COLOR]
4. Run it: [COLOR="Plum"]./Linux_Tamriel_Trade_Center.sh[/COLOR]
5. Follow the interactive setup. The script handles Steam Deck-specific Proton paths automatically.

[b][COLOR="RoyalBlue"]macOS:[/COLOR][/b]
1. Download [COLOR="Plum"]macOS_Tamriel_Trade_Center.sh[/COLOR].
2. Open Terminal, navigate to the folder, and run: [COLOR="Plum"]chmod +x macOS_Tamriel_Trade_Center.sh && ./macOS_Tamriel_Trade_Center.sh[/COLOR]
3. Follow the setup prompts.

[b][COLOR="RoyalBlue"]Windows:[/COLOR][/b]
1. Download [COLOR="Plum"]Windows_Tamriel_Trade_Center.bat[/COLOR].
2. Double-click to run. [COLOR="Gray"][i](Uses a native PowerShell wrapper for background tasks and System Tray support)[/i][/COLOR]

[SIZE="4"][COLOR="Orange"]Command Line Arguments & Steam Launch Options[/COLOR][/SIZE]
[LIST]
[*] [b][COLOR="Yellow"]--silent[/COLOR][/b] - Runs with no window and no output and keeps going in the background. Without --steam, it keeps its hourly cycle going whether or not ESO is open.
[*] [b][COLOR="Yellow"]--task[/COLOR][/b] - Used by the Windows scheduled task: runs hidden and shows the tray icon. On Linux and macOS it does the same as --silent.
[*] [b][COLOR="Yellow"]--auto[/COLOR][/b] - Skips the setup prompt and runs with your saved settings. Any other option does this too.
[*] [b][COLOR="Yellow"]--steam[/COLOR][/b] - Tells the script Steam started it, so it closes when ESO closes.
[*] [b][COLOR="Yellow"]--na[/COLOR][/b] / [b][COLOR="Yellow"]--eu[/COLOR][/b] / [b][COLOR="Yellow"]--both[/COLOR][/b] - Picks which Tamriel Trade Centre megaserver price tables to keep updated.
[*] [b][COLOR="Yellow"]--loop[/COLOR][/b] - Runs continuously with a 60-minute refresh cycle. Press [b]B[/b] during the countdown to browse your database.
[*] [b][COLOR="Yellow"]--once[/COLOR][/b] - Performs a single update and exits.
[*] [b][COLOR="Yellow"]--addon-dir "/path/"[/COLOR][/b] - Manually overrides the auto-detection folder.
[*] [b][COLOR="Yellow"]--setup[/COLOR][/b] - Clears your saved settings and opens the setup wizard again.
[*] [b][COLOR="Yellow"]--desktop[/COLOR][/b] - Added by the desktop shortcut so the log shows how the script was started.
[/LIST]

[SIZE="5"][COLOR="Yellow"]How It Works & Data Safety[/COLOR][/SIZE]

Everything the updater keeps for itself lives in one folder in your [b]Documents[/b]: [i]Linux_Tamriel_Trade_Center[/i] on Linux and Steam Deck, [i]Unix_Tamriel_Trade_Center[/i] on macOS and [i]Windows_Tamriel_Trade_Center[/i] on Windows. Everything in its Temp folder is cleared after every cycle.

[CODE]Documents/Linux_Tamriel_Trade_Center/
|-- Linux_Tamriel_Trade_Center.sh   the installed copy that shortcuts and Steam start
|-- lttc_updater.conf               your setup answers and settings
|-- Backups/                        Steam localconfig.vdf copies, and AddOns/ with the previous version of each updated add-on
|-- Cache/                          saved Top 10 and price results for the database browser
|-- Database/                       LTTC_Database.db (item names), LTTC_History.db (30-day history), LTTC_AddonUpdates.db (what the add-on updater installed)
|-- Logs/                           the log file, the last scan and the last screen
|-- Snapshots/                      copies used to tell whether your SavedVariables changed
`-- Temp/                           downloads in progress, emptied after every cycle[/CODE]

[LIST]
[*] [b]What it changes in your game folder:[/b] your TTC and ESO-Hub SavedVariables are only read and uploaded, never changed. It does change these: HarvestMap's own zone files in SavedVariables are moved aside before new HarvestMap data is downloaded, exactly as HarvestMap's DownloadNewData script does; add-ons it installs or updates are written to your AddOns folder, with the previous copy kept in Backups/AddOns; and an add-on it installs for you is switched on in AddOnSettings.txt.
[*] [b]Metadata & Snapshots:[/b] Compares file timestamps against its own snapshots, so data is only uploaded when something actually changed. A failed upload is retried on the next cycle.
[*] [b]Add-on updates only when there is one:[/b] an add-on is updated only when ESOUI's AddOnVersion is higher than yours, when ESOUI has a newer upload of an add-on the updater installed, or when both version numbers have the same format and ESOUI's is higher. Anything else is left alone and noted in the log, and nothing is ever downgraded. When several ESOUI listings ship the same folder, Discontinued & Outdated ones are skipped, the one matching the version you have installed comes first, and otherwise the most recent upload wins.
[*] [b]Shared trade history:[/b] the database template on ESOUI also carries the last 30 days of trade history. When a newer template comes out, its listings and sales are merged into your own history without counting anything twice.
[*] [b]Automatic Steam Backups:[/b] Before injecting any launch options into Steam, a timestamped backup of your [i]localconfig.vdf[/i] is safely stored in the Backups folder.
[*] [b]Permissions & System Integrity:[/b]
[LIST]
[*] [b]Linux / macOS / Steam Deck:[/b] Operates entirely within user-space and [b]never requires root/sudo access[/b]. It will not touch system files.
[*] [b]Windows:[/b] Standard operation [b]does not require Administrator privileges[/b].
[/LIST]
[/LIST]

[b][COLOR="Cyan"]Note:[/COLOR][/b]For Windows it will only ask for a UAC prompt if you explicitly tell it to run as a scheduled system task.

[SIZE="4"][COLOR="Orange"]Settings[/COLOR][/SIZE]
Setup writes [i]lttc_updater.conf[/i] in the updater's Documents folder. Besides the setup answers, you can change:
[LIST]
[*] [b][COLOR="Yellow"]ENABLE_ADDON_UPDATES=true[/COLOR][/b] - Keeps your other add-ons and libraries up to date from ESOUI.
[*] [b][COLOR="Yellow"]ADDON_UPDATE_SKIP="FolderA FolderB"[/COLOR][/b] - Add-on folders that are never updated.
[*] [b][COLOR="Yellow"]AUTO_SELF_UPDATE=false[/COLOR][/b] - Stops the updater from updating itself.
[/LIST]

[SIZE="5"][COLOR="Red"]Troubleshooting / Force Quit[/COLOR][/SIZE]

[spoiler]
If the script is running hidden in the background and you need to stop it:

[b][COLOR="RoyalBlue"]Linux, Steam Deck and macOS[/COLOR][/b] [COLOR="Gray"][i](Terminal)[/i][/COLOR]:
[CODE]pkill -f "Tamriel_Trade_Center"
rm -rf /tmp/ttc_updater*[/CODE]

[b][COLOR="RoyalBlue"]Windows[/COLOR][/b] [COLOR="Gray"][i](Command Prompt)[/i][/COLOR]:
[CODE]powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*Tamriel_Trade_Center*' -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"[/CODE]

pkill -f also closes anything else with Tamriel_Trade_Center in its command line, such as an editor that has the script open. The older wmic command no longer works on current Windows 11, where Microsoft removed wmic.

[b]Last resort (Windows):[/b] close every Windows PowerShell window and task instead:
[CODE]taskkill /F /IM powershell.exe /T[/CODE]

[b][COLOR="Orange"]Warning:[/COLOR][/b] This closes ALL Windows PowerShell windows you might have open, not just this script's.
[/spoiler]

[SIZE="5"][COLOR="Yellow"]Autorun Setup[/COLOR][/SIZE]

[spoiler]
In the examples below, replace YOU with your user name. Setup already installs the script at the path shown.

[b][COLOR="RoyalBlue"]Windows:[/COLOR][/b] setup question 10 does this for you, with a hidden scheduled task or a Startup-folder shortcut.

[b][COLOR="RoyalBlue"]Linux / Steam Deck[/COLOR][/b] [COLOR="Gray"][i](Desktop Mode; Gaming Mode does not run autostart entries, so use the Steam launch options there)[/i][/COLOR]
[LIST]
[*] [b]Visible terminal at login:[/b] copy the shortcut setup made into your autostart folder:
[CODE]mkdir -p ~/.config/autostart
cp ~/.local/share/applications/Linux_Tamriel_Trade_Center.desktop ~/.config/autostart/[/CODE]
or create [i]~/.config/autostart/Linux_Tamriel_Trade_Center.desktop[/i] yourself:
[CODE][Desktop Entry]
Type=Application
Name=Linux Tamriel Trade Center
Exec=/home/YOU/Documents/Linux_Tamriel_Trade_Center/Linux_Tamriel_Trade_Center.sh --loop
Terminal=true[/CODE]
[*] [b]Hidden at login:[/b] create [i]~/.config/autostart/Linux_Tamriel_Trade_Center_Hidden.desktop[/i]:
[CODE][Desktop Entry]
Type=Application
Name=Linux Tamriel Trade Center (Hidden)
Exec=/home/YOU/Documents/Linux_Tamriel_Trade_Center/Linux_Tamriel_Trade_Center.sh --silent --loop
Terminal=false[/CODE]
[/LIST]

[b][COLOR="RoyalBlue"]macOS[/COLOR][/b]
[LIST]
[*] [b]Visible Terminal at login:[/b] open [b]System Settings > General > Login Items[/b], click [b]+[/b] and pick [i]macOS_Tamriel_Trade_Center.command[/i] on your Desktop (setup's shortcut). Without that shortcut, copy the script, rename the copy to end in [b].command[/b] and pick that.
[*] [b]Hidden at login:[/b] create [i]~/Library/LaunchAgents/com.lttc.autoupdater.plist[/i]:
[CODE]<?xml version="1.0" encoding="UTF-8"?>
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
</plist>[/CODE]
Then run [COLOR="Plum"]launchctl load ~/Library/LaunchAgents/com.lttc.autoupdater.plist[/COLOR] in Terminal. It starts now and at every login. If macOS asks whether bash may access your Documents folder, allow it; the updater keeps its files there.
[/LIST]
[/spoiler]

[center]
[SIZE="5"][COLOR="Red"]License[/COLOR][/SIZE]

Copyright © 2021-2026 [COLOR="#FF69B4"]@APHONlC[/COLOR]. All rights reserved. See LICENSE.md

For permissions or inquiries, contact [COLOR="#FF69B4"]@APHONlC[/COLOR] on ESOUI.

[b]Disclaimer:[/b]
[b]Data Sources:[/b] Tamriel Trade Centre, HarvestMap, and ESO-Hub. This tool is a third-party utility and is not officially affiliated with the addon authors.
[b]Licensing Boundary:[/b] The all-rights-reserved terms above cover only this script's own code and logic. I do not claim ownership of the names, trademarks, or brands of the third-party providers integrated here [COLOR="Gray"][i](TTC, ESO-Hub, HarvestMap, and UESP)[/i][/COLOR], nor does this license grant any rights to those addons or override their respective Terms of Service.
[b]Liability:[/b] Provided "as is." Always back up your SavedVariables folder!

[b][COLOR="Orange"]Testers & Suggestions:[/COLOR][/b]
[color="#FF69B4"]@Drakius192[/color]
[color="#FF69B4"]@Hyborem[/color]
[color="#FF69B4"]@AHB182[/color]
[color="#FF69B4"]@cyxui[/color]
[color="#FF69B4"]@Woeler[/color]
[color="#FF69B4"]@HeyIt'sAmber[/color]
[color="#FF69B4"]@mccalli[/color]
[color="#FF69B4"]@dbojan[/color]

[b][color=#9CD04C]Check out my other addons/projects:[/color][/b]

[url="https://www.esoui.com/downloads/fileinfo.php?id=4388#info"][color=#fa9c1b]Auto Lua Memory Cleaner[/color][/url]
[url="https://www.esoui.com/downloads/fileinfo.php?id=4116#info"][color=#fa9c1b]Permanent Memento[/color][/url]
[url="https://www.esoui.com/downloads/fileinfo.php?id=3249#info"][color=#fa9c1b]Tamriel Trade Center, HarvestMap, ESO-Hub, ESOUI Auto-Updater[/color][/url] [COLOR="Gray"][i](Linux, macOS, SteamDeck, & Windows)[/i][/COLOR]

[b][color=#ff3300][SIZE="4"]Bug Reports[/SIZE][/color][/b]
If you encounter any issues, please submit a report here
[/center]
