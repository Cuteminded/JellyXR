# Using Jellyframe

1. Enter the address you normally use to open Jellyfin, such as `https://jellyfin.example.com`. If someone else runs the server, ask them for the address.
2. Enter your Jellyfin username and password.
3. Select **Sign in**.

To use **Quick Connect**, select it and note the code Jellyframe displays. Open Jellyfin on your phone or computer, sign in, and approve that code using Quick Connect.

Jellyframe remembers your sign-in without saving your password. Select **Sign out** before switching accounts or servers. You can use one server and account at a time.

## Reset your saved sign-in on PC

If you cannot sign out through the app, remove the saved sign-in file:

1. Close Jellyframe completely.
2. Find the file for your computer in the table below.
3. Delete `session.cfg`.
4. Open Jellyframe again and sign in.

| Computer | Saved sign-in file |
| --- | --- |
| Windows | `%APPDATA%\Jellyframe\session.cfg` |
| Linux | `~/.local/share/Jellyframe/session.cfg` |

To reset the saved app settings as well, delete `settings.cfg` from the same folder while Jellyframe is closed. You will need to enter your server address and choose your settings again. This does not delete movies, shows, or your Jellyfin account.

## Choose something to watch

1. Select **Home** to see recently added movies and shows, or choose one of your libraries from the menu.
2. Browse the titles, or enter a name in the search box and select **Search**.
3. Select a movie to open its details, then choose **Play movie**. For a series, choose a season and select **Play episode** beside the episode you want.
4. If you have watched part of a title before, choose **Resume** or **Resume episode** to continue from where you left off.

On a title's details page, **Play from start** appears beside **Resume** when saved progress is available. It starts the video at the beginning, even if that title is already playing.

In VR, point your controller at a button and squeeze the trigger to select it. Point at a text box to open the keyboard. Use the thumbstick to scroll through a list.

## Control playback

Press **A** to show the playback controls. Press **B** to open or close the main menu, including while a video is playing. Reopening the menu preserves the current library, title details, or settings page. Playback continues while you browse. Point at a button to see its name beneath the controls.

| Control | What it does |
| --- | --- |
| Play / Pause | Pause the video or continue watching. |
| Stop | Stop the video and return to your library. |
| Back 10 seconds | Go back a little to watch something again. |
| Forward 30 seconds | Skip ahead. |
| Time bar | Choose a different point in the video. |
| Settings | Change the screen, background, or playback quality. |
| Audio and subtitles | Placeholder for future audio-track and subtitle selection. This button is currently disabled. |
| Hide controls | Remove the controls from your view. Press A to show them again. |

Press **B** to browse your library while playback continues. Select the title that is already playing to return to the video.

When an episode finishes, a five-second countdown appears before the next available episode starts. Choose **Cancel** during the countdown to return to your library.

### Skip intros and credits

