# ArkTV – IPTV for ArkOS
![](https://github.com/AeolusUX/ArkTV/blob/main/ArkTV.png)

ArkTV is a lightweight, terminal-first IPTV player for handhelds and embedded Linux devices running ArkOS or any distribution with `systemd`. The project ships as a single bash script orchestrating `mpv`, `dialog`, `jq`, `curl`, and `python3` to offer a streamlined channel browser that feels native on retro consoles while remaining friendly on the desktop.

## Key Features
- Interactive channel picker rendered with `dialog`.
- Fullscreen playback through `mpv` with DRM/KMS output and IPC socket integration.
- Automatic dependency check and optional `apt` install for `mpv`, `dialog`, `jq`, `curl`, and `python3`.
- Remote channel list fetched from `channels/channels.json` in the main branch (validated before use).
- Built-in joystick support via `gptokeyb`, including automatic `/dev/uinput` permissions and controller mappings.
- On-device M3U/M3U8 import powered by `scripts/m3u_to_json.py`, which converts playlists into `channels/arktv_custom_channels.json` (persistente) e substitui a lista ativa imediatamente.
- Graceful cleanup that restores terminal state, fonts, and the `mpv.service` unit when you exit.

> **Heads-up about the on-screen keyboard (OSK):** when entering very long URLs the OSK confirm/cancel buttons may slide off the bottom of the screen. If that happens, shorten the URL (use a URL shortener) or rely on a local file path instead.

## Requirements
- ArkOS (tested on ArkOS-based handhelds) or any systemd-enabled distro where `mpv` can run against DRM/KMS.
- Root privileges to install packages, tweak console fonts, and enable `/dev/uinput`.
- Internet connectivity the first time you run the script (dependency installation and remote channel list download).
- Optional: `/opt/inttools/gptokeyb` for joystick input; ArkTV falls back to dialog-only navigation otherwise.

## Installation
1. Download or copy `ArkTV.sh` into your device’s `tools` or `ports` directory.
2. Make the script executable if necessary: `chmod +x ArkTV.sh`.
3. Launch the script from a terminal or your frontend of choice. ArkTV will:
   - Request sudo if not already running as root.
   - Check for required binaries and offer to install them via `apt`.
   - Reset the terminal, fonts, and joystick mappings before showing the main menu.

## Importing an M3U/M3U8 Playlist
1. Run `ArkTV.sh`.
2. Choose `Import playlist M3U` from the main menu.
3. Supply an HTTP/HTTPS URL or a local path to a `.m3u`/`.m3u8` file. ArkTV uses the OSK when available and falls back to dialog input otherwise.
4. The Python helper downloads (if necessary), validates `#EXTM3U/#EXTINF`, and writes the converted JSON to `channels/arktv_custom_channels.json`.
5. A playlist import passa a ser a lista padrão automaticamente nas próximas execuções (o arquivo é mantido em `channels/`). Use `Reset to default list` para remover o cache persistente e voltar ao JSON oficial.

Tip: `tests/validate_m3u.sh` demonstrates the conversion flow using `channels/sample_playlist.m3u`.

## Customizing the Default Channel List
ArkTV ships with a curated channel list hosted in this repository. To point the script at your own list:

1. **Fork the Project**
   - Visit the [ArkTV repository](https://github.com/AeolusUX/ArkTV) and create a fork.
   - Clone the fork locally or edit files directly on GitHub.

2. **Edit `channels/channels.json`**
   - Add, remove, or update entries such as:
     ```json
     [
         {"name": "My Channel", "url": "https://example.com/stream.m3u8"}
     ]
     ```
   - Keep it a valid JSON array; ArkTV rejects entries without a non-empty name or an HTTP/HTTPS URL.

3. **Repoint ArkTV**
   - In your fork, update the `DEFAULT_JSON_URL` constant near the top of `ArkTV.sh` to your raw GitHub URL, for example:
     ```
     https://raw.githubusercontent.com/<your-user>/ArkTV/main/channels/channels.json
     ```

4. **Validate & Commit**
   - Use tools like `jq` or [JSONLint](https://jsonlint.com/) to ensure the file is valid.
   - Commit and push the changes to your fork.

5. **Test**
   - Run `ArkTV.sh` on your device and confirm the menu reflects the new lineup.
   - Keep a backup of the original JSON in case you want to restore the official list.

ArkTV downloads the JSON with `curl -fsSL`, verifies the schema with `jq`, and refuses to launch the menu unless every entry passes validation. This protects the runtime from malformed playlists and missing fields.

## Development Notes
- The main launcher is pure bash; playlists are converted with Python 3’s standard library only.
- The script expects to run in a TTY. If no writable TTY is detected ArkTV exits with a helpful message.
- `scripts/m3u_to_json.py` accepts both URLs and local paths and can be used standalone:
  ```bash
  python3 scripts/m3u_to_json.py https://example.com/list.m3u -o channels/arktv_custom_channels.json
  ```
- To run the sample validation workflow:
  ```bash
  tests/validate_m3u.sh
  ```

## License
ArkTV is released under the MIT License.  
The project depends on [mpv](https://mpv.io/), which is licensed under GPLv2 or later (or LGPLv2.1 or later when built with `-Dgpl=false`). Consult mpv’s documentation for full licensing details.
