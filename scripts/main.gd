extends Node3D

var settings := JellyframeSettings.new()
var api := JellyfinClient.new()
var session := PlaybackSession.new()
var video: VideoBackend = AndroidVideo.new() if OS.get_name() == "Android" else PcVideo.new()
var camera: Camera3D
var panel: MeshInstance3D
var screen: MeshInstance3D
var viewport: SubViewport
var shell: UiShell
var libraries_loaded := false
var library_generation := 0
var page_generation := 0
var page: VBoxContainer
var status: Label
var keyboard: VRKeyboard
var material: ShaderMaterial
var theatre: TheatreEnvironment
var world: ViewingWorld
var player_overlay: PlayerOverlay
var mode := Stereo.Mode.MONO
var video_size := Vector2i(1920, 1080)
var playing := false
var elapsed := 0.0
var transcode_offset := 0
var quick_generation := 0
var countdown_generation := 0
var calibration := false
var seeking := false
var seek_paused := false
var timeline_elapsed := 0.0
var decoder_ready := false

func _ready() -> void:
	settings.load_settings()
	api.device_id = settings.device_id
	add_child(api)
	session.api = api
	add_child(session)
	add_child(video)
	_setup_world()
	add_child(MenuFeedback.new())
	_setup_ui()
	session.stream_ready.connect(_play_stream)
	session.failed.connect(_error)
	video.failed.connect(_video_failed)
	video.prepared.connect(_video_prepared)
	video.ended.connect(_ended)
	video.size_changed.connect(func(w: int, h: int): video_size = Vector2i(w, h); _resize_screen())
	_show_login()
	if video.has_android_services() and OS.is_debug_build() and video.bridge.calibration_requested():
		await get_tree().create_timer(2).timeout
		_calibrate()

func _setup_world() -> void:
	world = ViewingWorld.new()
	world.settings = settings
	add_child(world)
	world.setup()
	camera = world.camera
	viewport = world.viewport
	panel = world.panel
	screen = world.screen
	player_overlay = world.player_overlay
	player_overlay.action.connect(_player_action)
	player_overlay.seek_requested.connect(_seek_to)
	material = world.material
	theatre = world.theatre
	video.material = material
	world.menu_requested.connect(_toggle_menu)
	var xr := XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr:
		xr.pose_recentered.connect(_recenter, CONNECT_DEFERRED)
	_recenter()
	var startup := StartupRecenter.new()
	startup.ready_to_center.connect(func(): _recenter(); panel.show())
	add_child(startup)
	if get_viewport().use_xr: panel.hide()

func _setup_ui() -> void:
	shell = UiShell.new()
	viewport.add_child(shell)
	page = shell.page
	status = shell.status
	shell.navigate.connect(_open_library)
	shell.screen_settings.connect(_screen_settings)
	shell.sign_out.connect(_sign_out)
	keyboard = VRKeyboard.new()
	viewport.add_child(keyboard)
	keyboard.hide()

func _clear_page() -> void:
	page_generation += 1
	player_overlay.hide()
	if get_viewport().use_xr: panel.show()
	keyboard.hide()
	for child in page.get_children():
		page.remove_child(child)
		child.queue_free()

func _field(placeholder: String, secret: bool = false) -> LineEdit:
	var field := Widgets.input(placeholder, page, secret)
	field.focus_entered.connect(func(): keyboard.edit.call_deferred(field))
	return field

func _show_login() -> void:
	shell.set_signed_in(false)
	_clear_page()
	Widgets.label("Watch Jellyfin in VR", page, 40)
	Widgets.label("Connect to your Jellyfin server", page)
	var address := _field("https://jellyfin.example.com")
	address.text = settings.server
	var username := _field("Username")
	var password := _field("Password", true)
	var row := HBoxContainer.new()
	page.add_child(row)
	var login := Widgets.button("Sign in", func(): pass, row)
	Widgets.accent(login)
	login.pressed.connect(func():
		if not _configure(address.text): return
		login.disabled = true
		status.text = "Signing in..."
		keyboard.hide()
		var result := await api.login(username.text, password.text)
		if not is_instance_valid(login): return
		login.disabled = false
		password.clear()
		if result.ok: _signed_in()
		else: status.text = result.error)
	Widgets.button("Quick Connect", func():
		if _configure(address.text): _quick_connect(), row)
	if video.has_android_services() and OS.is_debug_build():
		Widgets.button("Test 3D playback", _calibrate, row)
	Widgets.label("HTTP sends credentials without encryption. Use HTTPS outside your home network.", page, 18)
	status.text = "Sign in to start watching."
	if video.has_android_services():
		var saved: String = video.bridge.load_session()
		var data: Variant = JSON.parse_string(saved) if not saved.is_empty() else null
		if data is Dictionary and data.get("server", "") == settings.server and api.configure(settings.server):
			api.token = data.get("token", "")
			api.user_id = data.get("user_id", "")
			var check := await api.request("/Users/Me")
			if check.ok: _show_library()
			else:
				api.token = ""
				api.user_id = ""
				status.text = "Your saved session has expired. Sign in again."

