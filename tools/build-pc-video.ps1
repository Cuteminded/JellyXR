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
        if ($Directory -eq 'mpv-lgpl') {
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
$vulkanRoot = Get-Dependency 'vulkan-headers-1.4.321.zip' `
    'https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/v1.4.321.zip' `
    'CACE1D5832FC00287C9B10B27577C41033B2C86434E884EEF5C8DCEA098D5118' 'vulkan-headers-1.4.321'
$mpvRoot = Get-Dependency 'mpv-lgpl.zip' `
    'https://nightly.link/mpv-player/mpv/actions/runs/40835379230/libmpv-v0.41.0-dev-gcf764c61d-40835379230-x86_64-w64-mingw32-lgpl.zip' `
    '4AB059D0C6CE2FCCC239F14F54087F9411C60B680D40B7DCCA8CDA44EA6E8366' 'mpv-lgpl'
$ffmpegRoot = Get-Dependency 'ffmpeg-lgpl.zip' `
    'https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-10-19-13-06/ffmpeg-n8.1.3-18-g46d899d7a0-win64-lgpl-shared-8.1.zip' `
    '638DD2A073CC1838CB668E736A822A1A58A3CA5405A109B0ECA41C5EE03EC9A1' 'ffmpeg-n8.1.3-18-g46d899d7a0-win64-lgpl-shared-8.1'

$cmake = Join-Path $cmakeRoot 'bin/cmake.exe'
$originalPath = $env:PATH
try {
    $env:PATH = (Join-Path $compilerRoot 'bin') + ';' + $env:PATH
    & $cmake --fresh -S (Join-Path $projectRoot 'native/pc') -B (Join-Path $buildRoot 'native') `
        -G 'MinGW Makefiles' '-DCMAKE_BUILD_TYPE=Release' '-DCMAKE_CXX_COMPILER=clang++' `
        "-DGODOT_CPP_PATH=$bindingsRoot" "-DMPV_ROOT=$mpvRoot" "-DFFMPEG_ROOT=$ffmpegRoot" "-DVULKAN_HEADERS_ROOT=$vulkanRoot" "-DPython3_EXECUTABLE=$Python"
    if ($LASTEXITCODE -ne 0) { throw 'PC video configuration failed.' }
    & $cmake --build (Join-Path $buildRoot 'native') --parallel $Jobs
    if ($LASTEXITCODE -ne 0) { throw 'PC video compilation failed.' }
} finally {
    $env:PATH = $originalPath
}

$pluginRoot = Join-Path $projectRoot 'addons/jellyxr_mpv'
New-Item -ItemType Directory -Force (Join-Path $pluginRoot 'bin') | Out-Null
Copy-Item (Join-Path $buildRoot 'native/jellyxr_mpv.dll') (Join-Path $pluginRoot 'bin')
Copy-Item (Join-Path $mpvRoot 'libmpv-2.dll') (Join-Path $pluginRoot 'bin')
foreach ($library in 'avcodec-62.dll', 'avformat-62.dll', 'avutil-60.dll', 'swscale-9.dll', 'swresample-6.dll') {
    Copy-Item (Join-Path $ffmpegRoot "bin/$library") (Join-Path $pluginRoot 'bin')
}
Copy-Item (Join-Path $projectRoot 'native/pc/jellyxr_mpv.gdextension') $pluginRoot
$licenses = Join-Path $buildRoot 'licenses'
New-Item -ItemType Directory -Force $licenses | Out-Null
Copy-Item (Join-Path $mpvRoot 'LICENSE.LGPL') (Join-Path $licenses 'mpv-lgpl.txt')
Copy-Item (Join-Path $ffmpegRoot 'LICENSE.txt') (Join-Path $licenses 'ffmpeg-lgpl.txt')
Copy-Item (Join-Path $projectRoot 'third_party/licenses/GPL-3.0.txt') $licenses
Copy-Item (Join-Path $bindingsRoot 'LICENSE.md') (Join-Path $licenses 'godot-cpp.txt')
Copy-Item (Join-Path $projectRoot 'LICENSE') (Join-Path $licenses 'jellyxr.txt')
Copy-Item (Join-Path $projectRoot 'LICENSING.md') $licenses
& $Python (Join-Path $PSScriptRoot 'inspect-playback-libraries.py') --bin-directory (Join-Path $pluginRoot 'bin') --output (Join-Path $buildRoot 'library-report.json')
if ($LASTEXITCODE -ne 0) { throw 'LGPL library verification failed.' }
Write-Host "PC video plugin built in $pluginRoot"
