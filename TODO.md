# Jellyfin feature checklist

This checklist compares Jellyframe with Jellyfin's user-facing features.
Implementation does not mean a feature has been tested on every headset.

- Checked items are implemented in the current source. 
- Unchecked items are missing or incomplete.
- Hardware validation is tracked separately below. 

## Sign-in and accounts

- [x] Connect to a custom Jellyfin server address.
- [x] Sign in with a username and password.
- [x] Sign in with Quick Connect after approval on another device.
- [x] Restore a saved session without storing the password.
- [x] Sign out and clear the saved session.
- [ ] Save multiple servers and switch between them.
- [ ] Switch between saved user accounts without signing out.
- [ ] Discover Jellyfin servers on the local network.
- [ ] Manage account settings and audio/subtitle language preferences.

## Libraries and discovery

- [x] Browse movies, series, and video items with posters and backdrops.
- [x] Select individual server libraries from the sidebar.
- [x] Show recently added titles on Home.
- [x] Show a Continue watching row on Home.
- [x] Search titles globally or within the selected library.
- [x] Load more titles while scrolling.
- [x] Sort libraries by name, rating, date, play count, or runtime, with ascending and descending order.
- [x] Browse titles in random order.
- [x] Browse series by season and episode.
- [x] Display watched indicators and saved playback progress supplied by Jellyfin.
- [ ] Show a Next up row for series. Automatic playback of the next episode already exists.
- [ ] Filter by watched status, genre, year, or other metadata.
- [ ] Add, remove, and browse favourites.
- [ ] Browse collections.
- [ ] Browse, create, and play playlists or a user-managed playback queue.
- [ ] Show recommendations and similar titles.
- [ ] Open actor or crew pages and browse their other titles.

## Title details and watch history

- [x] Show descriptions, release years, runtimes, ratings, and genres.
- [x] Show cast and crew portraits, names, and roles.
- [x] Show studio and video/audio stream information when available.
- [x] Resume a movie or episode from its saved position.
- [x] Start a partially watched title from the beginning.
- [x] Report playback start, progress, pause state, and stop events to Jellyfin.
- [ ] Manually mark a movie, episode, season, or series as watched or unwatched.
- [ ] Select between multiple media versions. Playback currently uses the first returned media source.
- [ ] Browse and play trailers and extras.

## Video playback

- [x] Play supported original video streams through Direct Play.
- [x] Request server transcoding and play HLS streams.
- [x] Retry with transcoding after a playback failure in Automatic mode.
- [x] Choose Automatic, Original full resolution, or Transcoded playback.
- [x] Choose 720p, 1080p, or 4K transcoding limits before starting playback.
- [x] Pause, resume, stop, seek on the timeline, and skip backward or forward.
- [x] Show loading and buffering feedback.
- [x] Browse the library while the current video continues playing.
- [x] Play the next available episode automatically after a cancellable countdown.
- [x] Manually skip intros, credits, recaps, and previews when the server supplies media segments. Requires the Jellyfin 10.10+ API and a segment provider such as Intro Skipper.
- [ ] Enable Direct Stream/remuxing. Playback requests currently set `EnableDirectStream` to `false`.
- [ ] Select audio tracks and languages. The audio/subtitle control is disabled.
- [ ] Display and select embedded or external subtitles. The playback profile currently advertises no subtitle support.
- [ ] Adjust subtitle appearance and timing.
- [ ] Browse chapters and jump to a selected chapter.
- [ ] Change playback speed.
- [ ] Change playback quality during an active session.
- [ ] Automatically hide playback controls after inactivity.
- [ ] Download media for offline playback.

## Other Jellyfin features

These extend beyond Jellyframe's current movie and series focus.

- [x] View photos.
- [x] Show loading feedback when opening photos from the library and switching photos.
- [ ] View slideshows.
- [ ] Read books and comics.
- [ ] Watch live TV and browse the programme guide.
- [ ] Join or host SyncPlay sessions.
- [ ] Receive remote playback commands from other Jellyfin clients.

## Jellyframe VR features

These are Jellyframe features rather than Jellyfin feature gaps.

- [x] Browse and control playback with VR controllers and an on-screen keyboard.
- [x] Adjust screen width, distance, height, and curvature in supported environments.
- [x] Choose Void, Cinema, Theatre, or supported-device Passthrough environments.
- [x] Select 2D, half-SBS, full-SBS, and top-bottom layouts, with an eye-swap option.
- [x] Select flat-screen, 180-degree, or 360-degree projection, with automatic detection for supported metadata and filenames.
- [x] Save screen, environment, library sorting, and playback quality settings.
- [ ] Implement native HDR output and display calibration.

## Hardware validation

- [ ] Verify installation and playback on Steam Frame.
- [ ] Verify installation and playback on Android XR.
- [x] Confirm Quest 3 HLS seeking and resume after the timeline fix.
- [x] Verify top-bottom stereo and eye swapping on Quest 3.
- [x] Verify stereoscopic 180-degree projection and recentering on Quest 3.
- [x] Verify Quest 3 HDR content playback.
- [x] Verify PC OpenGL HDR playback in a headset.
- [x] Verify photo loading feedback on Quest 3, both from the library and between photos.
- [ ] Verify ARM64 and other Linux configurations on headsets.
- [ ] Verify the new native Vulkan decoder, HDR conversion, and 4K/8K playback on Linux with a headset.