func _configure(address: String) -> bool:
	if not api.configure(address):
		status.text = "Enter a server address beginning with https:// or http://."
		return false
	return true

func _signed_in() -> void:
	settings.server = api.server
	settings.save()
	if video.has_android_services():
		video.bridge.save_session(JSON.stringify({"server": api.server, "token": api.token, "user_id": api.user_id}))
	_show_library()

func _quick_connect() -> void:
	quick_generation += 1
	var generation := quick_generation
	var result := await api.request("/QuickConnect/Initiate", HTTPClient.METHOD_POST)
	if not result.ok:
		status.text = result.error
		return
	_clear_page()
	Widgets.label("Approve this code in Jellyfin", page, 36)
	Widgets.label(str(result.data.get("Code", "")), page, 60)
	Widgets.button("Cancel", func(): quick_generation += 1; _show_login(), page)
	var secret: String = result.data.get("Secret", "")
	for attempt in range(60):
		await get_tree().create_timer(3).timeout
		if generation != quick_generation: return
		var state := await api.request("/QuickConnect/Connect" + api.query({"secret": secret}))
		if generation != quick_generation: return
		if not state.ok:
			status.text = state.error
			return
		if state.data.get("Authenticated", false):
			var auth := await api.request("/Users/AuthenticateWithQuickConnect", HTTPClient.METHOD_POST, {"Secret": secret})
			if generation != quick_generation: return
			auth = api.accept_login(auth)
			if auth.ok: _signed_in()
			else: status.text = auth.error
			return
	status.text = "The code expired. Cancel and request a new code."

func _show_library() -> void:
	var title := "Home"
	if shell.buttons.has(shell.selected_id): title = shell.buttons[shell.selected_id].text
	_open_library(shell.selected_id, title)

func _open_library(id: String, title: String) -> void:
	_clear_page()
	shell.set_signed_in(true)
	shell.select(id, title)
	var library := LibraryView.new()
	library.api = api
	library.library_id = id
	library.library_name = title
	api.library_sort_by = settings.library_sort_by
	api.library_sort_order = settings.library_sort_order
	library.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library.status.connect(func(message: String): status.text = message)
	library.selected.connect(_details)
	page.add_child(library)
	library.field.focus_entered.connect(func(): keyboard.edit.call_deferred(library.field))
	if not libraries_loaded: _load_libraries()

func _load_libraries() -> void:
	libraries_loaded = true
	library_generation += 1
	var generation := library_generation
	shell.clear_libraries()
	Widgets.label("Loading...", shell.libraries, 17)
	var result := await api.views()
	if generation != library_generation: return
	if result.ok:
		shell.set_libraries(result.data.get("Items", []))
	else:
		shell.clear_libraries()
		Widgets.label("Could not load libraries", shell.libraries, 17)
		Widgets.button("Retry libraries", _load_libraries, shell.libraries).add_theme_font_size_override("font_size", 17)

func _details(item: Dictionary) -> void:
	page_generation += 1
	var current := page_generation
	status.text = "Loading details..."
	var result := await api.details(item.Id)
	if current != page_generation: return
	if not result.ok:
		status.text = result.error
		return
	var detail: Dictionary = result.data
	_clear_page()
	var view := DetailsView.new()
	view.item = detail
	view.api = api
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.play_requested.connect(_start)
	view.back_requested.connect(_show_library)
	page.add_child(view)
	status.text = "Ready."

func _start(item: Dictionary) -> void:
	if not video.available():
		status.text = video.unavailable_message()
		return
	await _stop(false)
	calibration = false
	status.text = "Preparing playback..."
	await session.open(item)

