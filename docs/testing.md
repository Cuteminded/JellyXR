# Device testing

## Before playing

Use a test account or your own account on a reachable Jellyfin server. Do not
paste access tokens or passwords into issue reports. Keep server URLs with
credentials out of screenshots and logs.

## Quest checks

The debug build includes a generated 12-second half-SBS calibration clip. Select
**Test 3D playback** on the login screen. Close one eye at a time: LEFT should
appear only in the left eye and RIGHT only in the right eye. Both should be upright.
This test uses a bundled H.264 file, so it does not verify network streaming or HEVC.

1. Start Jellyframe while seated facing away from the previous launch direction.
   Confirm the menu appears in front of you once headset tracking is active.
   Launch with the headset removed, then put it on and repeat the check.
2. Point with either controller. Check hover, trigger press, trigger release,
   scrolling, keyboard typing, and controller menu toggling.
   Confirm a button activates once when the trigger is pressed and plays a soft
   click. Move the pointer while releasing, switch hands, and hold the trigger
   while aiming off the panel. Check the pointer dot marks the target.
   Hide the menu, turn your head, and show it again. Its world position and the
   movie position should stay unchanged until you explicitly select Recenter.
3. Sign in with a password, sign out, then test Quick Connect.
4. Restart the app and verify that the saved session is restored.
5. Select each server library in the left menu. Confirm search and Load more
   stay inside that library. Use Home to browse across libraries. Browse a
   library larger than 24 titles and check poster selection after scrolling.
6. Play a short SDR H.264/AAC file, then HEVC/AAC at the intended resolution.
7. Play known half-SBS and full-SBS calibration files. Verify each eye sees only
   its own view, proportions are correct, orientation is upright, and swap works.
8. Pause, seek, stop, resume, and inspect Continue Watching in another client.
9. Try an incompatible source and verify one transcoding fallback, followed by
   a useful error if the server cannot transcode.
10. Test an HDR source with server tone mapping. Compare colours with an SDR reference.
11. Recenter while seated and reclined. Check curvature and screen height.
12. Remove the headset during playback. Confirm audio pauses and resumes intentionally.
13. Let an episode finish. Confirm the next-episode countdown and cancellation.

## Performance

Watch a representative high-bitrate movie for at least 20 minutes. Check audio
synchronisation, dropped frames, heat, battery consumption, and Wi-Fi recovery.
Record codec, resolution, bitrate, direct/transcoded mode, headset software version,
and Jellyfin version with results. Passing on Quest does not validate Steam Frame.

## Automated coverage

The core script checks SBS detection, aspect correction, screen geometry,
server-address validation, and query encoding. It cannot verify eye separation,
hardware decoding, HDR tone mapping, or physical comfort.

## Initial verification, 2026-10-09

- Godot 4.7.2 project import and desktop startup passed.
- Core checks passed, including Jellyfin's HalfSideBySide and FullSideBySide enum values.
- Local HTTP integration checks passed for login encoding, authentication headers,
  pagination, empty responses, and invalid responses. These use a local fixture server.
- Android video plugin compiled successfully with JDK 17.
- Quest debug APK exported and installed successfully.
- The user confirmed the VR login panel appears and controller pointing/clicking works on Quest 3.
- Desktop visual inspection found and corrected a clipped VR keyboard.
- The first device calibration exposed a multiview shader type error. The eye index
  now uses an explicit integer conversion. The Android decoder opened the 1920x1080 clip.
- The user confirmed separate-eye output after that fix, but reported upside-down
  labels. The video shader now converts the screen's vertical UV coordinates before
  applying Android's texture transform.
- The user confirmed the corrected half-SBS calibration displays upright LEFT and
  RIGHT labels in the correct eyes on Quest 3.
- Keyboard focus transfer, character entry, and backspace passed the desktop smoke check.
- Poster input regression checks cover stationary clicks and 4/20-pixel pointer movement.
- Playback now recenters the movie and hides the menu when the decoder is ready;
  it no longer opens the screen-settings page over the movie automatically.
- The user confirmed real video playback works, including 3D. Specific HEVC and
  HDR cases remain unverified.
- The redesigned library passed desktop visual inspection and poster click tests.
- HTTP fixture checks cover user-library discovery and scoped search/pagination.
- Startup recenter tests cover missing tracking, interrupted tracking, and a
  single recenter after tracking settles. Physical placement needs a headset check.
- Menu toggle tests preserve both window and movie transforms after head movement.
- Pointer tests cover trigger hysteresis, off-panel entry, cancelled presses,
  controller handoff, and one sound per accepted button activation.
