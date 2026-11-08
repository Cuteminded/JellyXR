extends SceneTree

var app: Node

func _initialize() -> void:
	call_deferred("run_check")

func run_check() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	if not root.use_xr or not app.video.available():
		push_error("Start SteamVR with a connected headset and build the PC video plugin first.")
		quit(1)
		return
	print("SteamVR playback check: OpenXR initialized")
	if "--passthrough" in OS.get_cmdline_user_args() and not enable_passthrough():
		app.queue_free()
		quit(1)
		return
	app.video.ended.disconnect(app._ended)
	app.video.ended.connect(play_clip)
	app.video.failed.connect(func(message: String): push_error(message); quit(1))
	app.video.prepared.connect(func(): print("SteamVR playback check: video prepared"))
	play_clip()
	await create_timer(120).timeout
	app.video.stop()
	print("SteamVR playback check: finished")
	quit()

func enable_passthrough() -> bool:
	if not app.world.passthrough.is_supported():
		push_error("The OpenXR runtime does not report alpha-blend support. Use a SteamVR beta with passthrough support and a compatible headset and streaming connection.")
		return false
	app.settings.environment = "Passthrough"
	app.world.apply_environment()
	var xr := XRServer.find_interface("OpenXR")
	if not root.transparent_bg or xr.environment_blend_mode != XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND:
		push_error("Passthrough did not enable alpha blending and the transparent XR background.")
		return false
	print("SteamVR passthrough check: alpha blending enabled. Verify your room is visible around the video screen in the headset.")
	return true

func play_clip() -> void:
	app.session.item = {"Name": "Stereo check: LEFT in left eye, RIGHT in right eye"}
	app._play_stream(ProjectSettings.globalize_path("res://tests/fixtures/stereo_test.mp4"), {"Video3DFormat": "HalfSideBySide"}, 0)
