param(
    [Parameter(Mandatory)][string]$Godot,
    [Parameter(Mandatory)][string]$Gradle,
    [Parameter(Mandatory)][string]$AndroidSdk,
    [Parameter(Mandatory)][string]$JavaHome,
    [string]$SigningKeystore = "$PSScriptRoot/../.signing/jellyxr-release.keystore",
    [string]$SigningPasswordFile = "$PSScriptRoot/../.signing/release-password.txt"
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$env:JAVA_HOME = $JavaHome
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
if (-not (Test-Path -LiteralPath $SigningKeystore -PathType Leaf)) {
    throw 'Specify an existing signing key with -SigningKeystore.'
}
if (-not (Test-Path -LiteralPath $SigningPasswordFile -PathType Leaf)) {
    throw 'Specify an existing signing password file with -SigningPasswordFile.'
}
$signingPassword = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $SigningPasswordFile).Path).TrimEnd("`r", "`n")
if ([string]::IsNullOrWhiteSpace($signingPassword)) {
    throw 'The signing password file is empty.'
}
$previousSigningPassword = $env:GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD
$env:GODOT_ANDROID_KEYSTORE_DEBUG_PATH = (Resolve-Path -LiteralPath $SigningKeystore).Path
$env:GODOT_ANDROID_KEYSTORE_DEBUG_USER = 'Cuteminded'
Push-Location $projectRoot
try {
    $env:GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD = $signingPassword
    & "$PSScriptRoot/setup-openxr.ps1"
    & $Gradle -p native :android:stagePlugin
    if ($LASTEXITCODE -ne 0) { throw 'Android video plugin compilation failed.' }
    New-Item -ItemType Directory -Force -Path dist | Out-Null
    & $Godot --headless --xr-mode off --path . --editor --import --quit | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
    & $Godot --headless --xr-mode off --path . --export-debug 'Android' 'dist/jellyxr-android.apk' | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Android export failed.' }
    & $Godot --headless --xr-mode off --path . --export-debug 'Quest 1' 'dist/jellyXR-quest1.apk' | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Quest 1 export failed.' }
} finally {
    $env:GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD = $previousSigningPassword
    $signingPassword = $null
    Pop-Location
}

