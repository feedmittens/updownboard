#Requires -Version 5.1
# UpDownBoard installer — Windows
# https://github.com/feedmittens/updownboard
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$REPO      = 'https://github.com/feedmittens/updownboard'
$REPO_ZIP  = 'https://github.com/feedmittens/updownboard/archive/refs/heads/main.zip'
$InstallDir = "$env:ProgramFiles\UpDownBoard"
$ConfigDir  = "$env:ProgramData\UpDownBoard"
$ConfigFile = "$ConfigDir\config.yaml"
$LogDir     = "$env:ProgramData\UpDownBoard\logs"
$ServiceName = 'UpDownBoard'
$Port        = 8080

# ── Formatting ──────────────────────────────────────────────────────────────────
function Write-Header {
    Write-Host ""
    Write-Host "  +----------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  |      UpDownBoard -- Windows installer        |" -ForegroundColor Cyan
    Write-Host "  |      github.com/feedmittens/updownboard      |" -ForegroundColor Cyan
    Write-Host "  +----------------------------------------------+" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Info   { param($msg) Write-Host "  -> $msg" -ForegroundColor Blue }
function Write-Ok     { param($msg) Write-Host "  OK $msg" -ForegroundColor Green }
function Write-Warn   { param($msg) Write-Host "  !! $msg" -ForegroundColor Yellow }
function Write-Fail   { param($msg) Write-Host "  XX $msg" -ForegroundColor Red; exit 1 }
function Write-Section { param($msg) Write-Host ""; Write-Host $msg -ForegroundColor White }

# ── Admin check ──────────────────────────────────────────────────────────────────
function Require-Admin {
    $current = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Fail "Run this script as Administrator (right-click PowerShell -> Run as administrator)"
    }
}

# ── Mode picker ──────────────────────────────────────────────────────────────────
function Pick-Mode {
    Write-Section "Deployment mode"
    Write-Host "  How do you want to run UpDownBoard?"
    Write-Host ""
    Write-Host "  1) Docker        -- easiest; container managed as a Windows service"
    Write-Host "  2) Standalone    -- native Python, Windows Service via NSSM (no Docker)"
    Write-Host "  3) Behind IIS    -- standalone + IIS reverse proxy (ARR)"
    Write-Host ""
    do {
        $choice = Read-Host "  Choice [1/2/3]"
    } while ($choice -notmatch '^[123]$')
    return @('docker','standalone','iis')[[int]$choice - 1]
}

# ── Dependency checks ────────────────────────────────────────────────────────────
function Check-Python {
    Write-Section "Checking Python"
    try {
        $pyver = & python --version 2>&1
        if ($pyver -match '(\d+)\.(\d+)') {
            $maj = [int]$Matches[1]; $min = [int]$Matches[2]
            if ($maj -lt 3 -or ($maj -eq 3 -and $min -lt 11)) {
                Write-Fail "Python 3.11+ required (found $pyver). Download from https://www.python.org/"
            }
            Write-Ok "Python $maj.$min"
        } else { Write-Fail "Could not parse Python version." }
    } catch {
        Write-Fail "Python not found. Download from https://www.python.org/ (check 'Add to PATH' during install)"
    }
}

function Check-Docker {
    Write-Section "Checking Docker"
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Fail "Docker not found. Install Docker Desktop: https://docs.docker.com/desktop/install/windows-install/"
    }
    try { docker info 2>&1 | Out-Null } catch {
        Write-Fail "Docker daemon not running. Start Docker Desktop and try again."
    }
    $ver = docker --version | Select-String -Pattern '[\d.]+' | ForEach-Object { $_.Matches[0].Value }
    Write-Ok "Docker $ver"
}

