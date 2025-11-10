#!/bin/bash

#-----------------------#
# ArkTV by AeolusUX     #
#-----------------------#

# --- Root privilege check ---
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi

set -euo pipefail

# --- Global Variables ---
CURR_TTY=""
TTY_CANDIDATES=("/dev/tty1" "/dev/tty0" "/dev/tty")
MPV_SOCKET="/tmp/mpvsocket"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
DEFAULT_JSON_URL="https://raw.githubusercontent.com/AeolusUX/ArkTV/refs/heads/main/channels/channels.json"
JSON_URL="$DEFAULT_JSON_URL"
JSON_FILE=""
CUSTOM_JSON_PATH="$SCRIPT_DIR/channels/arktv_custom_channels.json"
CLEANED_UP=0

# --- Functions ---

resolve_tty() {
    local candidate detected

    if detected="$(/usr/bin/tty 2>/dev/null)" && [[ -n "$detected" && -w "$detected" ]]; then
        CURR_TTY="$detected"
        return 0
    fi

    for candidate in "${TTY_CANDIDATES[@]}"; do
        if [[ -c "$candidate" && -w "$candidate" ]]; then
            CURR_TTY="$candidate"
            return 0
        fi
    done

    return 1
}

use_default_channel_list() {
    CHANNEL_SOURCE="remote"
    JSON_URL="$DEFAULT_JSON_URL"
    JSON_FILE=""
}

prefer_custom_channel_list() {
    if [[ -s "$CUSTOM_JSON_PATH" ]]; then
        CHANNEL_SOURCE="custom"
        JSON_FILE="$CUSTOM_JSON_PATH"
    fi
}

initialize_terminal() {
    if ! resolve_tty; then
        echo "ArkTV: nenhum terminal disponível. Execute a partir do EmulationStation ou de um console." >&2
        exit 1
    fi

    if [[ -w "$CURR_TTY" ]]; then
        printf "\033c" > "$CURR_TTY"
        printf "\e[?25l" > "$CURR_TTY" # Hide cursor
    fi
}

cleanup() {
    if [[ $CLEANED_UP -eq 1 ]]; then
        return
    fi
    CLEANED_UP=1

    if [[ $CHANNEL_SOURCE == "remote" ]]; then
        [[ -n "$JSON_FILE" && -f "$JSON_FILE" ]] && rm -f "$JSON_FILE"
    fi

    if [[ -w "$CURR_TTY" ]]; then
        printf "\033c" > "$CURR_TTY"
        printf "\e[?25h" > "$CURR_TTY" # Show cursor again
    fi

    if [[ ! -e "/dev/input/by-path/platform-odroidgo2-joypad-event-joystick" ]]; then
        [[ -f /usr/share/consolefonts/Lat7-Terminus20x10.psf.gz ]] && setfont /usr/share/consolefonts/Lat7-Terminus20x10.psf.gz
    fi

    pkill -f "gptokeyb -1 ArkTV.sh" >/dev/null 2>&1 || pkill -f "gptokeyb -1 arktv.sh" >/dev/null 2>&1 || true

    manage_mpv_service stop
}

ExitMenu() {
    cleanup
    exit 0
}

# Simple internet connectivity check function
check_internet() {
    if ! curl -s --connect-timeout 5 --max-time 5 "http://1.1.1.1" >/dev/null 2>&1; then
        dialog --msgbox "No internet connection detected.\nPlease check your network and try again." 6 50 > "$CURR_TTY"
        return 1
    fi
    return 0
}

check_and_install_dependencies() {
    # Check internet FIRST, before trying to install anything
    if ! check_internet; then
        ExitMenu
    fi

    local missing=()
    for cmd in mpv dialog jq curl python3; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        if ! command -v apt >/dev/null; then
            dialog --msgbox "Error: apt not found. Please install ${missing[*]} manually." 8 60 > "$CURR_TTY"
            ExitMenu
        fi
        dialog --infobox "Installing missing dependencies: ${missing[*]}..." 3 60 > "$CURR_TTY"
        if ! apt update >/dev/null 2>&1 || ! apt install -y "${missing[@]}" >/dev/null 2>&1; then
            dialog --msgbox "Error: Failed to install ${missing[*]}.\nTry manually: sudo apt update && sudo apt install -y ${missing[*]}" 8 60 > "$CURR_TTY"
            ExitMenu
        fi
    fi
}

