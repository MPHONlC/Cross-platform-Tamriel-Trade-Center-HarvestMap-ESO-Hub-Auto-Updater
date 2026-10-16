Tamriel Trade Center, HarvestMap, ESO-Hub, ESOUI Auto-Updater - Changelog
====================================================================

Version: 2026.10.04.19.22 (26100419)
---------------------------

New Features (All Platforms)
  - Added optional updates for the other add-ons and libraries in your AddOns folder: setup now asks whether to keep them up to date. When it's on, the updater compares them with ESOUI every 6 hours, installs newer versions and keeps the previous copy in Backups/AddOns for 30 days. Linked folders, HarvestMapData and the ESO-Hub add-ons (which already update from ESO-Hub) are left alone.
  - Updated the last 30 days of trade history from the Auto-Updater Database Template. When a newer template exist, its TTC and ESO-Hub listings and sales are merged into your own history without counting anything twice.
  - Changed the database template to CalVer like the updater. Copies still on 0.0.x update to it.
  - Updated uploading to Tamriel Trade Centre.
  - Fixed some item colors in the listing log.

Layout
  - Added a separate macOS script, macOS_Tamriel_Trade_Center.sh. The Linux script is now Linux-only, so a bug on one platform can be fixed without touching the other.
  - Changed versioning.

Windows Fixes
  - Fixed the known bug where pressing "b" to browse the database while the updater was looping hid the output and switched the updater from loop mode to run-once.
  - Fixed ESO-Hub sales picking up item names left over from the TTC step, which could show the wrong name or none at all.
  - Fixed history records being appended as duplicates on every scan. Windows now merges them into one line with a scan counter, same as Linux.
  - Fixed the 30-day history prune deleting the history version header and failing on short or damaged rows.
  - Fixed the database browser reloading the whole config file when you open it. It only reads your saved @Username now.

macOS Fixes
  - Fixed ESO-Hub on macOS only ever checking and updating the first of EsoTradingHub, EsoHubScanner and LibEsoHubPrices.
  - Fixed the database browser's "@Username only" filter stopping with an error on macOS.
  - Fixed rerunning setup on macOS adding a second launch command to Steam's Launch Options, and the script path being quoted in a way that broke Steam's config file.
  - Changed the macOS desktop shortcut to a .command file on your Desktop that opens in Terminal.
  - Changed macOS to replace an older Linux_Tamriel_Trade_Center.sh in Unix_Tamriel_Trade_Center with the macOS script, so Steam launch options that point at the old name keep working.

Linux, macOS & Steam Deck Fixes
  - Fixed hidden runs that Steam didn't start closing after the first update whenever ESO wasn't open, so login autostart stopped almost right away. They now keep their hourly cycle, like on Windows.
  - Fixed the updater taking up to 5 seconds to close after being told to stop while waiting in the background.
  - Removed the need for rsync, and for perl outside the optional Steam launch options step. The script now checks for the tools it does need and names any that are missing.
  - Fixed setup changing the launch options of each Steam account twice when ~/.steam/steam and ~/.local/share/Steam are the same folder.