With [Intro Skipper](https://github.com/intro-skipper/intro-skipper) installed on Jellyfin 10.10 or newer, a **Skip intro** or **Skip credits** popup appears at the bottom-right of the video during a detected segment. Point at it and press the trigger to skip, even with the playback controls hidden. When the controls are open, the popup sits just above them. Recap and preview segments also have skip buttons when the server supplies them. Skipping is manual.

The server must finish analyzing the title before timestamps are available. Jellyframe reads Jellyfin's media segments, so other providers using the same API also work. If there are no timestamps or the request fails, playback continues without a skip button. Older plugin-specific APIs are not supported.

## Make the screen comfortable

Open **Settings**, then choose **Screen**. If your chosen background allows screen adjustments, you can change:

- **Width** to make the screen larger or smaller.
- **Distance** to move it closer or farther away.
- **Height** to move it up or down.
- **Curvature** to make it flat or curved around you.

If the screen is facing the wrong way, look in the direction you want to watch and use your headset's recenter command.

**Cinema** and **Theatre** have fixed screens. To move or resize the screen yourself, choose **Void** or **Passthrough** under **Settings > Environment**.

Select **Reset to defaults** on the Screen page to restore the usual screen size and position. This keeps your chosen background and video format. Settings are saved as you change them.

## Choose your surroundings

Open **Settings > Environment** and choose:

| Background | What you see |
| --- | --- |
| Void | A dark background with an adjustable screen. This is the default. |
| Cinema | A detailed cinema with a fixed screen at the front. |
| Theatre | A simpler cinema with a fixed screen. |
| Passthrough | Your real room around the video screen, if your headset supports it. |

If your device does not support Passthrough, you cannot select it. In Cinema and Theatre, black bars keep the picture from looking stretched.

## Watch a 3D video

Jellyframe usually chooses the right picture layout automatically. If you see two pictures side by side or one above the other, open **Settings > Screen** and look for **Video format**.

| Option | When to use it |
| --- | --- |
| 2D | Ordinary movies and shows without 3D. |
| Half-SBS | A 3D video that stores the left-eye and right-eye pictures side by side. |
| Full-SBS | Another side-by-side 3D format, with a wider picture for each eye. |
| Top-bottom | A 3D video that stores one eye's picture above the other. |

SBS means "side by side". If you do not know which version your video uses, try Half-SBS first. If the picture looks too wide or too narrow, try Full-SBS.

If the depth looks wrong, try **Swap left and right eyes**. These choices are not remembered separately for each title, so another video may need a different setting.

## Watch a 180° or 360° video

These videos let you look around inside the scene instead of watching a normal screen.

1. Start the video.
2. Open **Settings > Screen**.
3. Under **Video projection**, choose **180°** for a scene in front of you, or **360°** for a scene that surrounds you.
4. If the video is also in 3D, choose the matching **Video format** as described above. Otherwise, leave it on **2D**.

Move your head to look around. For a 180° video, the space behind you stays dark. Use your headset's recenter command if the scene faces the wrong direction. Press A to bring up the controls.

The video replaces your chosen background while you watch. Screen width, distance, height, and curvature do not affect these videos. Select **Screen** under Video projection to return to a normal video screen.

Jellyframe can recognize some 180° and 360° videos automatically, but you can change the setting if it chooses incorrectly. A new title uses automatic detection again. Some panoramic video formats are not supported, so changing this setting cannot fix every distorted video.

## Change playback quality

Open **Settings > Playback**. The choice applies to the next video you start.

- **Automatic** plays the original video when possible and asks Jellyfin to convert it when needed. Start with this option if you are unsure.
- **Original full resolution** keeps the original video quality. Your headset or PC must be able to play the file.
- **Transcoded** asks your Jellyfin server to convert the video. Choose **720p**, **1080p**, or **4K** under **Transcoded resolution**. This can help with files that will not play smoothly at their original quality.

1080p is the default for converted videos. Choose 720p to use less data, or 4K for more detail when the source video supports it. These are maximum sizes; smaller videos are not enlarged. Higher resolutions need a faster connection and more processing power from your Jellyfin server. Your choice is saved and applies to the next video you start.

Picture quality depends on the video, your device, your connection, and what your Jellyfin server can handle. To use the Windows setup tested with HDR, 4K, and 8K videos, follow the [Windows launch instructions](INSTALLATION.md#try-it-on-windows-with-steamvr).

## Change the order of your library

Open **Settings > Library sorting** and choose how you want titles arranged. **Ascending** means A to Z, lowest to highest, or oldest first. **Descending** reverses that order.

Home always shows the newest additions first. The sort order does not affect Random.

## If something does not look right

- If the controls disappear, press A to show them again.
- If you cannot resize the screen, choose Void or Passthrough under Settings > Environment, and select Screen under Video projection.
- If you see two copies of the picture, check Video format under Settings > Screen.
- If the scene surrounds you when you wanted a normal screen, select Screen under Video projection.
- If the video pauses with a loading message, it is waiting for more video data. Give it a moment. If this keeps happening, try Automatic or Transcoded under Settings > Playback, then start the video again.
- Audio-language and subtitle selection are not available yet.

For setup problems, see [Install and start Jellyframe](INSTALLATION.md). The [README](README.md#current-limitations) lists the remaining limitations.