func _play_stream(url: String, source: Dictionary, start_ms: int) -> void:
	decoder_ready = false
	if not seeking: mode = Stereo.detect(source)
	for stream in source.get("MediaStreams", []):
		if stream.get("Type", "") == "Video":
			video_size = Vector2i(int(stream.get("Width", 1920)), int(stream.get("Height", 1080)))
	transcode_offset = session.position_ticks if session.method == "Transcode" else 0
	if not seeking: _recenter()
	screen.show()
	playing = true
	if not seeking: _show_playback()
	_update_timeline()
	await video.open(url, api.authorization(), start_ms)

func _video_prepared() -> void:
	decoder_ready = true
	if seeking and seek_paused: video.toggle_pause()
	session.report("Playing", video.paused)
	status.text = "Playing. Press A or B to show the controls."
	if get_viewport().use_xr and not seeking:
		panel.hide()
		player_overlay.hide()
	seeking = false
	_update_timeline()

func _show_playback() -> void:
	keyboard.hide()
	panel.hide()
	player_overlay.title.text = session.item.get("Name", "Now playing")
	player_overlay.show()
	_update_timeline()

func _player_action(action: String) -> void:
	match action:
		"pause":
			video.toggle_pause()
			session.report("Progress", video.paused)
			_update_timeline()
		"back": _skip(-10000)
		"forward": _skip(30000)
		"stop": _stop()
		"settings": _screen_settings()
		"library": _show_library()
		"hide": player_overlay.hide()

func _screen_settings() -> void:
	_clear_page()
	var previous_heading := shell.heading.text if shell.heading.text != "Settings" else "Home"
	shell.heading.text = "Settings"
	var view := SettingsView.new()
	view.settings = settings
	view.passthrough_supported = world.passthrough.is_supported()
	view.stereo_mode = mode
	view.swap_eyes = material.get_shader_parameter("swap_eyes") == true
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.screen_changed.connect(func(): _resize_screen(); _position_screen())
	view.environment_changed.connect(_change_environment)
	view.stereo_selected.connect(func(value: int): mode = value; _resize_screen())
	view.eyes_swapped.connect(func(): material.set_shader_parameter("swap_eyes", not material.get_shader_parameter("swap_eyes")))
	view.status.connect(func(message: String): status.text = message)
	view.back_requested.connect(func():
		shell.heading.text = previous_heading
		if playing: _show_playback()
		elif not api.token.is_empty(): _show_library()
		else: _show_login())
	page.add_child(view)
	status.text = "Changes apply immediately."

func _resize_screen() -> void:
	var aspect_ratio := Stereo.aspect(video_size.x, video_size.y, mode)
	var dimensions := theatre.video_size(aspect_ratio) if settings.environment == "Theatre" else Vector2(settings.width, settings.width / aspect_ratio)
	var curvature := 0.0 if settings.environment == "Theatre" else settings.curvature
	screen.mesh = Stereo.mesh(dimensions.x, aspect_ratio, curvature)
	material.set_shader_parameter("stereo", mode != Stereo.Mode.MONO)
	player_overlay.fit_screen(dimensions.x, aspect_ratio, curvature)

func _change_environment() -> void:
	world.apply_environment()
	theatre.visible = settings.environment == "Theatre"
	if not theatre.visible: screen.global_basis = camera.global_basis
	_position_screen()
	_resize_screen()

func _recenter() -> void:
	panel.global_transform = camera.global_transform
	panel.position += -camera.global_basis.z * 2.7
	screen.global_basis = camera.global_basis
	theatre.recenter(camera.global_transform)
	_position_screen()
	_resize_screen()

func _position_screen() -> void:
	if settings.environment == "Theatre":
		screen.global_transform = theatre.projection_transform()
	else:
		screen.global_position = camera.global_position - screen.global_basis.z * settings.distance + screen.global_basis.y * settings.height

func _toggle_menu() -> void:
	if not get_viewport().use_xr: return
	if playing:
		if player_overlay.visible: player_overlay.hide()
		else: _show_playback()
	else: panel.visible = not panel.visible

func _skip(amount: int) -> void:
	_seek_to(int(transcode_offset / 10000) + video.position_ms() + amount)

func _duration_ms() -> int:
	if calibration: return video.duration_ms()
	var ticks := int(session.source.get("RunTimeTicks", 0))
	if ticks <= 0: ticks = int(session.item.get("RunTimeTicks", 0))
	if ticks > 0: return int(ticks / 10000)
	var duration := video.duration_ms()
	return duration + int(transcode_offset / 10000) if duration > 0 else 0

