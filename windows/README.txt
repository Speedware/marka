Marka for Windows

Build the installer (once, on any Windows 10/11 PC with internet)
1. Unzip this folder anywhere.
2. Double-click build-exe.bat.
   If Python or Inno Setup is missing, it installs them with winget.
   If Windows shows "Windows protected your PC", click "More info", then "Run anyway".
3. The result is dist\Marka-Setup.exe.

Install
Run Marka-Setup.exe on any Windows 10/11 PC. Nothing else is needed: Python is inside.
The installer adds Marka to the Start menu and, if checked, to the Desktop.

If the page does not open, the error is written to marka.log in
%LOCALAPPDATA%\Programs\Marka