function Check-NSSM {
    Write-Section "Checking NSSM"
    if (-not (Get-Command nssm -ErrorAction SilentlyContinue)) {
        Write-Warn "NSSM not found — downloading to $InstallDir\nssm.exe"
        $nssmZip = "$env:TEMP\nssm.zip"
        Invoke-WebRequest 'https://nssm.cc/release/nssm-2.24.zip' -OutFile $nssmZip
        Expand-Archive $nssmZip "$env:TEMP\nssm_extract" -Force
        $nssmExe = Get-ChildItem "$env:TEMP\nssm_extract" -Recurse -Filter 'nssm.exe' |
                   Where-Object { $_.Directory.Name -eq 'win64' } | Select-Object -First 1
        if (-not $nssmExe) {
            $nssmExe = Get-ChildItem "$env:TEMP\nssm_extract" -Recurse -Filter 'nssm.exe' | Select-Object -First 1
        }
        Copy-Item $nssmExe.FullName "$InstallDir\nssm.exe"
        Write-Ok "NSSM downloaded"
        $script:NssmPath = "$InstallDir\nssm.exe"
    } else {
        $script:NssmPath = (Get-Command nssm).Source
        Write-Ok "NSSM found at $($script:NssmPath)"
    }
}

function Check-IIS {
    Write-Section "Checking IIS"
    $iis = Get-WindowsFeature -Name 'Web-Server' -ErrorAction SilentlyContinue
    if (-not $iis -or -not $iis.Installed) {
        Write-Fail "IIS not installed. Enable it: Install-WindowsFeature -Name Web-Server -IncludeManagementTools"
    }
    # Check ARR
    $arr = Get-WindowsFeature -Name 'Web-Http-Redirect' -ErrorAction SilentlyContinue
    if (-not (Test-Path 'HKLM:\SOFTWARE\Microsoft\IIS Extensions\Application Request Routing')) {
        Write-Warn "IIS Application Request Routing (ARR) may not be installed."
        Write-Warn "Download from: https://www.iis.net/downloads/microsoft/application-request-routing"
    }
    Write-Ok "IIS found"
}

# ── Download source ──────────────────────────────────────────────────────────────
function Download-Source {
    Write-Section "Downloading UpDownBoard"
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    $zipPath = "$env:TEMP\updownboard.zip"
    Write-Info "Fetching $REPO_ZIP"
    Invoke-WebRequest $REPO_ZIP -OutFile $zipPath
    $extractPath = "$env:TEMP\updownboard_extract"
    Expand-Archive $zipPath $extractPath -Force
    $srcDir = Get-ChildItem $extractPath | Select-Object -First 1
    Get-ChildItem $srcDir.FullName | Copy-Item -Destination $InstallDir -Recurse -Force
    Remove-Item $zipPath, $extractPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok "Installed to $InstallDir"
}

# ── Config setup ─────────────────────────────────────────────────────────────────
function Setup-Config {
    Write-Section "Configuration"
    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
    New-Item -ItemType Directory -Force -Path $LogDir   | Out-Null
    if (-not (Test-Path $ConfigFile)) {
        Copy-Item "$InstallDir\config.example.yaml" $ConfigFile
        Write-Info "Created $ConfigFile from example"
        Write-Warn "Edit $ConfigFile to add your systems before starting."
    } else {
        Write-Ok "Config already exists at $ConfigFile -- leaving it alone"
    }
    # Symlink into install dir (junction for directories, hardlink for files)
    if (-not (Test-Path "$InstallDir\config.yaml")) {
        New-Item -ItemType HardLink -Path "$InstallDir\config.yaml" -Target $ConfigFile | Out-Null
    }
}

# ── Docker deployment ─────────────────────────────────────────────────────────────
function Install-Docker {
    Write-Section "Docker deployment"
    Check-Docker

    $compose = @"
services:
  updownboard:
    build: .
    ports:
      - "${Port}:8080"
    volumes:
      - ${ConfigFile}:/app/config.yaml:ro
    cap_add:
      - NET_RAW
    restart: unless-stopped
"@
    $compose | Set-Content "$InstallDir\docker-compose.yml"
    Write-Ok "docker-compose.yml written"

    Write-Section "Building container"
    Push-Location $InstallDir
    docker compose build
    Pop-Location
    Write-Ok "Image built"

    # Register docker compose as a Windows service via NSSM
    Check-NSSM
    $dockerPath = (Get-Command docker).Source
    & $script:NssmPath install $ServiceName $dockerPath 'compose up' 2>&1 | Out-Null
    & $script:NssmPath set $ServiceName AppDirectory $InstallDir 2>&1 | Out-Null
    & $script:NssmPath set $ServiceName AppStdout "$LogDir\updownboard.log" 2>&1 | Out-Null
    & $script:NssmPath set $ServiceName AppStderr "$LogDir\updownboard.log" 2>&1 | Out-Null
    & $script:NssmPath set $ServiceName Start SERVICE_AUTO_START 2>&1 | Out-Null
    Start-Service $ServiceName
    Write-Ok "Windows service installed and started"
    Write-Ok "Running at http://localhost:$Port"
}

