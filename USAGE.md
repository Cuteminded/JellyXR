# Using Jellyframe

## Browsing and playback

- Sign in with your Jellyfin username and password or Quick Connect.
- Browse and search your libraries, view title details, and continue watching.
- Watch 2D movies and side-by-side 3D videos.
- Watch equirectangular 180° and 360° videos in 2D, side-by-side 3D, or top-bottom 3D.
- Resize the screen and adjust its distance, height, and curvature.
- Recenter the screen in your viewing direction.
- Watch against a dark background, in a cinema, or with your room visible through passthrough.
- Use your controllers to select titles, type, pause, and skip through a video, or point at a player control to see its label beneath the buttons.
- Use the Library button to return to the selected movie or series, keeping the current season open for a series. Selecting the active title returns to playback.
- When an episode ends, a 5-second countdown appears before the next available episode starts in series order, including across seasons. Cancel the countdown to return to your library.

Jellyframe supports one server and one user at a time, saves your screen settings, and remembers your sign-in without storing your password. On PC, it stores the sign-in token in `session.cfg` in Godot's local user-data folder.

Default PC session locations:

| Platform | File |
| --- | --- |
| Windows | `%APPDATA%\Godot\app_userdata\Jellyframe\session.cfg` |
| Linux | `~/.local/share/godot/app_userdata/Jellyframe/session.cfg` |

Jellyframe reads the 3D format from Jellyfin's metadata or the filename, but you can select half or full side-by-side mode and swap the left and right views in Settings if the picture looks wrong. Top-bottom uses the upper half for the left eye and the lower half for the right eye; format and eye-swap changes are not saved per title.

## 180° and 360° videos

Start a video, open Settings > Screen, and choose **180°** or **360°** under Video projection, then select **2D**, **Half-SBS**, **Full-SBS**, or **Top-bottom** under Video format to match the file. 180° fills the view in front of you and leaves the view behind you dark, while 360° surrounds you.

Look around with your headset to see the scene, use the headset's recenter command to set the forward direction, and press A or B to show the playback controls in front of you.

Jellyframe selects 360° automatically for filenames with a separate `360`, `360deg`, or `VR360` marker, such as `Beach.360.mp4`, and selects 180° for a separate `180`, `180deg`, or `VR180` marker. It does not infer the projection from video dimensions; files with a separate `TB`, `OU`, `top-bottom`, or `over-under` marker select top-bottom 3D.

180° and 360° modes support equirectangular video, but not cubemap or fisheye layouts. The video replaces the chosen environment during playback, and screen size and position controls do not affect it. Select **Screen** to return to the virtual screen; projection overrides apply to the current playback and are not saved per title, so a new title uses automatic detection again.

## Settings and environments

Use the separate settings pages to change library sorting, screen controls, and environments. For library sorting, choose a field and ascending or descending order; Home always shows the newest additions first.

Choose an environment:

- Void, the default, gives you a dark background.
- Cinema uses the detailed cinema interior.
- Theatre uses the original simple cinema.
- Passthrough shows your room around the screen and is disabled on unsupported devices.

Cinema and Theatre have a fixed front screen with black bars to preserve the video's proportions, while Void and Passthrough let you adjust the screen's size, distance, height, and curvature.

Reset to defaults restores the screen settings and keeps your chosen environment.
