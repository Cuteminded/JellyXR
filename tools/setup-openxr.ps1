$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$version = '5.1.0-stable'
$expectedHash = '6A838DBDF4115549E4511EBEE0DA9A5DCC8F9F6258D4CC2F2EE57A907A3E2911'
$cache = Join-Path $projectRoot 'build/openxr'
$destination = Join-Path $projectRoot 'addons/godotopenxrvendors'
$marker = Join-Path $destination 'installed-version.txt'
if ((Test-Path $marker) -and (Get-Content $marker -Raw).Trim() -eq $version) { return }
New-Item -ItemType Directory -Force $cache | Out-Null
$archive = Join-Path $cache 'vendors.zip'
if (-not (Test-Path $archive)) {
    Invoke-WebRequest "https://github.com/GodotVR/godot_openxr_vendors/releases/download/$version/godotopenxrvendorsaddon.zip" -OutFile $archive
}
if ((Get-FileHash $archive -Algorithm SHA256).Hash -ne $expectedHash) {
    throw 'OpenXR Vendors archive checksum does not match the pinned release.'
}
Expand-Archive $archive (Join-Path $cache 'release') -Force
Copy-Item (Join-Path $cache 'release/asset/addons/godotopenxrvendors') (Join-Path $projectRoot 'addons') -Recurse -Force
$license = Join-Path $destination 'LICENSE'
Invoke-WebRequest "https://raw.githubusercontent.com/GodotVR/godot_openxr_vendors/$version/LICENSE" -OutFile $license
Set-Content $marker $version
