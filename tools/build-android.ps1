param(
    [Parameter(Mandatory)][string]$Godot,
    [Parameter(Mandatory)][string]$Gradle,
    [Parameter(Mandatory)][string]$AndroidSdk,
    [Parameter(Mandatory)][string]$JavaHome
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$env:JAVA_HOME = $JavaHome
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
Push-Location $projectRoot
try {
    & "$PSScriptRoot/setup-openxr.ps1"
    & $Gradle -p native :android:stagePlugin
    if ($LASTEXITCODE -ne 0) { throw 'Android video plugin compilation failed.' }
    New-Item -ItemType Directory -Force -Path dist | Out-Null
    & $Godot --headless --xr-mode off --path . --editor --import --quit
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
    & $Godot --headless --xr-mode off --path . --export-debug 'Quest 3' 'dist/jellyframe-android.apk'
    if ($LASTEXITCODE -ne 0) { throw 'Android export failed.' }
} finally {
    Pop-Location
}

