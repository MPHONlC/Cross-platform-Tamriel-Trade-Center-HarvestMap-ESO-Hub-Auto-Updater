missing_tools=""
for tool in curl unzip awk sed grep find; do
    command -v "$tool" >/dev/null 2>&1 || missing_tools="$missing_tools $tool"
done
if [ -n "$missing_tools" ]; then
    echo -e "\e[0;31m[!] This updater needs these tools, which are not installed:$missing_tools\e[0m"
    echo -e "\e[0;33m    Install them with your system's package manager, then run the updater again.\e[0m"
    write_ttc_log "ERROR" "Missing required tools:$missing_tools"
    exit 1
fi
