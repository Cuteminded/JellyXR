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
	app.video.ended.disconnect(app._ended)
	app.video.ended.connect(play_clip)
	app.video.failed.connect(func(message: String): push_error(message); quit(1))
	app.video.prepared.connect(func(): print("SteamVR playback check: video prepared"))
	play_clip()
	await create_timer(120).timeout
	app.video.stop()
	print("SteamVR playback check: finished")
	quit()

func play_clip() -> void:
	app.calibration = true
	app.session.item = {"Name": "Stereo check: LEFT in left eye, RIGHT in right eye"}
	app._play_stream(ProjectSettings.globalize_path("res://native/video/src/main/res/raw/stereo_test.mp4"), {"Video3DFormat": "HalfSideBySide"}, 0)
