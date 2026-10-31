param(
    [Parameter(Mandatory)][string]$Gradle,
    [Parameter(Mandatory)][string]$AndroidSdk,
    [Parameter(Mandatory)][string]$JavaHome,
    [string]$Ffmpeg = 'ffmpeg'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$env:JAVA_HOME = $JavaHome
$env:ANDROID_HOME = $AndroidSdk
Push-Location $projectRoot
try {
    New-Item -ItemType Directory -Force build/android-test-media | Out-Null
    & $Ffmpeg -hide_banner -loglevel error -f lavfi -i 'color=c=blue:s=1920x1080:r=30' -t 12 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -g 90 -movflags +faststart -y build/android-test-media/playback.mp4
    if ($LASTEXITCODE -ne 0) { throw 'MP4 fixture generation failed.' }
    & $Ffmpeg -hide_banner -loglevel error -i build/android-test-media/playback.mp4 -c copy -hls_time 3 -hls_playlist_type vod -hls_segment_filename build/android-test-media/stream%d.ts -y build/android-test-media/stream.m3u8
    if ($LASTEXITCODE -ne 0) { throw 'HLS fixture generation failed.' }
    & $Gradle -p native :android:connectedDebugAndroidTest --console=plain
    if ($LASTEXITCODE -ne 0) { throw 'Android playback tests failed.' }
} finally {
    Pop-Location
}
