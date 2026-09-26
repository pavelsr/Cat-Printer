# Troubleshooting the original Cat-Printer code

This document lists problems found when running the **original** [NaitLee/Cat-Printer](https://github.com/NaitLee/Cat-Printer) code on a modern Linux host with current Python tools.

The printer is a Bluetooth Low Energy (BLE) thermal printer. The CLI is `printer.py`. The printer does not print text. It only prints a black-and-white bitmap (PBM).

---

## 1. `uv sync` / `rye sync` cannot install the project

### What you see

- `rye` is missing, or Rye is no longer maintained.
- `uv sync` fails while building `pyobjc`.
- `uv sync` fails with Hatchling:

  `Unable to determine which files to ship inside the wheel`  
  `there is no directory that matches the name of your project (cat_printer)`

### Why the original code fails

PR [#64](https://github.com/NaitLee/Cat-Printer/pull/64) added `pyproject.toml` for **Rye**. That file has three problems:

1. **Rye is outdated.** The author of Rye now points people to **uv**. `rye sync` is not a good default.
2. **`pyobjc` is a hard dependency.** `pyobjc` is a macOS-only bridge. On Linux, uv tries to build it from source (`pyobjc-framework-webkit` and others) and fails. The original `requirements.txt` only has `bleak`. The README already says to install `pyobjc` on macOS only.
3. **The repo is not a Python package.** Scripts live in the project root (`server.py`, `printer.py`, `printer_lib/`). There is no `cat_printer/` package. Hatchling cannot guess what to put in a wheel, so `uv sync` cannot install the project itself.

### What to do

- Use `uv`, not Rye.
- Make `pyobjc` macOS-only:

  `pyobjc~=9.1.1; sys_platform == 'darwin'`
- Tell uv this is an app, not a library:

  ```toml
  [tool.uv]
  package = false
  ```

Then `uv sync` only installs `bleak` (and Linux extras such as `dbus-fast`).

---

## 2. Scan says “No available devices found”

### What you see

```text
Cat Printer
Scanning for devices…
No available devices found
```

The printer is on. The host Bluetooth settings may even show it as connected.

### Why the original code fails

`printer.py` does **not** use the device that the desktop Bluetooth UI already holds. Every run calls `BleakScanner.discover()` and then keeps only devices whose BLE name is in a fixed list:

`GB01`, `GB02`, `GB03`, `GT01`, `MX05`, `MX06`, `MX08`, `MX09`, `MX10`, `YT01`

Two common cases fail:

1. **The printer is already connected** (phone or this PC). A BLE printer often **stops advertising**. The scan cannot see it.
2. **The BLE name is missing or unknown.** The filter drops the device. A different model name needs `-u` (“unknown device”).

The message `Scanning for devices…` is also printed when you pass a model and MAC. The original code still says “scanning” even when it tries to skip the scan.

### What to do

1. Disconnect the printer from the phone and from the system Bluetooth UI. Power the printer off and on so it advertises again.
2. Scan longer, or show all BLE devices:

   ```bash
   uv run python printer.py -s 8 -u -t 24,DejaVu-Sans-Mono -
   ```
3. Skip the name filter and pass model + MAC:

   ```bash
   uv run python printer.py -s 4,MX10,AA:BB:CC:DD:EE:FF ...
   ```

   The first number is **scan time in seconds**. It is required as the first `-s` value. If you also pass model and MAC, the original code is supposed to skip discovery. On a modern Bleak stack that path still breaks (see below).

On Linux also check:

- Bluetooth is on (`bluetoothctl show` → `Powered: yes`).
- `bluez` is installed and `bluetooth.service` is running.
- Your user is in the `bluetooth` group, then log in again.

---

## 3. Connect by MAC crashes: `BLEDevice.__init__()` missing arguments

### What you see

```text
TypeError: BLEDevice.__init__() missing 2 required positional arguments: 'details' and 'rssi'
```

This happens with:

```bash
python printer.py -s 4,MX10,80:12:15:29:B5:19 ...
```

### Why the original code fails

When `-s` includes `Model,MAC`, the original `scan()` builds a fake device:

```python
return [BLEDevice(address, name)]
```

That matches **old Bleak**. Bleak 0.20+ needs:

```python
BLEDevice(address, name, details, rssi)
```

So the “connect by MAC, do not scan” shortcut crashes before it can connect. This is why a known, already-paired printer still fails on the CLI.

### What to do

Build the object with the extra arguments, for example `BLEDevice(address, name, None, 0)`, or use a small object that only has `.name` and `.address`. Later Bleak versions may change the constructor again.

---

## 4. Connect by MAC then fails: device not found

### What you see

After the `BLEDevice` crash is fixed:

```text
Connecting
bleak.exc.BleakDeviceNotFoundError: Device with address … was not found.
```

`bluetoothctl` still shows the printer: `Paired: yes`, `Connected: yes`.

### Why the original code fails

`connect()` does:

```python
self.device = BleakClient(address)
self.device.connect(...)
```

On Linux, Bleak still **scans for an advertisement** unless you pass a `BLEDevice` that already has the BlueZ D-Bus path (`details["path"]`). An already-connected printer does not advertise, so `find_device_by_address()` times out.

BlueZ already knows the device, for example:

`/org/bluez/hci0/dev_80_12_15_29_B5_19`

The original code never looks that path up. It only waits for a new scan result.

If `connect()` fails, the original code also starts `start_notify()` in the same `loop()` call. That leftover coroutine is never awaited (`RuntimeWarning`).

### What to do

On Linux, resolve the device from the BlueZ object manager (same data Bleak already loads). Pass that `BLEDevice` (with `path` and `props`) to `BleakClient`. If BlueZ says the device is already connected, Bleak will reuse the connection and will not need a new advertisement.

Call `connect()` and `start_notify()` as two steps, not as two futures created at once.

---

## 5. Text print needs ImageMagick, and `@-` is blocked

### What you see

- `ImageMagick not found`, or
- `magick: attempt to perform an operation not allowed by the security policy '@-'`

The CLI still may print `Finished`. Nothing useful comes out of the printer.

### Why the original code fails

`-t Size[,Font]` (without `pf2`) sends text to ImageMagick and asks for a PBM image:

```text
caption:@-
```

`@-` means “read the caption from stdin”. Many Linux distros **block `@`** in ImageMagick policy (a leftover of old security bugs). The convert step fails. The printer then gets empty or invalid data.

ImageMagick is not a Python dependency. The original code only looks for `magick` or `convert` on `PATH`.

The printer still only accepts a bitmap. ImageMagick is the original way to turn TTF text (or a photo with `-c image`) into that bitmap.

### What to do

Install ImageMagick:

```bash
sudo apt install imagemagick
```

Do not use `caption:@-`. Read the text in Python and pass it as an argument:

```text
caption:W01
```

Example that prints 24 pt monospace text:

```bash
echo 'W01' | uv run python printer.py \
  -s 4,MX10,AA:BB:CC:DD:EE:FF \
  -t 24,/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf -
```

If you omit the font name (`-t 24` only), the original code may pass `None` as `-font`. Always set a font.

---

## 6. `-t …,pf2` has no font in the repo

### What you see

`PF2 font not found or broken: 'font'`

### Why the original code fails

`-t 24,font,pf2` uses a built-in PF2 raster font and does not need ImageMagick. In that mode `24` is a **scale factor**, not a TrueType point size.

`.gitignore` ignores `*.pf2`, `pf2/`, and `pf2.zip`. The public repo ships **no** `font.pf2`. So the “no ImageMagick” path does not work on a clean clone.

### What to do

Use ImageMagick and a system TTF (see above), or add a PF2 file yourself (`font.pf2` or `unifont.pf2` in the project root or in `pf2/`).

---

## Quick Linux checklist

| Check | Command / note |
| --- | --- |
| Bluetooth on | `bluetoothctl show` → Powered: yes |
| Printer known | `bluetoothctl devices` / `bluetoothctl info AA:BB:CC:DD:EE:FF` |
| Already connected? | Scan will often fail. Use model + MAC, and a BlueZ path lookup. |
| User can use BLE | add user to group `bluetooth`, then log in again |
| Python BLE lib | `uv sync` with `bleak` only on Linux |
| Text / images | install `imagemagick`; avoid `caption:@-` |
| Supported BLE names | see the model list in `printer_lib/models.py` |

---

## Working print command (after the fixes above)

```bash
echo 'W01' | uv run python printer.py \
  -s 4,MX10,80:12:15:29:B5:19 \
  -t 24,/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf -
```

Replace the MAC with your printer address. `4` is scan time (unused when model and MAC are set and the BlueZ device is already known).
