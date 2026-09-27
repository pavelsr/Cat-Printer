# Cat-Printer

## Summary

Fork of [NaitLee/Cat-Printer](https://github.com/NaitLee/Cat-Printer): print to Bluetooth cat printers on Linux. Dependencies are fixed. Install is simpler (`pyproject.toml`, PEP 518 and PEP 621). Tested on **Ubuntu 26.04.1 LTS**.

## Features

- Web UI, CLI, and Docker/Podman (port 8095)
- Models: `GB01`, `GB02`, `GB03`, `GT01`, `YT01`, `MX05`, `MX06`, `MX08`, `MX09`, `MX10`, `MX11`, `PD01`, `SC03h`, `MXTP`
- `uv` / `uvx` setup; Linux gets `bleak` only
- Text and photos via ImageMagick; already-paired printers need `-s seconds,MODEL,MAC`
- `preview.sh` to check text size before you print (text only)

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

## Text preview

`preview.sh` shows how simple text will look before you print. Use it for labels and other short text. It does not preview photos or PostScript.

You need a clone of this repo, plus ImageMagick and fontconfig. The script uses `cat-printer` if it is installed, or `uvx` if it is not.

```bash
./preview.sh
```

You can also pass the text and size:

```bash
./preview.sh --text 'Hello World' --font Courier --fit 4:2.5 --no-real-sizes
```

`--fit` is the box in centimeters. The max width is 4.88 cm. Example: `4:2.5` is width and height, `4` is width only, `:2.5` is height only.

The script writes a PBM file in `/tmp/cat-printer/` and then prints **Command for direct printing:** plus a command you can copy. That command uses `--feed 5` (about 5 mm of extra paper after the print). Change it with `--feed N`.

See `./preview.sh --help` for all options.
