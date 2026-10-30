param(
    [Parameter(Mandatory = $true)][string]$Python,
    [int]$Jobs = 8,
    [string]$WorkRoot = '',
    [string]$OutputRoot = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $WorkRoot) { $WorkRoot = Join-Path $projectRoot 'build/desktop/godot-video' }
if (-not $OutputRoot) { $OutputRoot = Join-Path $projectRoot 'build/desktop/templates' }
$compilerRoot = Join-Path $projectRoot 'build/desktop/deps/llvm-mingw-20261006-ucrt-x86_64'
if (-not (Test-Path -LiteralPath (Join-Path $compilerRoot 'bin/clang++.exe'))) {
    throw 'Build the Windows PC video dependencies with tools/build-pc-video.ps1 first.'
}
New-Item -ItemType Directory -Force $WorkRoot, $OutputRoot | Out-Null
$archive = Join-Path $WorkRoot 'godot-4.7.2.tar.gz'
if (-not (Test-Path -LiteralPath $archive)) {
    Invoke-WebRequest 'https://codeload.github.com/godotengine/godot/tar.gz/refs/tags/4.7.2-stable' -OutFile $archive
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne 'E954996374CBD1CB5D72E0E3781CC537408E6CE73B010B12C6C2F308A820690A') {
    throw 'Godot source archive checksum mismatch.'
}
$patchFiles = @('prepare-godot-vaapi.py', 'prepare-godot-d3d11.py', 'godot-vaapi-bridge.cpp.inc', 'godot-d3d12-submit.cpp.inc')
$patchHash = ($patchFiles | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $_)).Hash }) -join ''
$source = Join-Path $WorkRoot 'godot'
$stamp = Join-Path $source '.jellyxr-windows-video'
if (-not (Test-Path -LiteralPath $stamp) -or (Get-Content -LiteralPath $stamp -Raw).Trim() -ne $patchHash) {
    New-Item -ItemType Directory -Force $source | Out-Null
    & tar -xf $archive -C $source --strip-components=1
    if ($LASTEXITCODE -ne 0) { throw 'Godot source extraction failed.' }
    & $Python (Join-Path $PSScriptRoot 'prepare-godot-d3d11.py') $source
    if ($LASTEXITCODE -ne 0) { throw 'Godot Windows video adapter patch failed.' }
    Set-Content -LiteralPath $stamp -Value $patchHash -NoNewline
}
$packages = Join-Path $WorkRoot 'python-packages'
if (-not (Test-Path -LiteralPath (Join-Path $packages 'SCons/__init__.py'))) {
    & $Python -m pip install --no-user --target $packages 'scons==4.10.0'
    if ($LASTEXITCODE -ne 0) { throw 'SCons installation failed.' }
}
$previousPath = $env:PATH
$previousPythonPath = $env:PYTHONPATH
try {
    $env:PATH = "$compilerRoot/bin;$previousPath"
    $env:PYTHONPATH = $packages
    & $Python -m SCons -C $source platform=windows target=template_release arch=x86_64 `
        use_mingw=yes use_llvm=yes d3d12=no disable_path_overrides=no debug_symbols=no lto=none "-j$Jobs"
    if ($LASTEXITCODE -ne 0) { throw 'Godot Windows video template compilation failed.' }
} finally {
    $env:PATH = $previousPath
    $env:PYTHONPATH = $previousPythonPath
}
Copy-Item -LiteralPath (Join-Path $source 'bin/godot.windows.template_release.x86_64.llvm.exe') `
    -Destination (Join-Path $OutputRoot 'godot-video.windows.x86_64.exe') -Force
Copy-Item -LiteralPath (Join-Path $source 'LICENSE.txt') -Destination (Join-Path $OutputRoot 'godot-license.txt') -Force
Copy-Item -LiteralPath (Join-Path $source 'COPYRIGHT.txt') -Destination (Join-Path $OutputRoot 'godot-copyright.txt') -Force
