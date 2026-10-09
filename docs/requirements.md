# Product requirements

## Target

Jellyframe is a public, MIT-licensed Jellyfin playback client by Cuteminded.
It should run directly on Steam Frame without a gaming PC. Quest 3 is the
available test headset. The initial server compatibility target is Jellyfin 10.11.6.

## Library and connection

Support one user and one server address, including remote access. Provide password
login, Quick Connect, and persistent sign-in. Show Continue Watching, recently
added movies and episodes, Movies, Shows, Favourites, Collections, and Search.
Keep watched titles visible. Large libraries need pagination and bounded image loading.

Selecting a title opens details with Play/Resume and track selection. Series need
season and episode navigation. Update playback position and watched status on the
server. Include a cancellable next-episode countdown.

## Viewing

Support ordinary 2D and stereoscopic half-SBS/full-SBS movies on a virtual screen.
Detect explicit 3D metadata and filename markers, with manual mode and eye-order
overrides. Do not persist per-movie corrections. Save global screen settings.

Allow size, height, distance, and curvature adjustments. Recenter in the current
viewing direction, including while reclining or lying down. Offer blank space,
a simple theatre, and passthrough where the headset API supports it. Passthrough
may follow the initial release. Controls should hide automatically during playback.

Prefer direct playback of compatible SDR HEVC/AAC sources, with Jellyfin transcoding
as a fallback. Support HDR sources through a verified colour-correct path. A server
without a GPU should not be assumed capable of real-time 4K transcoding.

Provide pause/play, seeking, -10/+30 seconds, volume, audio/subtitle selection,
stereo mode, and recenter. Follow the user's Jellyfin language and subtitle settings.

## Interaction and appearance

Use controller laser pointing, large hit areas, readable English text, and stable
selection feedback. The Steam Big Picture references guide the backdrop, poster
rows, and prominent selected title. Use original Jellyframe branding and server artwork.

The first usable milestone is sign-in, viewing the user's actual library, and
playing content. Shared viewing, administration, additional profiles, downloads,
and store distribution are outside the initial milestone. Keep playback and server
code separate so future features do not require rewriting the interface.

## Distribution

Start with downloadable packages and installation instructions. Prefer free and
open source dependencies. Steam Frame runtime, decoding performance, and passthrough
must be tested on Steam Frame before claiming support.