fetch_json_file() {
    if [[ -z "$JSON_FILE" || "$CHANNEL_SOURCE" != "remote" ]]; then
        if ! JSON_FILE="$(mktemp /tmp/arktv_channels.XXXXXX)"; then
            dialog --msgbox "Error: Failed to allocate temporary file for channels." 6 60 > "$CURR_TTY"
            ExitMenu
        fi
    fi

    local tmp_file
    if ! tmp_file="$(mktemp /tmp/arktv_channels_download.XXXXXX)"; then
        dialog --msgbox "Error: Unable to create download buffer." 6 60 > "$CURR_TTY"
        ExitMenu
    fi

    if ! curl -fsSL \
        --connect-timeout 5 \
        --max-time 20 \
        --retry 2 \
        --retry-delay 1 \
        --output "$tmp_file" \
        "$JSON_URL"; then
        rm -f "$tmp_file"
        dialog --msgbox "Error: Failed to download channel list." 6 55 > "$CURR_TTY"
        ExitMenu
    fi

    mv -f "$tmp_file" "$JSON_FILE"
}

prepare_channel_file() {
    if [[ "$CHANNEL_SOURCE" == "custom" ]]; then
        if [[ -f "$CUSTOM_JSON_PATH" ]]; then
            JSON_FILE="$CUSTOM_JSON_PATH"
            return 0
        fi
        dialog --msgbox "Custom channel list not found. Falling back to default list." 6 60 > "$CURR_TTY"
        use_default_channel_list
    fi

    fetch_json_file
}

trim_string() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

