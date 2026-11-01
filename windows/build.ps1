# Builds dist\Marka-Setup.exe: an installer with an embedded Python, so target PCs need nothing preinstalled.
# Same approach as Speedware/tandem: find or install Python, take the embeddable Python of the same version,
# put the libraries into it and pack everything with Inno Setup.
$AppVersion = '1.0.0'
$ErrorActionPreference = 'Stop'

$Root     = $PSScriptRoot
$BuildDir = Join-Path $Root 'build'
$DistDir  = Join-Path $Root 'dist'
Set-Location $Root
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

function Step($text) { Write-Host "`n=== $text" -ForegroundColor Cyan }

function Update-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Install-WithWinget([string]$Id, [string]$Name, [string]$Override = '') {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "$Name was not found and winget is not available. Install 'App Installer' from the Microsoft Store or install $Name manually."
    }
    Write-Host "$Name was not found, installing it with winget ($Id)..." -ForegroundColor Yellow
    $wingetArgs = @('install', '--id', $Id, '--exact', '--silent',
                    '--accept-package-agreements', '--accept-source-agreements')
    if ($Override) { $wingetArgs += @('--override', $Override) }
    & winget @wingetArgs
    Update-Path
}

# Runs a Python candidate with a timeout: the Microsoft Store stub python.exe can hang when started from a script.
function Test-Python([string]$Exe, [string]$Prefix = '') {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = "$Prefix -c ""import sys, platform; print(sys.executable); print(platform.python_version()); print(platform.architecture()[0]); print('%d%d' % sys.version_info[:2])"""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    try { $p = [System.Diagnostics.Process]::Start($psi) } catch { return $null }
    if (-not $p.WaitForExit(15000)) {
        try { $p.Kill() } catch {}
        Write-Host "  $Exe did not answer in 15 s, skipped"
        return $null
    }
    if ($p.ExitCode -ne 0) { return $null }
    $out = @($p.StandardOutput.ReadToEnd().Trim() -split "`r?`n")
    if ($out.Count -lt 4) { return $null }
    $v = [version]$out[1]
    if ($out[2] -ne '64bit') { Write-Host "  32-bit Python, skipped"; return $null }
    # zxing-cpp 2.x, which the app is tested with, has wheels for Python 3.9-3.13 only
    if ($v -lt [version]'3.9' -or $v -ge [version]'3.14') { Write-Host "  Python $v is not supported (need 3.9-3.13), skipped"; return $null }
    return [pscustomobject]@{ Exe = $out[0].Trim(); Version = $out[1].Trim(); Short = $out[3].Trim() }
}

function Find-Python {
    $candidates = New-Object System.Collections.ArrayList
    foreach ($pattern in @((Join-Path $env:LOCALAPPDATA 'Programs\Python\Python3*\python.exe'),
                           (Join-Path $env:ProgramFiles 'Python3*\python.exe'))) {
        foreach ($f in @(Get-ChildItem $pattern -ErrorAction SilentlyContinue | Sort-Object FullName -Descending)) {
            [void]$candidates.Add(@($f.FullName, ''))
        }
    }
    $py = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($py) { [void]$candidates.Add(@($py.Source, '-3')) }
    # the WindowsApps python.exe is usually the Microsoft Store stub, so it goes last
    $onPath = @(Get-Command python.exe -All -ErrorAction SilentlyContinue | ForEach-Object { $_.Source })
    foreach ($p in $onPath) { if ($p -notmatch '\\WindowsApps\\') { [void]$candidates.Add(@($p, '')) } }
    foreach ($p in $onPath) { if ($p -match '\\WindowsApps\\') { [void]$candidates.Add(@($p, '')) } }
    foreach ($c in $candidates) {
        Write-Host "  trying $($c[0]) $($c[1])"
        $found = Test-Python $c[0] $c[1]
        if ($found) { return $found }
    }
    return $null
}

function Find-Iscc {
    return @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}

