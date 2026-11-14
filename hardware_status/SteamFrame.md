# Steam Frame video decoding

| Format | Status | Support on Steam Frame |
| --- | --- | --- |
| H.264, 8-bit | Hardware decoding | GPU copy works. |
| HEVC Main, 8-bit 4:2:0 | Hardware decoding | GPU copy works, including at 4K60. Some 8K streams may fall back to software decoding because Iris can reject a stream even when its resolution is within the advertised range. |
| HEVC Main 10 | Software only | The reported SteamOS driver lacks usable linear 10-bit output for JellyXR's V4L2 path. [SteamOS issue #2946](https://github.com/ValveSoftware/SteamOS/issues/2946) |
| HEVC 4:2:2 | Software only | JellyXR's V4L2 HEVC path supports 8-bit Main with 4:2:0 chroma. |
| AV1 | Software only | The reported SteamOS driver does not expose AV1 decoding through V4L2. [SteamOS issue #2954](https://github.com/ValveSoftware/SteamOS/issues/2954) |

If a video stutters in Direct Play, use **Transcoded** playback in JellyXR so Jellyfin can send H.264 instead.
