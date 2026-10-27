extends SceneTree

class FixtureApi extends JellyfinClient:
	var bodies: Array[Dictionary] = []
	var paths: Array[String] = []
	var wait_for_frame := false
	func request(path: String, _method: HTTPClient.Method = HTTPClient.METHOD_GET, body: Dictionary = {}) -> Dictionary:
		bodies.append(body)
		paths.append(path)
		if wait_for_frame: await get_tree().process_frame
		return {"ok": true, "data": {"PlaySessionId": "test-session", "MediaSources": [{"Id": "source", "SupportsDirectPlay": true, "TranscodingSubProtocol": "hls", "TranscodingUrl": "/video/master.m3u8?VideoCodec=copy", "MediaStreams": [{"Type": "Audio", "Index": 2}, {"Type": "Subtitle", "Index": 5, "Codec": "pgssub"}]}]}}

class FixtureVideo extends VideoBackend:
	var position := 42000
	func position_ms() -> int: return position
	func stop() -> void: paused = false
	func toggle_pause() -> void: paused = not paused
	func open(_url: String, _authorization: String, start_ms: int) -> void:
		position = start_ms
		prepared.emit()

var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run_checks() -> void:
	var track := SubtitleTrack.new()
	root.add_child(track)
	track.cues = SubtitleTrack.parse("WEBVTT\n\nfirst\n00:01.000 --> 00:04.000 align:start\n<i>Hello</i> &amp; welcome\n\n00:02.000 --> 00:03.000\nSecond\n\nNOTE ignored\n00:00.000 --> 00:10.000\nHidden\n\n00:bad --> 00:07.000\nInvalid\n\n00:05.000 --> 00:06.000\nLast")
	check(track.cues.size() == 3, "The parser accepts cue IDs and settings but skips notes and malformed cues")
	check(track.text_at(999) == "" and track.text_at(1000) == "Hello & welcome", "Cue start boundaries and markup are handled")
	check(track.text_at(2500) == "Hello & welcome\nSecond", "Overlapping cues remain visible together")
	check(track.text_at(3000) == "Hello & welcome" and track.text_at(4000) == "", "Cue end boundaries are exclusive")
	check(track.text_at(5500) == "Last" and track.text_at(1500) == "Hello & welcome", "Forward and backward seeking finds the right cues")
	track.delay_ms = 500
	check(track.text_at(1000) == "" and track.text_at(1500) == "Hello & welcome", "Positive delay moves subtitles later")
	track.delay_ms = -500
	check(track.text_at(500) == "Hello & welcome", "Negative delay moves subtitles earlier")
	check(SubtitleTrack.supported({"Codec": "ass"}) and not SubtitleTrack.supported({"Codec": "pgssub"}), "Text conversion and picture burn-in use separate paths")
	track.clear()
	check(track.text_at(1500).is_empty() and track.index == -1, "Disabling subtitles clears the displayed cues")
	var api := FixtureApi.new()
	api.server = "https://fixture.invalid"
	root.add_child(api)
	var session := PlaybackSession.new()
	session.api = api
	session.settings = JellyXRSettings.new()
	root.add_child(session)
	var streams: Array = []
	session.stream_ready.connect(func(url: String, _source: Dictionary, start: int): streams.append([url, start]))
	await session.open({"Id": "item"})
	check(api.bodies.back().EnableDirectStream, "Automatic playback enables remuxing")
	session.position_ticks = 420000000
	session.audio_index = 2
	await session.open(session.item, false, true)
	check(api.bodies.back().AudioStreamIndex == 2 and not api.bodies.back().EnableDirectPlay, "Audio selection requests a server stream with the chosen index")
	check(session.method == "DirectStream" and session.is_hls() and streams.back()[1] == 42000, "Remuxed HLS retains the absolute resume position")
	await session.report("Playing")
	await session.report("Stopped")
	check(api.paths.back().begins_with("/Videos/ActiveEncodings"), "Stopping a remux closes its server encoding session")
	session.subtitle_index = 5
	session.burn_subtitles = true
	await session.open(session.item, false, true)
	var body: Dictionary = api.bodies.back()
	check(body.SubtitleStreamIndex == 5 and body.AlwaysBurnInSubtitleWhenTranscoding and not body.AllowVideoStreamCopy, "Picture subtitles request burn-in with video conversion")
	check(session.method == "Transcode" and body.AudioStreamIndex == 2, "Burn-in keeps the selected audio")
	await session.open({"Id": "next"})
	check(session.audio_index == -1 and session.subtitle_index == -1 and not session.burn_subtitles, "New titles reset per-item stream indices")
	api.wait_for_frame = true
	var count := streams.size()
	session.open({"Id": "cancelled"})
	session.cancel_pending()
	await process_frame
	await process_frame
	check(streams.size() == count, "A cancelled request cannot restart playback")
	var view := TracksView.new()
	view.session = session
	view.subtitles = track
	view.settings = session.settings
	root.add_child(view)
	await process_frame
	view._refresh()
	check(track.changed.get_connections().size() == 1, "Refreshing track choices does not duplicate subtitle notifications")
	view.queue_free()
	session.queue_free()
	api.queue_free()
	track.queue_free()
	await process_frame
	await check_app_switching()
	print("Track checks: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(1 if failures else 0)

func check_app_switching() -> void:
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.video.queue_free()
	var video := FixtureVideo.new()
	app.add_child(video)
	app.video = video
	video.prepared.connect(app._video_prepared)
	app.api.queue_free()
	var api := FixtureApi.new()
	api.server = "https://fixture.invalid"
	app.add_child(api)
	app.api = api
	app.session.api = api
	app.playing = true
	app.session.item = {"Id": "item"}
	app.session.source = {"Id": "source"}
	app.session.media_source_id = "source"
	video.paused = true
	await app._select_audio(2)
	check(video.paused and video.position == 42000, "Changing audio preserves pause state and the current position")
	check(app.session.audio_index == 2 and not app.seeking, "A prepared replacement stream completes the track change")
	await app._select_subtitle(5)
	check(app.session.burn_subtitles and app.subtitles.index == 5 and video.paused, "Picture subtitle selection restarts playback and preserves pause")
	await app._select_subtitle(-1)
	check(not app.session.burn_subtitles and app.subtitles.index == -1 and video.paused, "Turning off burned-in subtitles reopens a stream without them")
	app.session.started = false
	await app._stop(false)
	check(app.subtitles.index == -1 and app.subtitle_overlay.text.is_empty(), "Stopping clears subtitle display and selection")
	app.queue_free()
	await process_frame