try {
    Step 'Python'
    $py = Find-Python
    if (-not $py) {
        Install-WithWinget 'Python.Python.3.13' 'Python' '/quiet InstallAllUsers=0 PrependPath=1 Include_test=0'
        $py = Find-Python
        if (-not $py) { throw 'Could not install Python automatically. Install Python 3.13 (64-bit) from python.org and run the build again.' }
    }
    $version, $short = $py.Version, $py.Short
    Write-Host "Python $version ($($py.Exe))"

    $cache = Join-Path $BuildDir 'cache'
    $stage = Join-Path $BuildDir 'stage'
    $pyDir = Join-Path $stage 'python'
    $appDir = Join-Path $stage 'app'
    $siteDir = Join-Path $pyDir 'Lib\site-packages'
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Force $cache, $pyDir, $appDir, $siteDir | Out-Null

    Step "Embeddable Python $version"
    $zip = Join-Path $cache "python-$version-embed-amd64.zip"
    if (-not (Test-Path $zip)) {
        $url = "https://www.python.org/ftp/python/$version/python-$version-embed-amd64.zip"
        Write-Host "Downloading $url"
        Invoke-WebRequest -Uri $url -OutFile "$zip.part" -UseBasicParsing
        Move-Item "$zip.part" $zip -Force
    }
    Expand-Archive -Path $zip -DestinationPath $pyDir -Force

    # the embeddable Python only searches the paths listed in its ._pth file
    $pth = Get-ChildItem $pyDir -Filter 'python*._pth' | Select-Object -First 1
    @("python$short.zip", '.', 'Lib', 'Lib\site-packages', '..\app') | Set-Content -Path $pth.FullName -Encoding Ascii

    Step 'Libraries (PyMuPDF, zxing-cpp, numpy)'
    # the build Python has the same version and bitness as the embedded one, so pip picks matching wheels
    $ErrorActionPreference = 'Continue'
    & $py.Exe -m pip install --disable-pip-version-check --no-warn-script-location --only-binary=:all: `
        --target $siteDir -r (Join-Path $Root 'requirements.txt')
    $pipExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($pipExit -ne 0) { throw 'pip could not install the libraries (see above). Check the internet connection.' }
    $bin = Join-Path $siteDir 'bin'
    if (Test-Path $bin) { Remove-Item $bin -Recurse -Force }

    Step 'App files'
    Copy-Item (Join-Path $Root 'app\server.py'), (Join-Path $Root 'app\index.html') -Destination $appDir
    Copy-Item (Join-Path $Root 'marka.svg'), (Join-Path $Root 'marka.ico') -Destination $stage

    Step 'Check: the embedded Python loads the app and the libraries'
    $ErrorActionPreference = 'Continue'
    & (Join-Path $pyDir 'python.exe') -c "import fitz, zxingcpp, numpy, server; print('PyMuPDF', fitz.VersionBind, '/ zxing-cpp', zxingcpp.__version__ if hasattr(zxingcpp, '__version__') else 'ok')"
    $checkExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($checkExit -ne 0) { throw 'The embedded Python could not load the app (see the error above).' }
    Get-ChildItem $stage -Recurse -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force

    Step 'Inno Setup'
    $iscc = Find-Iscc
    if (-not $iscc) {
        Install-WithWinget 'JRSoftware.InnoSetup' 'Inno Setup 6'
        $iscc = Find-Iscc
        if (-not $iscc) { throw 'Could not install Inno Setup automatically. Install it from https://jrsoftware.org/isdl.php and run the build again.' }
    }
    Write-Host "Inno Setup: $iscc"

    Step 'Installer'
    & $iscc /Q "/DAppVersion=$AppVersion" "/DStageDir=$stage" "/DIconFile=$(Join-Path $Root 'marka.ico')" "/DOutDir=$DistDir" `
        (Join-Path $Root 'installer.iss')
    if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed (see above).' }
    Write-Host "`nDone: dist\Marka-Setup.exe. This file can be copied to any Windows PC and installed." -ForegroundColor Green
    exit 0
} catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