Fixes (All Platforms)
  - Added a log line naming the ESOUI file when an update of one of your add-ons fails.
  - Fixed TTC price tables never downloading after the updater installed TamrielTradeCentre for you (the add-on's version number was saved as the price table version).
  - Fixed issue where "Both (NA & EU)" uploading your TTC data to the EU server only. It now uploads to both.
  - Fixed database updates from ESOUI keeping duplicate trader location rows.
  - Fixed TTC entries borrowing the price, amount, sale time or name of the entry before them when a field was missing.
  - Fixed trader map links with a broken ping parameter, so the ESO-Hub map opens on the exact trader spot again.
  - Fixed rows without a guild showing the trader location of the row before them.
  - Fixed the HarvestMap snapshot being saved even when the download failed, which skipped the retry.
  - Fixed the database auto-repair running before the SavedVariables folder was known.
  - Fixed the price calculator breaking on item names with brackets or other special characters.
  - Fixed the price calculator listing results in a different order every run. Results are sorted by item name now.
  - Fixed the item database file order depending on the system language settings.

Windows Additions
  - Added the Linux download safety net.
  - Added LibEsoHubPrices to the missing add-on installer.
  - Added the --setup, --addon-dir and --desktop options. The desktop shortcut now passes --desktop so the log shows how the updater was started.
  - Added the log line that records the launch method (Steam, desktop shortcut, background task or double-click).
  - Added the cleanup for leftover title tags in older database files.
  - Added the Linux progress spinners with completion times for parsing, uploads, downloads, pruning and cleanup.
  - Added the HarvestMap server and local status lines.
  - Added version detection on first run for ESO-Hub add-ons you already have, so they don't all show as out of date.
  - Added skipping the EsoHubScanner upload when the file has no scanned items.
  - Added the persistent /Cache folder to the database browser, so Top 10 and price results load instantly until new data arrives.
  - Added UESP Wiki links for furniture plans, crafting motifs and style pages in the database browser.
  - Improved Top 10 and suggested prices to use the Linux math: scan-weighted prices, outliers trimmed, and at least 5 data points.
  - Improved TTC parsing speed. A 535 KB TamrielTradeCentre.lua went from about 2.2 to 0.9 seconds in testing.

Linux, macOS & Steam Deck Additions
  - Added "View / Search Database" to the database browser: search by name, guild, player or trader town, filter by source, your @Username and time, sort by date, price or name, 50 results per page.
  - Added "View Previous Extraction History", which lists what the last scan found with the same search and sorting.
  - Improved Top 10 and price calculator sorting speed, about 7 times faster on large histories.

Parity
  - Changed both scripts to share the same menus, messages, database format and results. Given the same SavedVariables, Linux, macOS and Windows should now write byte-identical history and database files.


Version: 6.0
---------------------------

Windows Updates
  - The Offline Database Browser and the Outlier Price Calculator have been ported over (You will need the modern "Windows Terminal" app to use the clickable rich text URLs).
  - Folder Organization: Overhauled the folder structure so all the files are now organized in \Database, \Logs, and \Temp folders to keep the directory clean.
  - A huge shoutout to @Drakius192 for helping me test the Windows version!
  - Known Bug: Pressing "b" to browse the database while the script is actively looping causes a bug. Please be aware of this while a fix is being worked on.

Performance & UI Upgrades (Linux / Steamdeck / macOS)
  - Note: Some features have been temporarily removed while we investigate a bug affecting those specific functions.
  - Metadata Checks: I completely ripped out the heavy byte-by-byte file comparisons and replaced them with instant metadata checks.
  - Live Loading Spinners: Added live rotating loading spinning animation across the entire script for all uploads, downloads and extractions, with exact completion times.
  - Persistent Cache: The database browser now uses a persistent /Cache folder so your heavy math calculations load instantly if you haven't scanned any new data.
  - Cleanup: The cleanup now outputs a transparent, targeted list of exactly what temporary files were deleted from your system. (for ease of mind)

Logging & Maintenance (Linux / Steamdeck / macOS)
  - Log OS Identification: logs now append the specific operating system (Linux / Steamdeck / macOS) to help identify platform specific issues (applies to both Simple and Detailed logs).
  - Log Maintenance: Implemented a self cleanup cycle that automatically prunes log entries older than 3 days (for both Simple and Detailed modes) so you don't have to worry logs are taking space.
  - Session Tracking: The script now logs exactly how you launched it (Steam, Desktop, or Terminal) and precisely when it was closed, making it much easier to see why or when it stopped running.
  - Cleanup Logging: every deleted file or folder now has a precise timestamp.

Database & Data Merging (All Platforms)
  - Smart Data Merging: The history database no longer blindly appends duplicate scans that bloat your file size. It now groups identical listings, merges new buyers and sellers onto a single line, and tracks them with a scan counter.
  - Database Self-Repair: The database will now automatically strip corrupted data and fix missing colors from older versions.
  - ESO-Hub Parsing: The parser no longer ignores "Unknown Items" and will save the sales to automatically backfill the names on future scans.

New Features (All Platforms)
  - Interactive Map Pings: TTC Kiosk IDs are now perfectly merged with ESO-Hub zone data! When you click a trader location link in the terminal, it will open the ESO-Hub Interactive Map with an exact coordinate ping showing you precisely where they are. Huge thanks to @Woeler for providing the ping info!
  - UESP Wiki Links: Added links to the UESP Wiki for Furniture Plans (Blueprints, Praxis, Design, etc.) and (Crafting Motifs/Style Pages), so you can view item appearances and details directly from the terminal.
  - Targeted Username Tracking: You can now set an exact @Username in the settings to toggle a personal filter, letting you view a targetted Top Selling and Highest Grossing stats while entirely ignoring global data.
  - Time & Source Filters: Added new database filters so you can narrow the data down to the Past 1, 2, or 3 weeks, and explicitly filter by TTC or ESO-Hub data sources.

Fixes & Improvements
  - Fixed an issue where personal TTC listings sometimes lacked a seller name (it now injects your @AccountName automatically).
  - Fixed a bug where LibEsoHubPrices.zip could download corrupted if the script was run in Silent mode.
  - Fixed TTC uploads failing to trigger if the local data extraction was skipped in Silent mode.
  - Updated the Steam Launch Option injector so it carries over your existing steam launch commands without overwriting them.
  - Improved process detection for the game client to ensure the script always knows when ESO is running.
  - Fixed Linux desktop environment caching so the shortcut icon actually refreshes properly.
  - Fixed a typo ("Vive City" -> "Vivec City") and added several missing trader NPCs and locations. (more I probably have not covered)
  - Shortcut Bug: I've fixed a bug from the setup wizard regarding creation of desktop shortcut to automatically find and wipe any old or duplicate shortcuts, it will now properly create updated desktop shortcuts.
  - Added 3rd Option to Update EU & NA Pricetables at the same time. (thanks to @Hyborem for the suggestion)
  - (Map URL now contains precise ping data, e.g., "https://eso-hub.com/en/interactive-map?map=1858&ping=745.346%3B782.579")

Version: 5.0
---------------------------

  - Small patch for Steamdeck Desktop Mode not showing the terminal. (Thanks to @AHB182)

Version: 4.9
---------------------------

  - Updated Extraction parser to work in tandem with "TamrielTradeCentre.lua" and "EsoTradingHub.lua" Savedvariables to cross-reference ItemID with their Item Names. (if you have unknown items on ESO-HUB extraction, thats because you need ttc saved variables to display them properly. Template Database provided if you don't use TTC)
  - Updated Kiosk Map Dictionary & Fixed Guild Trader location display, the script will now generate clickable Interactive Map URLs for any trader. (thanks to @cyxui for providing kiosk ID and ESO-HUB for their Interactive map) (I may or may not have covered all traders, Interactive map pings are being worked on for next update)
  - More Fixes for Steamdeck, force download of "TamrielTradeCentre", "EsoHubScanner" "EsoTradingHub" "LibEsoHubPrices" "HarvestMap" "HarvestMapData" addons if they are missing and properly enable them on "AddOnSettings.txt" (since its hard for steamdeck users to type y/n on terminal this is now forced, they can choose to disable addons in-game. thanks for @AHB182 for painstakingly testing this on steamdeck. Linux and MacOS will be prompted if they want to install said missing addons, it wont be forced for them.)
  - Added Folder Organization & Migration, Implemented subfolder structure (/Database, /Logs, /Temp) with automatic migration for older files on older versions of this script. (Databases still need to be re-created)
  - Updated File Migrations to accommodate recent changes. (needs to re-run setup to update old version)
  - Updated Process Detection
  - Updated Variable Assignments
  - Updated Relative time mathematical comparison
  - Updated Item Quality Color Math Logic (I haven't covered all of them, some items will default to white quality color)
  - Updated Database & History Sorting Logic
  - Changed Steamdeck forced to --silent mode regardless of choice on gamemode/gamescope. (script can still be run on desktop mode visibly)
  - Changed Steamdeck notification back to notify-send from zenity
  - No new updates for Windows.

Version: 4.3
---------------------------

  - Added Database & History Browser, track your trade data in LTTC_History.db for 90 days, allowing you to search through past sales and listings.
  - Added Price Calculator A new "Suggested Price Calculator" function uses outlier elimination (trimming the top/bottom 10% of data) to provide more accurate market prices directly in your terminal.
  - Added ESO-Hub Secure Login to upload scanned data with your user token, which is then stored in the config file while your user & password is wiped from memory. (you can still upload without logging in)
  - Some fixes to steamdeck (still require more test)

Version: 4.1 (Windows)
---------------------------

  - Added ESO-Hub Secure Login to upload scanned data with your user token, which is then stored in the config file while your user & password is wiped from memory.

Version: 4.0
---------------------------

  - Added & Improved extraction of local sales, listings, and scans on the terminal with clickable URLs (if enabled, kept windows version simple for now as it is not my main OS and I'm limited to testing).
  - Changed where the script installs itself and its configuration files to be moved on your Documents folder instead of the ESO game directory. (not fully tested on macOS)
  - Added API integrations for TTC & ESO-Hub to download the latest data versions and upload your local scans and sales data to their respective servers.
  - Added Native OS Notifications (Windows Action Center, Linux notify-send, macOS osascript) to summarize update statuses. (not fully tested on macOS)
  - Added Logs to track script events and item extractions (if enabled).
  - Added System Tray Icon for "Windows version only" when script is run as hidden in the background, can now be registered as a scheduled task.
  - Added a lock to only allow a single instance of the script to run to prevent multiple updaters from running simultaneously.
  - Steam localconfig.vdf files are now safely backed up with timestamps before launch options are injected.
  - Added Addon Detection to read your AddOnSettings.txt to automatically skip updates for addons you you don't have installed.
  - Script will now kill itself if ran via Steam Launch Options and it detects the game is no longer running.
  - PriceTable downloads now checks TTC/ESO-Hub API for new versions and compares it to your local version if it matches it will skip the download else downloads the new Data.
  - HarvestMap data sync now checks if you have new data before merging with the servers else skips it.
  - Changed Data downloads to Daily for TTC and twice a day for ESO-Hub (as long as the data table version is different from your local version the script will Download the new Data), Data Uploads to every hour (when there is data to be uploaded).
  - Added Disclaimer & Credits ***

Version: 3
---------------------------

  - Added initial script setup.
  - Added automated Steam Launch Options injection functionality for Steam across Linux, macOS, and Windows. (macOS & Windows needs testing)
  - Added macOS support (needs testing)
  - Added directory self check that automatically forces setup to run if the script or config files are missing from the game folder.
  - Added Harvest Map Data Uploader & Downloader
  - Added ESO-Hub weekly Price Data Downloader (tracks and skips if data has been downloaded this week)
  - Changed TTC Price Data Download Timer to 1 hour download cooldown, it will now strictly record the timestamp of the last attempt regardless of success or failure to prevent server spam. (now tracks and skip if data has been downloaded recently 1 hour cd)
  - Updated Default Addon directory locations

Version: 2.3 (2025-05-20)
---------------------------

  - Added Desktop Shortcuts (credits to mccalli)
  - No other Changes

Version: 2.3 (2023-07-26)
---------------------------

  - Update

Version: 2.2 (2023-03-01)
---------------------------

  - Added Windows Version by dbojan. (if you are having problems running TTC.exe on Windows due to outdated .net)
  - It uses tar from relatively newer version of windows 10.
  - Slightly modified the original code by dbojan, and created 3 versions. (5-mins-looping-scripts, Looping-with-user-Input, Single-use-scripts.)
  - Included the original code by dbojan.

Version: 2.2 (2023-03-01)
---------------------------

  - Added EU counterpart. (should work as the NA versions let me know if there are problems.)

Version: 2.1 (2022-08-15)
---------------------------

  - Update

Version: 2.1 (2022-08-12)
---------------------------

  - Fixed an Issue resulting on the script to not update "PriceTable files" even tho the script outputs that it did.

Version: 2 (2021-12-11)
---------------------------

  - Update

Version: 1 (2021-12-08)
---------------------------

  - Initial Release