# ── Standalone deployment ─────────────────────────────────────────────────────────
function Install-Standalone {
    Write-Section "Standalone deployment"
    Check-Python
    Download-Source
    Setup-Config
    Check-NSSM

    Write-Section "Python virtualenv"
    & python -m venv "$InstallDir\venv"
    & "$InstallDir\venv\Scripts\pip" install --quiet --upgrade pip
    & "$InstallDir\venv\Scripts\pip" install --quiet -r "$InstallDir\requirements.txt"
    Write-Ok "Dependencies installed"

    Write-Section "Windows Service (NSSM)"
    $uvicorn = "$InstallDir\venv\Scripts\uvicorn.exe"
    & $script:NssmPath install $ServiceName $uvicorn "app.main:app --host 0.0.0.0 --port $Port" 2>&1 | Out-Null
    & $script:NssmPath set $ServiceName AppDirectory $InstallDir 2>&1 | Out-Null
    & $script:NssmPath set $ServiceName AppStdout "$LogDir\updownboard.log" 2>&1 | Out-Null
    & $script:NssmPath set $ServiceName AppStderr "$LogDir\updownboard.log" 2>&1 | Out-Null
    & $script:NssmPath set $ServiceName Start SERVICE_AUTO_START 2>&1 | Out-Null
    Start-Service $ServiceName
    Write-Ok "Service installed and started at http://localhost:$Port"
}

# ── IIS deployment ────────────────────────────────────────────────────────────────
function Install-IIS {
    Write-Section "IIS reverse proxy deployment"
    Check-IIS
    Install-Standalone

    Write-Section "IIS site configuration"
    Import-Module WebAdministration -ErrorAction Stop

    # Create an IIS site that ARR reverse-proxies to uvicorn
    $siteName = 'UpDownBoard'
    $sitePath = "$env:SystemDrive\inetpub\updownboard"
    New-Item -ItemType Directory -Force -Path $sitePath | Out-Null

    # web.config with ARR rewrite rule
    $webConfig = @'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <rewrite>
      <rules>
        <rule name="UpDownBoard Proxy" stopProcessing="true">
          <match url="(.*)" />
          <action type="Rewrite" url="http://localhost:PORT/{R:1}" />
        </rule>
      </rules>
    </rewrite>
  </system.webServer>
</configuration>
'@
    $webConfig -replace 'PORT', $Port | Set-Content "$sitePath\web.config"

    if (Get-Website -Name $siteName -ErrorAction SilentlyContinue) {
        Remove-Website -Name $siteName
    }
    New-Website -Name $siteName -Port 80 -PhysicalPath $sitePath -Force | Out-Null
    Write-Ok "IIS site '$siteName' created on port 80"
    Write-Warn "ARR must be installed for the reverse proxy to work."
    Write-Warn "Download: https://www.iis.net/downloads/microsoft/application-request-routing"
    Write-Info "To add TLS: bind a certificate in IIS Manager and add a *:443 binding"
}

# ── Main ──────────────────────────────────────────────────────────────────────────
Write-Header
Require-Admin
$mode = Pick-Mode

switch ($mode) {
    'docker'     { Download-Source; Setup-Config; Install-Docker }
    'standalone' { Install-Standalone }
    'iis'        { Install-IIS }
}

Write-Host ""
Write-Host "  Done." -ForegroundColor Green
Write-Host ""
Write-Host "  Dashboard:  http://localhost:$Port" -ForegroundColor Cyan
Write-Host "  Status:     http://localhost:$Port/status" -ForegroundColor Cyan
Write-Host "  Config:     $ConfigFile" -ForegroundColor Cyan
Write-Host "  Logs:       $LogDir\updownboard.log" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Edit config.yaml, then: Restart-Service $ServiceName"
Write-Host "  Repo: $REPO" -ForegroundColor DarkGray
Write-Host ""