func _update_timeline() -> void:
	player_overlay.update_time(int(transcode_offset / 10000) + video.position_ms(), _duration_ms(), decoder_ready and not seeking, video.paused)

func _seek_to(milliseconds: int) -> void:
	if not playing or seeking or not decoder_ready: return
	var target := clampi(milliseconds, 0, maxi(0, _duration_ms() - 1000))
	if calibration or session.method != "Transcode":
		video.seek(target)
		return
	seeking = true
	seek_paused = video.paused
	decoder_ready = false
	var generation := countdown_generation
	session.position_ticks = transcode_offset + video.position_ms() * 10000
	video.stop()
	status.text = "Seeking..."
	await session.report("Stopped")
	if generation != countdown_generation: return
	session.position_ticks = target * 10000
	await session.open(session.item, true)

func _stop(show_library: bool = true) -> void:
	countdown_generation += 1
	player_overlay.hide()
	seeking = false
	decoder_ready = false
	if playing:
		session.position_ticks = transcode_offset + video.position_ms() * 10000
		video.stop()
		playing = false
		await session.report("Stopped")
	screen.hide()
	if show_library and not api.token.is_empty(): _show_library()

func _ended() -> void:
	if calibration:
		await _stop(false)
		calibration = false
		_show_login()
		if get_viewport().use_xr: panel.show()
		return
	var previous := session.item.duplicate(true)
	await _stop(false)
	if get_viewport().use_xr: panel.show()
	if previous.get("Type", "") != "Episode":
		_show_library()
		return
	var result := await api.request("/Shows/NextUp" + api.query({"UserId": api.user_id, "SeriesId": previous.get("SeriesId", ""), "Limit": 1}))
	if not result.ok or result.data.get("Items", []).is_empty():
		_show_library()
		return
	var next: Dictionary = result.data.Items[0]
	if next.Id == previous.Id:
		_show_library()
		return
	_clear_page()
	var label := Widgets.label("", page, 36)
	var generation := countdown_generation
	Widgets.button("Cancel autoplay", func(): countdown_generation += 1; _show_library(), page)
	for seconds in range(10, 0, -1):
		if generation != countdown_generation: return
		label.text = "%s starts in %d seconds" % [next.get("Name", "Next episode"), seconds]
		await get_tree().create_timer(1).timeout
	if generation == countdown_generation: _start(next)

func _video_failed(message: String) -> void:
	status.text = message
	if calibration:
		_error(message)
		return
	if video.available() and playing:
		session.position_ticks = transcode_offset + video.position_ms() * 10000
		video.stop()
		await session.retry_transcode()

func _error(message: String) -> void:
	player_overlay.hide()
	seeking = false
	decoder_ready = false
	status.text = message
	playing = false
	video.stop()
	screen.hide()
	if get_viewport().use_xr: panel.show()

func _sign_out() -> void:
	library_generation += 1
	libraries_loaded = false
	shell.selected_id = ""
	quick_generation += 1
	await _stop(false)
	if not api.token.is_empty(): await api.request("/Sessions/Logout", HTTPClient.METHOD_POST)
	api.token = ""
	api.user_id = ""
	api.random_library_ids.clear()
	api.random_library_generation.clear()
	if video.has_android_services(): video.bridge.save_session("")
	_show_login()

func _process(delta: float) -> void:
	if not playing: return
	timeline_elapsed += delta
	if timeline_elapsed >= 0.25:
		timeline_elapsed = 0.0
		_update_timeline()
	if seeking: return
	elapsed += delta
	if elapsed >= 10:
		elapsed = 0
		session.position_ticks = transcode_offset + video.position_ms() * 10000
		session.report("Progress", video.paused)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: _toggle_menu()


func _calibrate() -> void:
	transcode_offset = 0
	decoder_ready = false
	print("Jellyframe: calibration requested")
	calibration = true
	mode = Stereo.Mode.HALF_SBS
	video_size = Vector2i(1920, 1080)
	_resize_screen()
	_recenter()
	print("Jellyframe: calibration screen positioned")
	screen.show()
	playing = true
	status.text = "Close one eye at a time. You should see LEFT in your left eye and RIGHT in your right eye."
	await video.open(video.bridge.calibration_url(), "", 0)
	if get_viewport().use_xr: panel.hide()



