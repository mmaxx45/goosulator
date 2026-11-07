# Baut rechner.exe und stellt sie auf das Windows-Subsystem um, damit beim
# Start kein Konsolenfenster aufgeht.
#
#   .\build.ps1                          goose aus dem PATH
#   .\build.ps1 -Goose C:\pfad\goose.exe
param([string]$Goose = "goose")

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

& $Goose build rechner.goose
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# editbin gehört zu den MSVC-Build-Tools, mit denen goose ohnehin baut.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products * -property installationPath
$editbin = Get-ChildItem "$vs\VC\Tools\MSVC\*\bin\Hostx64\x64\editbin.exe" |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $editbin) { throw "editbin.exe nicht gefunden (MSVC Build Tools installiert?)" }

& $editbin.FullName /nologo /SUBSYSTEM:WINDOWS rechner.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "rechner.exe gebaut (ohne Konsolenfenster)"
