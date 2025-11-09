#!/usr/bin/env python3

"""
ArkTV helper: converte playlists M3U/M3U8 em JSON compatível com ArkTV.

Principais referências:
- Formato M3U Plus (#EXTM3U / #EXTINF atributos) adotado pela comunidade IPTV.
- Boas práticas observadas em bibliotecas 2024/2025 como @iptv/playlist (JS) e ipytv (Python),
  porém reimplementadas aqui para evitar dependências extras.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional

EXTINF_PATTERN = re.compile(r"#EXTINF:(?P<duration>-?\d+)\s*(?P<attrs>[^,]*)\s*,(?P<title>.*)")
ATTRIBUTE_PATTERN = re.compile(r'([\w-]+)="([^"]*)"')
VALID_PROTOCOLS = ("http://", "https://", "rtmp://", "rtsp://", "udp://")


class M3UParserError(Exception):
    """Erro genérico do parser."""


@dataclass
class Channel:
    name: str
    url: str
    group: Optional[str] = None
    logo: Optional[str] = None
    raw_attributes: Optional[Dict[str, str]] = None

    def to_json(self) -> Dict[str, str]:
        payload: Dict[str, str] = {"name": self.name.strip(), "url": self.url.strip()}
        if self.group:
            payload["group"] = self.group.strip()
        if self.logo:
            payload["logo"] = self.logo.strip()
        return payload


def fetch_source(source: str, timeout: int = 15) -> str:
    parsed = urllib.parse.urlparse(source)
    if parsed.scheme in ("http", "https"):
        request = urllib.request.Request(
            source,
            headers={
                "User-Agent": "ArkTV-M3U-Parser/1.0 (+https://github.com/AeolusUX/ArkTV)"
            },
        )
        with urllib.request.urlopen(request, timeout=timeout) as response:
            content_type = response.headers.get_content_charset() or "utf-8"
            data = response.read()
            return data.decode(content_type, errors="replace")

    if parsed.scheme in ("", "file"):
        path = source if parsed.scheme == "" else parsed.path
        with open(path, "r", encoding="utf-8", errors="replace") as handler:
            return handler.read()

    raise M3UParserError(f"Esquema de URL não suportado: {parsed.scheme or 'desconhecido'}")


def parse_attributes(attr_blob: str) -> Dict[str, str]:
    attributes: Dict[str, str] = {}
    for key, value in ATTRIBUTE_PATTERN.findall(attr_blob or ""):
        attributes[key.lower()] = value
    return attributes


def parse_m3u_playlist(raw: str) -> List[Channel]:
    if not raw.strip():
        raise M3UParserError("Playlist vazia.")

    lines = (line.strip() for line in raw.splitlines())
    lines_iter = iter(line for line in lines if line != "")

    try:
        header = next(lines_iter)
    except StopIteration as exc:
        raise M3UParserError("Playlist não contém cabeçalho válido.") from exc

    if not header.startswith("#EXTM3U"):
        raise M3UParserError("Arquivo não inicia com #EXTM3U.")

    channels: List[Channel] = []
    pending_attrs: Optional[Dict[str, str]] = None
    pending_name: Optional[str] = None

    for line in lines_iter:
        if line.startswith("#EXTINF"):
            match = EXTINF_PATTERN.match(line)
            if not match:
                raise M3UParserError(f"Linha #EXTINF inválida: {line}")
            attrs = parse_attributes(match.group("attrs"))
            pending_attrs = attrs
            pending_name = attrs.get("tvg-name") or match.group("title").strip()
            continue

        if line.startswith("#EXTGRP"):
            # Alguns arquivos usam #EXTGRP sem #EXTINF, então preservamos
            if pending_attrs is None:
                pending_attrs = {}
            pending_attrs.setdefault("group-title", line.split(":", 1)[-1].strip())
            continue

        # URLs ou outras diretivas
        if pending_name and pending_attrs is not None and is_stream_url(line):
            channel = Channel(
                name=pending_name,
                url=line,
                group=pending_attrs.get("group-title"),
                logo=pending_attrs.get("tvg-logo"),
                raw_attributes=pending_attrs or None,
            )
            channels.append(channel)
            pending_attrs = None
            pending_name = None

    if not channels:
        raise M3UParserError("Nenhum canal válido encontrado na playlist.")

    return channels


def is_stream_url(value: str) -> bool:
    return value.lower().startswith(VALID_PROTOCOLS)


def convert_playlist(source: str, timeout: int = 15) -> List[Dict[str, str]]:
    try:
        contents = fetch_source(source, timeout=timeout)
        channels = parse_m3u_playlist(contents)
        return [channel.to_json() for channel in channels]
    except (urllib.error.URLError, OSError) as exc:
        raise M3UParserError(f"Falha ao obter playlist: {exc}") from exc


def save_output(channels: Iterable[Dict[str, str]], output: Optional[str]) -> None:
    json_payload = json.dumps(list(channels), ensure_ascii=False, indent=4)
    if output:
        with open(output, "w", encoding="utf-8") as handler:
            handler.write(json_payload)
    else:
        sys.stdout.write(json_payload + "\n")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Converte uma playlist M3U/M3U8 em JSON compatível com ArkTV."
    )
    parser.add_argument("source", help="URL (http/https) ou caminho local para playlist M3U/M3U8.")
    parser.add_argument(
        "-o",
        "--output",
        help="Caminho do arquivo de saída. Se omitido, imprime no stdout.",
    )
    parser.add_argument(
        "-t",
        "--timeout",
        type=int,
        default=15,
        help="Timeout em segundos para downloads HTTP(S). Padrão: 15.",
    )
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        channels = convert_playlist(args.source, timeout=args.timeout)
        save_output(channels, args.output)
    except M3UParserError as exc:
        parser.error(str(exc))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())


