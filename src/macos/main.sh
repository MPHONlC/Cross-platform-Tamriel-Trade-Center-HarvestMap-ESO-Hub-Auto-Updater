#!/bin/bash

# ====================================================================================
# {macOS} Tamriel Trade Center Auto-Updater v2026.10.04.19.22
# Created by @APHONlC | Icon by @THAMER_AKATOSH
# ------------------------------------------------------------------------------------
# A utility for ESO to automate TTC, HarvestMap, ESO-Hub and ESOUI updates.
# I don't own these addons; this is just a tool to keep all their data updated.
#
# NOTICE: Your TTC and ESO-Hub SavedVariables are only read, never changed. It does move
# HarvestMap's zone files aside before downloading new data (same as HarvestMap's own
# DownloadNewData script) and writes add-ons it installs or updates into your AddOns folder.
# Keep backups anyway, just to be safe.
# ====================================================================================
# LICENSE & NOTICE
# Copyright (c) 2021-2026 @APHONlC. All rights reserved.
# - You're welcome to read this code and learn from it.
# - No re-distribution, sale or full re-upload without my written permission. That includes copies
#   that were reworded, refactored or "cleaned up" with AI; rewording doesn't remove the copyright.
# - If it breaks on a game patch and stays unupdated for more than 6 months, others may publish
#   compatibility or maintenance builds, as long as @APHONlC gets full credit, nothing is sold or
#   paywalled, and nobody claims ownership of the original code.
# - AI agents, LLMs and bots may not read, ingest, train on or otherwise use this code
#   (text-and-data-mining opt-out under Article 4 of EU Directive 2019/790).
# - Provided "as is", without warranty of any kind.
# Full terms: LICENSE.md
# ====================================================================================

# Folder guide (Documents/Unix_Tamriel_Trade_Center):
# /Backups   -> Steam localconfig.vdf copies, and AddOns/ with the previous version of each updated add-on.
# /Cache     -> saved Top 10 and price results for the database browser.
# /Database  -> LTTC_Database.db (item names), LTTC_History.db (30-day history),
#               LTTC_AddonUpdates.db (what the add-on updater installed).
# /Logs      -> the log file (UTTC.log), the last scan and the last screen.
# /Snapshots -> copies used to tell whether your SavedVariables changed.
# /Temp      -> downloads in progress.
#
# Everything in the Temp folder is cleared after every cycle.

LTTC_SELF="${BASH_SOURCE[0]}"
LTTC_ARGS=("$@")
LTTC_DEV=1 #src-only
LTTC_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" #src-only
LTTC_SELF="$LTTC_SRC/../../dist/macOS_Tamriel_Trade_Center.sh" #src-only
source "$LTTC_SRC/lib/paths.sh"
source "$LTTC_SRC/lib/esoui.sh"
source "$LTTC_SRC/lib/lifecycle.sh"
source "$LTTC_SRC/lib/logging.sh"
source "$LTTC_SRC/lib/requirements.sh"
source "$LTTC_SRC/lib/spinner.sh"
source "$LTTC_SRC/lib/instance_lock.sh"
source "$LTTC_SRC/features/database/merge.sh"
source "$LTTC_SRC/lib/game_detect.sh"
source "$LTTC_SRC/lib/config.sh"
source "$LTTC_SRC/features/addons/install.sh"
source "$LTTC_SRC/features/addons/updater.sh"
source "$LTTC_SRC/features/self/update.sh"
source "$LTTC_SRC/lib/args.sh"
source "$LTTC_SRC/lib/system.sh"
source "$LTTC_SRC/features/setup/wizard.sh"
source "$LTTC_SRC/lib/output.sh"
source "$LTTC_SRC/data/kiosk_locations.sh"
source "$LTTC_SRC/data/item_quality.sh"
source "$LTTC_SRC/features/database/repair.sh"
source "$LTTC_SRC/features/database/browser.sh"
source "$LTTC_SRC/features/database/prune.sh"
source "$LTTC_SRC/features/ttc/extract.sh"
source "$LTTC_SRC/features/ttc/upload.sh"
source "$LTTC_SRC/features/esohub/extract.sh"
source "$LTTC_SRC/features/setup/startup.sh"
source "$LTTC_SRC/lib/runtime.sh"
while true; do
    source "$LTTC_SRC/features/cycle/start.sh"
    source "$LTTC_SRC/features/database/sync.sh"
    [ "$ENABLE_LOCAL_MODE" != true ] && run_addon_updates
    source "$LTTC_SRC/features/ttc/update.sh"
    source "$LTTC_SRC/features/esohub/update.sh"
    source "$LTTC_SRC/features/harvestmap/update.sh"
    source "$LTTC_SRC/features/cycle/cleanup.sh"
    source "$LTTC_SRC/features/cycle/countdown.sh"
done