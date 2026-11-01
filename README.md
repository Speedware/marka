# Marka

Converts Chestny Znak marking codes (DataMatrix and QR) from PDF to CSV. Everything runs locally; files never leave the computer.

Only the web interface is in Russian. Every other file, name and message is in English: Cyrillic got garbled on Windows.

## Mac

Double-click `install.command`. It creates `.venv`, installs the dependencies and builds `Marka.app`.
Drag `Marka.app` into the Dock or Applications. If you move the project folder, run `install.command` again:
the app stores the path to the project.

## Windows

Same approach as [Speedware/tandem](https://github.com/Speedware/tandem): an Inno Setup installer with an embedded Python.

1. On the Mac, double-click `build-windows.command`; it makes `dist/Marka-Windows.zip`.
2. On Windows, unzip it and run `build-exe.bat`. It finds Python 3.9-3.13 (or installs 3.13 with winget),
   puts the embeddable Python and the libraries together and builds `dist\Marka-Setup.exe` with Inno Setup.
3. `Marka-Setup.exe` installs on any Windows 10/11 PC; nothing else is needed.

Rebuild after any change in `app/`. See `windows/README.txt`.

## Usage

1. Click the Marka icon; http://127.0.0.1:8765/ opens in the browser.
2. Drop one or more PDF files.
3. Pick the export format and download.

Export modes:
- **One CSV**: all codes from all PDF files.
- **CSV per PDF**: a ZIP archive with one file per PDF.
- **CSV per code**: a ZIP archive with one file per code.

Code format:
- **with GS**: the code as is, with the GS (0x1D) separator before the crypto tail;
- **without GS**: the same characters without the separator;
- **without crypto tail**: only `01` + GTIN + `21` + serial number.

By default a code containing a comma, semicolon or quote is wrapped in quotes so Excel and Numbers keep it in one cell.
The "no quotes" option gives a file byte for byte identical to the Chestny Znak export.

The server exits by itself about 6 minutes after the page is closed. Log: `marka.log`.

## Files

- `app/server.py`: code recognition and CSV export
- `app/index.html`: the page
- `marka.svg`: the icon
- `install.command`: Mac setup
- `build-windows.command`, `windows/`: Windows package
- `.venv/`, `Marka.app`, `dist/`, `marka.log`: created by the scripts and the app; do not edit
