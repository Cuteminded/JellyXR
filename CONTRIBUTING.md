# Contributing to jellyXR

Contributions can include bug fixes, playback improvements, VR controls, tests, and documentation. Reports of problems you find while using jellyXR are also welcome.

Read the [README](README.md) for the project's scope and current limitations, and [Build from source](DEVELOPMENT.md) for setup, build commands, tests, and the code layout.

## Report a bug

Search the repository's issues before opening a new one. Include:

- The jellyXR build or commit you used.
- Your operating system, headset, and OpenXR runtime, where applicable.
- Your GPU and the OpenGL or Vulkan renderer used for PC playback.
- Your Jellyfin server version.
- Steps to reproduce the problem, what you expected, and what happened.
- Relevant logs or screenshots.

For playback problems, include the container format, video and audio codecs, resolution, frame rate, HDR format, and stereo or panoramic layout. If you know whether Jellyfin played the file directly or converted it, include that too.

Remove passwords, access tokens, and private server details from logs before posting them. A short sample you have permission to share can help reproduce a playback problem.

## Propose a feature

Before implementing a large change, open an issue. Explain what you want to do in the app, what gets in the way, and how the change would help. Include any platform or headset requirements.

Small fixes and documentation corrections can go straight into a pull request.

## Make a change

Fork the repository and create a branch for your change. Keep each pull request focused on one problem so reviewers can understand and test it.

Follow the style of the surrounding code. Use clear names and keep functions small. Add comments when the code cannot explain the reason for a decision. Write code, comments, and documentation in English.

Update the documentation when you change setup steps, controls, or app behaviour. Keep generated builds, downloaded dependencies, credentials, and local editor settings out of your commits.

## Test your change

Run the checks that cover the code you changed. The [development guide](DEVELOPMENT.md) lists the core, HTTP, decoder, streaming, and headset tests. Add a regression test when it can reproduce the bug or check the new behaviour.

Desktop preview with `--xr-mode off` can check layout and library navigation, but cannot verify VR comfort, tracking, controller behaviour, stereo output, or video playback. Decoder and streaming tests check playback without a headset and cannot verify how it looks or behaves in VR.

For headset tests, record the platform, headset, and runtime you used, and state in the pull request if you could not test an affected platform.

Before submitting, check for whitespace errors:

```sh
git diff --check
```

## Open a pull request

Explain the problem and what your change does, link any related issue, and list the checks you ran with their results. Include screenshots for visible UI changes and describe any testing that still needs hardware.

## Licence

Submit code contributions under the project's GPL-3.0-only licence. Include the licence, attribution, and source of any new assets or dependencies. See [Licence and attribution](LICENSING.md) and the full [licence text](LICENSE).
