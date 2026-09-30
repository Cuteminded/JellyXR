# Contributing to Jellyframe

You can help with bug fixes, playback compatibility, VR controls, tests, and
documentation. You can also report problems you find while using the app.

Read the [README](README.md) for the project's scope and current limitations.
For setup, build commands, tests, and the code layout, see
[Build from source](DEVELOPMENT.md).

## Report a bug

Search the repository's issues before opening a new one. Include:

- The Jellyframe build or commit you used.
- Your operating system, headset, and OpenXR runtime, where applicable.
- Your Jellyfin server version.
- Steps to reproduce the problem, what you expected, and what happened.
- Relevant logs or screenshots.

For playback problems, include the container format, video and audio codecs,
resolution, and whether the video is 2D or side-by-side 3D. State whether Jellyfin
played the file directly or converted it during playback, if you know.

Remove passwords, access tokens, and private server details from logs before
posting them. A short sample you have permission to share can help reproduce
a playback problem.

## Propose a feature

Open an issue to discuss a large change before implementing it. Explain what
you want to do in the app, what gets in the way, and how the change would help.
Mention any platform or headset requirements.

Small fixes and documentation corrections can go straight into a pull request.

## Make a change

Fork the repository and create a branch for your change. Keep each pull request
focused on one problem so reviewers can understand and test it.

Follow the style of the surrounding code. Use clear names, keep functions small,
and add comments only when the code cannot explain the reason for a decision.
Write code, comments, and documentation in English.

Update the documentation when you change setup steps, controls, or app behaviour.
Keep generated builds, downloaded dependencies, credentials, and local editor
settings out of your commits.

## Test your change

Run the checks that cover the code you changed. The
[development guide](DEVELOPMENT.md) lists the core, HTTP, decoder, streaming,
and headset tests. Add a regression test when it can reproduce the bug or
check the new behaviour.

Desktop preview with `--xr-mode off` can check layout and library navigation.
It cannot verify VR comfort, tracking, controller behaviour, stereo output, or
video playback. Decoder and streaming tests check playback without a headset,
but do not verify how it looks or behaves in VR.

For headset tests, record the platform, headset, and runtime you used. If you
could not test an affected platform, say so in the pull request.

Before submitting, check for whitespace errors:

```sh
git diff --check
```

## Open a pull request

Explain the problem and what your change does. Link the related issue, if there
is one, and list the checks you ran with their results. Include screenshots for
visible UI changes and describe any testing that still needs hardware.

## Licence

Submit code contributions under the project's GPL-3.0-only licence. For new
assets or dependencies, include their licence and attribution and explain where
they came from. See [Licence and attribution](LICENSING.md) and the full
[licence text](LICENSE).

# ❤️ Thank You
Thank you so much for contributing. Your time and effort are appreciated. Let’s make Jellyframe better together!
