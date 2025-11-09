# ArkTV - IPTV for ArkOS
![](https://github.com/AeolusUX/ArkTV/blob/main/ArkTV.png)

ArkTV is a lightweight, terminal-based IPTV player for Linux devices, built with bash and powered by [mpv](https://mpv.io/). It offers an intuitive menu for browsing and streaming internet TV channels, with joystick support for retro handhelds and embedded devices.

## Features
- Channel selection via `dialog` menu
- Fullscreen streaming with `mpv`
- Joystick/gamepad support via `gptokeyb`
- Auto-installs dependencies (`mpv`, `dialog`, `jq`, `curl`, `python3`)
- Fetches and validates channel lists from a JSON file hosted on GitHub (rejects entradas sem `name`/`url` válidos)
- Importa playlists M3U/M3U8 diretamente pelo menu e converte para JSON local automaticamente

## Requirements
- Ambiente ArkOS ou qualquer distribuição com `systemd` ativo (o script inicia/para `mpv.service`)
- Acesso root (para instalar dependências, ajustar fontes do console e habilitar `/dev/uinput`)
- Conexão com a internet e os binários `curl`, `mpv`, `jq`, `dialog`, `python3`

## Installation
1. Download or copy the `ArkTV.sh` script.
2. Place it in your device's **tools** or **ports** folder.
3. Run the script to install dependencies and start ArkTV.

## Importando uma Playlist M3U
1. Inicie o `ArkTV.sh`.
2. No menu principal escolha `Importar playlist M3U`.
3. Informe uma URL HTTP/HTTPS ou um caminho local para o arquivo `.m3u` ou `.m3u8`.
4. O script Python `scripts/m3u_to_json.py` fará o download, validará `#EXTM3U/#EXTINF` e criará ` /tmp/arktv_custom_channels.json`.
5. A lista importada assume o lugar da lista padrão imediatamente. Use a opção `Voltar à lista padrão` para retornar ao JSON oficial.

> Dica: `tests/validate_m3u.sh` demonstra a conversão usando a playlist de exemplo `channels/sample_playlist.m3u`.

## Modifying the Channel List
ArkTV uses a JSON file hosted on GitHub to define channels. To customize it manualmente:

1. **Fork the Repository**:
   - Visit the [ArkTV GitHub repository](https://github.com/AeolusUX/ArkTV).
   - Click "Fork" to create your own copy.
   - Clone your forked repository or edit directly on GitHub.

2. **Edit the JSON File**:
   - Locate `channels.json` in your forked repository.
   - Open in a text editor (e.g., VS Code) or GitHub’s online editor.
   - **Add a Channel**:
     ```json
     [
         ...,
         {"name": "New Channel", "url": "https://example.com/stream.m3u8"}
     ]
     ```
   - **Remove a Channel**: Delete the object (e.g., `{"name": "A2Z SD", "url": "..."}`) and adjust commas.
   - **Update a Channel**: Modify `name` or `url` (e.g., `{"name": "HBO HD", "url": "new-url"}`).


3. **Update ArkTV Configuration**:
   - Open `ArkTV.sh` in your forked repository.
   - Edit **line 18** to point to your JSON file URL (e.g., `https://raw.githubusercontent.com/YourUsername/ArkTV/main/channels.json`).

4. **Validate and Save**:
   - Validate JSON using [JSONLint](https://jsonlint.com/).
   - Ensure no trailing commas or missing brackets.
   - Commit and push changes to your forked repository.

5. **Test**:
   - Run ArkTV to verify the updated channel list.
   - Backup the original JSON file before editing.

**Note**: ArkTV baixa o JSON para um arquivo temporário via `curl -fsSL` e só monta o menu se todos os canais possuírem `name` e `url` HTTP/HTTPS válidos. Use um validador (ou o próprio `jq`) para detectar erros de sintaxe antes de subir mudanças.

## License
ArkTV is licensed under the MIT License.  
This project uses [mpv](https://mpv.io/), licensed under GPLv2 or later (or LGPLv2.1 or later if built with `-Dgpl=false`). See [mpv's license details](https://mpv.io/) for more information.
