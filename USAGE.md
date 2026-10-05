# Using Jellyframe

## Browsing and playback

- Sign in with your Jellyfin username and password or Quick Connect.
- Browse and search your libraries, view title details, and continue watching.
- Watch 2D movies and side-by-side 3D videos.
- Watch equirectangular 360° videos in 2D, side-by-side 3D, or top-bottom 3D.
- Resize the screen and adjust its distance, height, and curvature.
- Recenter the screen in your viewing direction.
- Watch against a dark background, in a cinema, or with your room visible through passthrough.
- Use your controllers to select titles, type, pause, and skip through a video.
  Point at a player control to see its label beneath the buttons.
- Return from the player to the selected movie or series with the Library button.
  Series keep the current season open. Selecting the active title returns to playback.
- Choose an episode to watch. When it ends, a 5-second countdown appears on the
  video screen before the next available episode starts. Autoplay follows series
  order, including across seasons. Cancel the countdown to return to your library.

Jellyframe saves your screen settings and remembers your sign-in.
It supports one server and one user at a time. It does not save your password.
On PC, the sign-in token is stored in `session.cfg` in Godot's local user-data folder.

Default PC session locations:
| Platform | File |
| --- | --- |
| Windows | `%APPDATA%\Godot\app_userdata\Jellyframe\session.cfg` |
| Linux | `~/.local/share/godot/app_userdata/Jellyframe/session.cfg` |

For 3D video, Jellyframe reads the format from Jellyfin's metadata or the filename.
If a video looks wrong, you can select half or full side-by-side mode and swap
the left and right views in Settings. Top-bottom uses the upper half for the left
eye and the lower half for the right eye. These changes are not saved per title.

## 360° videos

Start a video, open Settings > Screen, and choose **360°** under Video projection.
Choose **2D**, **Half-SBS**, **Full-SBS**, or **Top-bottom** under Video format to
match the file. Look around with your headset to see the whole scene. Use your
headset's recenter command to set the forward direction. Press A or B to show
the playback controls in front of you.

Jellyframe selects 360° automatically for filenames with a separate `360`,
`360deg`, or `VR360` marker, such as `Beach.360.mp4`. It does not infer the
projection from video dimensions. Files with a separate `TB`, `OU`,
`top-bottom`, or `over-under` marker select top-bottom 3D.

360° mode supports equirectangular video only. Cubemap, fisheye, and 180° video
are not supported. During playback, the video replaces the chosen environment.
Screen size and position controls do not affect it. Select **Screen** to return
to the virtual screen. Projection overrides apply to the current playback and
are not saved per title. A new title uses automatic detection again.

## Settings and environments

Settings has separate pages for library sorting, screen controls, and environments.
Choose which field to sort your libraries by and whether to use ascending or
descending order. Home always shows the newest additions first.

Choose an environment:

- Void, the default, gives you a dark background.
- Cinema uses the detailed cinema interior.
- Theatre uses the original simple cinema.
- Passthrough shows your room around the screen. It is disabled on unsupported devices.

Cinema and Theatre have a fixed front screen. Black bars preserve the video's
proportions. In Void and Passthrough, you can adjust the screen's size, distance,
height, and curvature.

Reset to defaults restores the screen settings and keeps your chosen environment.
