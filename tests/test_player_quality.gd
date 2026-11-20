extends SceneTree

const Fixtures = preload("res://tests/test_tracks.gd")

class FixtureSettings extends JellyXRSettings:
	func save(_path: String = PATH) -> Error: return OK

var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error(message)

func run_checks() -> void:
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.video.queue_free()
	app.api.queue_free()
	var video := Fixtures.FixtureVideo.new()
	var api := Fixtures.FixtureApi.new()
	app.add_child(video)
	app.add_child(api)
	api.server = "https://fixture.invalid"
	api.stream_path = "/video/master.m3u8"
	app.video = video
	app.api = api
	app.session.api = api
	app.session.video_backend = null
	app.settings = FixtureSettings.new()
	app.session.settings = app.settings
	app.api.token = "fixture"
	app.shell.signed_in = true
	video.prepared.connect(app._video_prepared)
	app.playing = true
	app.decoder_ready = true
	app.session.item = {"Id": "item"}
	app.session.source = {"Id": "source"}
	app.session.media_source_id = "source"
	app.session.audio_index = 2
	app.session.subtitle_index = 5
	app.session.active_playback_mode = "auto"
	app.session.active_transcode_resolution = 1080
	app.session.active_transcode_max_fps = 30
	video.paused = true
	app._show_playback()
	app._screen_settings()
	var view: SettingsView = app.page.get_child(0)
	view._show_section(3)
	var transcoded: CheckBox = view.playback_choices.get_child(2).get_child(0)
	transcoded.pressed.emit()
	check(app.session.method == "Transcode" and video.position == 42000 and video.paused, "Selecting Transcoded preserves playback position and pause state")
	view.transcode_choices.get_child(2).pressed.emit()
	view.transcode_fps_choices.get_child(0).pressed.emit()
	var request := playback_request(api)
	check(request.StartTimeTicks == 420000000 and not request.AllowVideoStreamCopy, "The replacement request transcodes at the current position")
	var limits: Array = request.DeviceProfile.TranscodingProfiles[0].Conditions
	check(limits[1].Value == "1440" and limits[2].Value == "24", "Resolution and frame rate selections reach Jellyfin")
	check(request.MediaSourceId == "source" and request.AudioStreamIndex == 2 and app.session.subtitle_index == 5, "Changing quality preserves the media version and track selections")
	check(app.settings.playback_mode == "transcoded" and app.settings.transcode_resolution == 1440 and app.settings.transcode_max_fps == 24, "Settings selections apply to the active session and future videos")
	check(app.panel.visible and view.is_visible_in_tree(), "Changing quality keeps Settings open")
	check(not app.player_overlay.submenu_buttons.has("quality"), "The playbar has no separate Quality button")
	var count := api.bodies.size()
	await app._select_quality("transcoded", 1440, 24)
	check(api.bodies.size() == count, "Selecting the current quality does not reload playback")
	view._select_playback_mode("original")
	check(app.session.active_playback_mode == "original" and playback_request(api).StartTimeTicks == 420000000, "Original mode can be selected during playback")
	view._select_playback_mode("auto")
	check(app.session.active_playback_mode == "auto" and app.session.method != "Transcode", "Automatic renegotiates original playback after leaving Transcoded")
	app.session.method = "Transcode"
	view.transcode_choices.get_child(0).pressed.emit()
	check(app.session.method == "Transcode" and not playback_request(api).AllowVideoStreamCopy, "Adjusting Automatic fallback limits keeps the stream transcoded")
	app.session.burn_subtitles = true
	app._screen_settings()
	view = app.page.get_child(0)
	check(view.playback_choices.get_child(1).get_child(0).disabled, "Settings disables Original while picture subtitles require conversion")
	count = api.bodies.size()
	await app._select_quality("original", 720, 24)
	check(api.bodies.size() == count, "Picture subtitles cannot bypass the Original mode restriction")
	app.session.burn_subtitles = false
	app.transcode_offset = 100000000
	video.position = 32000
	api.wait_for_frame = true
	app._select_quality("transcoded", 1080, 30)
	check(app.seeking, "Changing quality loads a replacement stream")
	app.settings.transcode_resolution = 1440
	app._playback_settings_changed()
	app.player_overlay.close_menu()
	for frame in range(16): await process_frame
	check(video.position == 42000 and video.paused, "Restarting an offset stream preserves the absolute playback position")
	check(app.session.active_transcode_resolution == 1440 and not app.seeking, "Settings changed during a reload apply once playback is ready")
	check(not app.player_overlay.quick_access.visible, "Finishing a quality change keeps a dismissed menu closed")
	video.paused = false
	await app._select_quality("transcoded", 2160, 60)
	check(not video.paused and video.position == 42000, "Changing quality while playing resumes without pausing")
	app._select_quality("auto", 720, 30)
	await app._stop(false)
	for frame in range(8): await process_frame
	check(not app.playing and not app.seeking, "Stopping during a quality change cancels the replacement stream")
	app.playing = false
	app.queue_free()
	await process_frame
	print("Player quality checks: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(1 if failures else 0)

func playback_request(api: JellyfinClient) -> Dictionary:
	for index in range(api.paths.size() - 1, -1, -1):
		if api.paths[index].ends_with("/PlaybackInfo"): return api.bodies[index]
	return {}
