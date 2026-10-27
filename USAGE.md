# Using jellyXR

1. Enter the address you normally use to open Jellyfin, such as `https://jellyfin.example.com`. If someone else runs the server, ask them for the address.
2. Enter your Jellyfin username and password.
3. Select **Sign in**.

To use **Quick Connect**, select it and note the code jellyXR displays. Open Jellyfin on your phone or computer, sign in, and approve that code using Quick Connect.

jellyXR remembers your sign-in without saving your password. Select **Sign out** before switching accounts or servers. You can use one server and account at a time.

## Reset your saved sign-in on PC

If you cannot sign out through the app, remove the saved sign-in file:

1. Close jellyXR completely.
2. Open the folder listed below. On Windows, paste `%APPDATA%\jellyXR` into the address bar in File Explorer and press Enter.
3. Delete `session.cfg`.
4. Open jellyXR again and sign in.

| Computer | Folder |
| --- | --- |
| Windows | `%APPDATA%\jellyXR` |
| Linux | `~/.local/share/jellyXR` |

To reset the saved app settings as well, delete `settings.cfg` from the same folder while jellyXR is closed. You will need to enter your server address and choose your settings again. This does not delete movies, shows, or your Jellyfin account.

## Choose something to watch

1. Select **Home** to see recently added movies and shows, or choose one of your libraries from the menu.
2. Browse the titles, or enter a name in the search box and select **Search**.
3. Select a movie to open its details, then choose **Play movie**. For a series, choose a season and select **Play episode** beside the episode you want.
4. If you have watched part of a title before, choose **Resume** or **Resume episode** to continue from where you left off.

On a title's details page, **Play from start** appears beside **Resume** when saved progress is available. It starts the video at the beginning, even if that title is already playing.

Play and Resume use the first available version. If a movie or episode has several versions, select **Choose version** to pick the one you want to watch.

In VR, point your controller at a button and squeeze the trigger to select it. Point at a text box to open the keyboard. Use the thumbstick to scroll through a list.

## View photos

Select a photo in your library to open it. A "Loading photo..." indicator appears while the image loads. Use the previous and next controls to browse photos; the same indicator appears while another photo is loading. If loading fails, the app returns to the library with an error message so you can try again.

## Control playback

Press **A** to show the playback controls.
Press **B** to open or close the library during playback.
Press **Y** on the left controller to open or close settings.

| Control | What it does |
| --- | --- |
| Play / Pause | Pause the video or continue watching. |
| Stop | Stop the video and return to your library. |
| Back 10 seconds | Go back a little to watch something again. |
| Forward 30 seconds | Skip ahead. |
| Time bar | Choose a different point in the video. |
| Settings | Change the screen, background, or playback quality. |
| Audio and subtitles | Choose a language, turn subtitles on or off, and adjust how they look. |
| Hide controls | Remove the controls from your view. Press A to show them again. |
| Statistics for nerds | Use the chart button at the far right to inspect playback details and live statistics. Select it again to dismiss the panel. |

Press **B** to browse your library while playback continues. Select the title that is already playing to return to the video.

When an episode finishes, a five-second countdown appears before the next available episode starts. Choose **Cancel** during the countdown to return to your library.

### Skip intros and credits

If Jellyfin knows where an intro or the credits begin, a **Skip intro** or **Skip credits** button appears near the bottom-right of the video. Point at it and press the trigger to skip. You can use it without opening the playback controls. Some videos also have buttons to skip a recap or preview.

This needs setup in Jellyfin, for example with [Intro Skipper](https://github.com/intro-skipper/intro-skipper). If someone else manages your Jellyfin server, ask them to enable it. Skip buttons appear only after Jellyfin has checked the video and found the parts it can skip.

## Audio and subtitles

Press **A** to open the playback controls, then select **Audio and subtitles**.

### Choose a language

Under **Audio**, select the language or version you want to hear. The choices depend on the video. Some videos also include commentary.

The video briefly reloads when you change the audio, then continues from the same point. If you paused it first, it stays paused.

If the choices are unavailable, select **Use Automatic for this video**. This lets Jellyfin prepare the video for your chosen audio or subtitles. It does not change your saved playback preference.

Select **Back to video** to continue watching, or press **B** to open your library.

### Turn subtitles on or off

Under **Subtitles**, choose one of the available options. Choose **Off** to hide them.

Subtitles may take a little while to load. If loading fails, select the same option again to retry.

### Make subtitles easier to read

Under **Text subtitle appearance**, you can:

- Change **Text size** to make the letters larger or smaller.
- Change **Vertical position** to move the subtitles up or down.
- Choose white, yellow, or green text.
- Change **Delay** if the words appear at the wrong time.

If the words appear too early, increase Delay with **+**. If they appear too late, decrease it with **-**. Select **Reset timing** to undo your timing changes.

The app remembers your size, position, and color choices. Timing changes apply only to the current video. Subtitles move above the playback controls while those controls are visible, then return to your chosen position when you hide them.

Some subtitles are saved as pictures. Choosing these briefly reloads the video, and you cannot change their size, color, position, or timing. The app tells you when those adjustments do not apply. Other subtitles may look simpler than they do in another player, without their original fonts or placement.

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

jellyXR usually chooses the right picture layout automatically. If you see two pictures side by side or one above the other, open **Settings > Screen** and look for **Video format**.

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

jellyXR can recognize some 180° and 360° videos automatically, but you can change the setting if it chooses incorrectly. A new title uses automatic detection again. Some videos use a picture layout the app cannot show correctly. Changing this setting will not fix those videos.

## Change playback quality

Open **Settings > Playback**. The choice applies to the next video you start.

- **Automatic** lets Jellyfin choose how to play the video on your device. Start with this option if you are unsure.
- **Original full resolution** keeps the original video quality. Your headset or PC must be able to play the file.
- **Transcoded** asks Jellyfin to prepare a version that is easier for your device to play. Choose **720p**, **1080p**, or **4K** under **Transcoded resolution**. This can help with files that will not play smoothly at their original quality.

Start with **1080p**. Try **720p** if playback keeps stopping to load, or **4K** for a sharper picture if the video was recorded at that quality. Choosing 4K cannot add detail to a lower-quality video. Higher quality needs a faster connection and a computer running Jellyfin that can keep up. The app remembers your choice for the next video you start.

Picture quality also depends on the video itself and your headset. For help getting started on a PC, see the [Windows launch instructions](INSTALLATION.md#try-it-on-windows-with-steamvr).

## Change the order of your library

Open **Settings > Library sorting** and choose how you want titles arranged. **Ascending** means A to Z, lowest to highest, or oldest first. **Descending** reverses that order.

Home always shows the newest additions first. The sort order does not affect Random.

## If something does not look right

- If the controls disappear, press A to show them again.
- If you cannot resize the screen, choose Void or Passthrough under Settings > Environment, and select Screen under Video projection.
- If you see two copies of the picture, check Video format under Settings > Screen.
- If the scene surrounds you when you wanted a normal screen, select Screen under Video projection.
- If the video pauses with a loading message, it is waiting for more video data. Give it a moment. If this keeps happening, try Automatic or Transcoded under Settings > Playback, then start the video again.
- If subtitles appear too early or too late, adjust Delay under Audio and subtitles.
- If audio or subtitle choices are unavailable, select Use Automatic for this video on that page.

For setup problems, see [Install and start jellyXR](INSTALLATION.md). The [README](README.md#current-limitations) lists the remaining limitations.
