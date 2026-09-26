# Cat-Printer

## Summary

Fork of [mrbrandao/Cat-Printer](https://github.com/mrbrandao/Cat-Printer): print to Bluetooth cat printers on Linux. Dependencies are fixed. Install is simpler (`pyproject.toml`, PEP 518 and PEP 621). Tested on **Ubuntu 26.04.1 LTS**.

## Features

- Web UI, CLI, and Docker/Podman (port 8095)
- Models: `GB01`, `GB02`, `GB03`, `GT01`, `YT01`, `MX05`, `MX06`, `MX08`, `MX09`, `MX10`
- `uv` / `uvx` setup; Linux gets `bleak` only
- Text and photos via ImageMagick; already-paired printers need `-s seconds,MODEL,MAC`

## Installation

```bash
sudo apt install bluez imagemagick && sudo usermod -aG bluetooth "$USER"
```

Log in again. Then install from GitHub ([pavelsr/Cat-Printer](https://github.com/pavelsr/Cat-Printer)):

```bash
uv tool install git+https://github.com/pavelsr/Cat-Printer
cat-printer --help
cat-printer-server
```

Or run without installing:

```bash
uvx --from git+https://github.com/pavelsr/Cat-Printer python printer.py --help
echo 'Hello world' | uvx --from git+https://github.com/pavelsr/Cat-Printer \
  python printer.py -s 4,MX10,AA:BB:CC:DD:EE:FF -t 24,DejaVu-Sans-Mono -
```

Or clone: `git clone https://github.com/pavelsr/Cat-Printer && cd Cat-Printer && uv sync`  
Web UI: `uv run python server.py` · CLI: `uv run python printer.py --help`  
Docker: `cd build-container && podman compose up --build` (or `docker`). See [doc/troubleshooting.md](doc/troubleshooting.md).