find_osk_binary() {
    local candidates=(
        "/opt/inttools/osk"
        "/opt/inttools/osk-sdl"
        "/opt/inttools/osk-sdl2"
        "/usr/local/bin/osk"
        "osk"
        "osk-sdl"
        "osk-sdl2"
    )

    local candidate resolved
    for candidate in "${candidates[@]}"; do
        if [[ -x "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
        if resolved="$(command -v "$candidate" 2>/dev/null)"; then
            printf '%s' "$resolved"
            return 0
        fi
    done

    return 1
}

prompt_with_osk() {
    local prompt="$1"
    local osk_binary

    if ! osk_binary="$(find_osk_binary)"; then
        return 1
    fi

    LD_LIBRARY_PATH=/usr/local/bin "$osk_binary" "$prompt" 2>/dev/null | tail -n 1
}

import_playlist_dialog() {
    local playlist_url osk_output

    if ! osk_output="$(prompt_with_osk "Informe a URL da playlist M3U/M3U8.")"; then
        dialog --msgbox "Teclado virtual indisponível. Não foi possível solicitar a URL." 7 60 > "$CURR_TTY"
        return 1
    fi

    playlist_url="$(trim_string "$osk_output")"

    if [[ -z "$playlist_url" ]]; then
        dialog --msgbox "Nenhuma URL informada." 6 50 > "$CURR_TTY"
        return 1
    fi

    dialog --infobox "Importando playlist...\nIsso pode levar alguns segundos." 5 60 > "$CURR_TTY"

    local output
    mkdir -p "$(dirname "$CUSTOM_JSON_PATH")"
    if ! output="$(python3 "$SCRIPT_DIR/scripts/m3u_to_json.py" "$playlist_url" -o "$CUSTOM_JSON_PATH" 2>&1)"; then
        dialog --msgbox "Erro ao importar playlist:\n${output}" 8 60 > "$CURR_TTY"
        return 1
    fi

    CHANNEL_SOURCE="custom"
    JSON_FILE="$CUSTOM_JSON_PATH"

    dialog --msgbox "Playlist importada com sucesso!\nSelecione novamente para carregar os canais." 7 60 > "$CURR_TTY"
    return 0
}

restore_default_playlist() {
    use_default_channel_list
    rm -f "$CUSTOM_JSON_PATH"
    dialog --msgbox "Lista padrão restaurada." 5 45 > "$CURR_TTY"
}

check_json_file() {
    prepare_channel_file
    if [[ ! -f "$JSON_FILE" ]]; then
        dialog --msgbox "Error: Channel list file missing." 6 50 > "$CURR_TTY"
        ExitMenu
    fi
    if ! jq -e '
        type == "array"
        and length > 0
        and all(.[];
            (.name | type == "string")
            and (.name | length > 0)
            and (.url | type == "string")
            and (.url | test("^https?://"))
        )
    ' "$JSON_FILE" >/dev/null; then
        dialog --msgbox "Error: Invalid JSON format in channel list." 6 50 > "$CURR_TTY"
        ExitMenu
    fi
}

load_channels() {
    declare -gA CHANNELS
    CHANNEL_MENU_OPTIONS=()

    CHANNEL_MENU_OPTIONS+=("IMPORT" "Import playlist M3U")
    if [[ "$CHANNEL_SOURCE" == "custom" ]]; then
        CHANNEL_MENU_OPTIONS+=("RESET" "Voltar à lista padrão")
    fi

    local index=1
    while IFS= read -r name && IFS= read -r url; do
        CHANNEL_MENU_OPTIONS+=("$index" "$name")
        CHANNELS["$index"]="$url"
        ((index++))
    done < <(jq -r '.[] | .name, .url' "$JSON_FILE")

    if (( index == 1 )); then
        dialog --msgbox "No channels available to display." 6 50 > "$CURR_TTY"
        ExitMenu
    fi

    CHANNEL_MENU_OPTIONS+=("0" "Exit")
}

manage_mpv_service() {
    local action="$1"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl "$action" mpv.service >/dev/null 2>&1 || true
    fi
}

play_channel() {
    local idx="$1"
    local url="${CHANNELS[$idx]}"
    local name
    name=$(jq -r --argjson i "$((idx-1))" '.[$i].name' "$JSON_FILE")

    dialog --infobox "Starting channel: $name..." 3 50 > "$CURR_TTY"
    sleep 1

    manage_mpv_service start

    /usr/bin/mpv --fullscreen --geometry=640x480 --hwdec=auto --vo=drm --input-ipc-server="$MPV_SOCKET" "$url" >/dev/null 2>&1

    manage_mpv_service stop

    ExitMenu
}

show_channel_menu() {
    check_and_install_dependencies
    while true; do
        check_json_file
        load_channels

        local choice dialog_status
        set +e
        choice=$(dialog --output-fd 1 \
            --backtitle "ArkTV by AeolusUX v1.0" \
            --title "Select Channel" \
            --menu "Choose a channel to play:" 18 65 12 \
            "${CHANNEL_MENU_OPTIONS[@]}" \
            2>"$CURR_TTY")
        dialog_status=$?
        set -e

        if (( dialog_status != 0 )) || [[ -z "$choice" || "$choice" == "0" ]]; then
            ExitMenu
        fi

        case "$choice" in
            IMPORT)
                import_playlist_dialog
                ;;
            RESET)
                restore_default_playlist
                ;;
            *)
                if [[ -n "${CHANNELS[$choice]-}" ]]; then
                    play_channel "$choice"
                else
                    dialog --msgbox "Opção inválida selecionada." 5 45 > "$CURR_TTY"
                fi
                ;;
        esac
    done
}

# --- Main execution ---

use_default_channel_list

prefer_custom_channel_list

initialize_terminal

trap cleanup EXIT SIGINT SIGTERM

export TERM=linux
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

if [[ ! -e "/dev/input/by-path/platform-odroidgo2-joypad-event-joystick" ]]; then
    [[ -f /usr/share/consolefonts/Lat7-TerminusBold22x11.psf.gz ]] && setfont /usr/share/consolefonts/Lat7-TerminusBold22x11.psf.gz
else
    [[ -f /usr/share/consolefonts/Lat7-Terminus16.psf ]] && setfont /usr/share/consolefonts/Lat7-Terminus16.psf
fi

# Joystick support setup
if command -v /opt/inttools/gptokeyb &>/dev/null; then
    [[ -e /dev/uinput ]] && chmod 666 /dev/uinput 2>/dev/null || true
    export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"
    pkill -f "gptokeyb -1 ArkTV.sh" >/dev/null 2>&1 || pkill -f "gptokeyb -1 arktv.sh" >/dev/null 2>&1 || true
    /opt/inttools/gptokeyb -1 "ArkTV.sh" -c "/opt/inttools/keys.gptk" >/dev/null 2>&1 &
else
    dialog --infobox "gptokeyb not found. Joystick control disabled." 5 65 > "$CURR_TTY"
    sleep 2
fi

show_channel_menu