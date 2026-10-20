param(
    [Parameter(Mandatory = $true)][string]$Python,
    [int]$Jobs = 8
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$buildRoot = Join-Path $projectRoot 'build/desktop'
$dependencyRoot = Join-Path $buildRoot 'deps'
New-Item -ItemType Directory -Force $dependencyRoot | Out-Null
New-Item -ItemType File -Force (Join-Path $projectRoot 'build/.gdignore') | Out-Null

function Get-Dependency([string]$Name, [string]$Url, [string]$Hash, [string]$Directory) {
    $archive = Join-Path $dependencyRoot $Name
    if (-not (Test-Path -LiteralPath $archive)) {
        Invoke-WebRequest -Uri $Url -OutFile $archive
    }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $Hash) {
        throw "Checksum mismatch for $Name. Remove the cached archive and retry."
    }
    $destination = Join-Path $dependencyRoot $Directory
    if (-not (Test-Path -LiteralPath $destination)) {
        if ($Directory -eq 'mpv') {
            New-Item -ItemType Directory $destination | Out-Null
            & tar -xf $archive -C $destination
        } else {
            & tar -xf $archive -C $dependencyRoot
        }
        if ($LASTEXITCODE -ne 0) { throw "Could not extract $Name." }
    }
    return $destination
}

$cmakeRoot = Get-Dependency 'cmake.zip' `
    'https://github.com/Kitware/CMake/releases/download/v3.31.6/cmake-3.31.6-windows-x86_64.zip' `
    'D163CD3AB4959B0A53FA8988F2DDBD2E6C501658201E6A154386BAD9DBE4F836' 'cmake-3.31.6-windows-x86_64'
$compilerRoot = Get-Dependency 'llvm.zip' `
    'https://github.com/mstorsjo/llvm-mingw/releases/download/20261006/llvm-mingw-20261006-ucrt-x86_64.zip' `
    '317492C456AA27EE607A5919F1D2D38DCDC1112516A24D0BF4B00D078F52D17A' 'llvm-mingw-20261006-ucrt-x86_64'
$bindingsRoot = Get-Dependency 'godot-cpp.zip' `
    'https://github.com/godotengine/godot-cpp/archive/refs/tags/godot-4.5-stable.zip' `
    '0316EA168750B5F4F1CAEA6457657A6C64241F890F78E2F042AEE4BE2B1085BF' 'godot-cpp-godot-4.5-stable'
$mpvRoot = Get-Dependency 'mpv.7z' `
    'https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20261010/mpv-dev-x86_64-20261010-git-b2c255c13e.7z' `
    '394490ED6354C2294B87C63DFA3663B23524B5551AACE9CBE35C4085682B14FA' 'mpv'
$ffmpegRoot = Get-Dependency 'ffmpeg.zip' `
    'https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-10-19-13-06/ffmpeg-n8.1.3-18-g46d899d7a0-win64-gpl-shared-8.1.zip' `
    'FA41FF09E92EE00E302B3D842716BA1B8332FC0115B3F4C3E02A2083200B20EF' 'ffmpeg-n8.1.3-18-g46d899d7a0-win64-gpl-shared-8.1'

$cmake = Join-Path $cmakeRoot 'bin/cmake.exe'
$originalPath = $env:PATH
try {
    $env:PATH = (Join-Path $compilerRoot 'bin') + ';' + $env:PATH
    & $cmake -S (Join-Path $projectRoot 'native/pc') -B (Join-Path $buildRoot 'native') `
        -G 'MinGW Makefiles' '-DCMAKE_BUILD_TYPE=Release' '-DCMAKE_CXX_COMPILER=clang++' `
        "-DGODOT_CPP_PATH=$bindingsRoot" "-DMPV_ROOT=$mpvRoot" "-DFFMPEG_ROOT=$ffmpegRoot" "-DPython3_EXECUTABLE=$Python"
    if ($LASTEXITCODE -ne 0) { throw 'PC video configuration failed.' }
    & $cmake --build (Join-Path $buildRoot 'native') --parallel $Jobs
    if ($LASTEXITCODE -ne 0) { throw 'PC video compilation failed.' }
} finally {
    $env:PATH = $originalPath
}

$pluginRoot = Join-Path $projectRoot 'addons/jellyframe_mpv'
New-Item -ItemType Directory -Force (Join-Path $pluginRoot 'bin') | Out-Null
Copy-Item (Join-Path $buildRoot 'native/jellyframe_mpv.dll') (Join-Path $pluginRoot 'bin')
Copy-Item (Join-Path $mpvRoot 'libmpv-2.dll') (Join-Path $pluginRoot 'bin')
foreach ($library in 'avcodec-62.dll', 'avformat-62.dll', 'avutil-60.dll', 'swscale-9.dll', 'swresample-6.dll') {
    Copy-Item (Join-Path $ffmpegRoot "bin/$library") (Join-Path $pluginRoot 'bin')
}
Copy-Item (Join-Path $projectRoot 'native/pc/jellyframe_mpv.gdextension') $pluginRoot
Write-Host "PC video plugin built in $pluginRoot"
