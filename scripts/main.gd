extends Node3D

var settings := JellyXRSettings.new()
var session_store := SessionStore.new()
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
var settings_return_page: Control
var settings_return_heading := ""
var settings_return_status := ""
var status: Label
var keyboard: VRKeyboard
var material: ShaderMaterial
var theatre: TheatreEnvironment
var world: ViewingWorld
var player_overlay: PlayerOverlay
var mode := Stereo.Mode.MONO
var stereo_overridden := false
var projection_mode := VideoProjection.Mode.SCREEN
var projection_overridden := false
var video_size := Vector2i(1920, 1080)
var playing := false
var elapsed := 0.0
var transcode_offset := 0
var quick_generation := 0
var countdown_generation := 0
var autoplay_pending := false
var seeking := false
var seek_paused := false
var timeline_elapsed := 0.0
var decoder_ready := false
var media_segments := MediaSegments.new()
var photo_active := false
var photo_loading := false
var photo_item: Dictionary = {}
var video_material: ShaderMaterial
var photo_loader: PhotoView
var photo_sequence := PhotoSequence.new()

func _ready() -> void:
	settings.load_settings()
	api.device_id = settings.device_id
	add_child(api)
	session.api = api
	session.settings = settings
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
	await _restore_session()

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
	world.player_loading.cancelled.connect(_show_library)
	world.player_skip_popup.skip_requested.connect(_skip_segment)
	material = world.material
	theatre = world.theatre
	video.material = material
	world.menu_requested.connect(_toggle_menu)
	world.settings_requested.connect(_toggle_settings)
	world.library_requested.connect(_toggle_controller_library)
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
	shell.return_from_settings.connect(_return_from_settings)
	shell.sign_out.connect(_sign_out)
	keyboard = VRKeyboard.new()
	viewport.add_child(keyboard)
	keyboard.hide()

func _clear_page(keep_settings_return: bool = false) -> void:
	if not keep_settings_return and is_instance_valid(settings_return_page):
		settings_return_page.queue_free()
		settings_return_page = null
	shell.set_settings_mode(false)
	page_generation += 1
	countdown_generation += 1
	_cancel_countdown()
	shell.heading.show()
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
	shell.heading.hide()
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
	Widgets.label("HTTP sends credentials without encryption. Use HTTPS outside your home network.", page, 18)
	status.text = "Sign in to start watching."

func _restore_session() -> void:
	var data: Variant = session_store.load_session()
	if video.has_android_services():
		var saved: String = video.bridge.load_session()
		data = JSON.parse_string(saved) if not saved.is_empty() else null
	if not data is Dictionary or data.get("server", "") != settings.server: return
	for key in ["token", "user_id"]:
		if not data.get(key) is String or data[key].is_empty(): return
	if not api.configure(settings.server): return
	api.token = data.token
	api.user_id = data.user_id
	var generation := page_generation
	status.text = "Restoring your saved session..."
	_set_login_enabled(false)
	var check := await api.request("/Users/Me")
	if generation != page_generation: return
	_set_login_enabled(true)
	if check.ok:
		_show_library()
	else:
		api.token = ""
		api.user_id = ""
		if check.get("status", 0) in [401, 403]:
			_clear_saved_session()
			status.text = "Your saved session has expired. Sign in again."
		else:
			status.text = "Could not restore your saved session. Check your connection or sign in again."

func _set_login_enabled(enabled: bool) -> void:
	for button in page.find_children("*", "BaseButton", true, false):
		button.disabled = not enabled
	for field in page.find_children("*", "LineEdit", true, false):
		field.editable = enabled

func _clear_saved_session() -> void:
	if video.has_android_services(): video.bridge.save_session("")
	elif session_store.clear_session() != OK:
		push_warning("Could not remove the saved sign-in session.")

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
	else:
		var error := session_store.save_session({"server": api.server, "token": api.token, "user_id": api.user_id})
		if error != OK:
			push_warning("Could not save the sign-in session. Check available storage and permissions.")
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

func _toggle_controller_library() -> void:
	if api.token.is_empty(): return
	if autoplay_pending:
		_show_library()
		return
	for child in page.get_children():
		if child is SettingsView:
			_return_from_settings()
			return
	_toggle_panel()

func _toggle_panel() -> void:
	panel.visible = not panel.visible
	player_overlay.hide()
	keyboard.hide()

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
	library.status.connect(func(message: String):
		if library == settings_return_page:
			settings_return_status = message
		else:
			status.text = message)
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

func _details(item: Dictionary, season: Dictionary = {}) -> void:
	if item.get("Type", "") == "Photo":
		photo_sequence = PhotoSequence.new()
		for child in page.get_children():
			if child is LibraryView: photo_sequence.capture(child, item)
		_show_photo(item)
		return
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
	view.initial_season = season
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.play_requested.connect(_start)
	view.play_from_start_requested.connect(_start.bind(true))
	view.version_requested.connect(_choose_media_version)
	view.back_requested.connect(_show_library)
	page.add_child(view)
	status.text = "Ready."

func _show_photo(item: Dictionary) -> void:
	page_generation += 1
	var current := page_generation
	await _stop(false)
	if current != page_generation: return
	photo_active = true
	photo_item = item
	video_material = material
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/pc_video.gdshader")
	screen.material_override = material
	world.panorama.material_override = material
	mode = PhotoView.stereo_mode(item)
	projection_mode = VideoProjection.detect({"Path": item.get("Path", item.get("Name", ""))})
	stereo_overridden = false
	projection_overridden = false
	photo_loader = PhotoView.new()
	photo_loader.api = api
	photo_loader.item = item
	photo_loader.photo_ready.connect(_photo_ready)
	photo_loader.failed.connect(_photo_failed)
	status.text = "Loading photo..."
	photo_loading = true
	keyboard.hide()
	panel.hide()
	screen.show()
	_resize_screen()
	_update_loading()
	add_child(photo_loader)
	photo_loader._load()

func _photo_ready(texture: Texture2D) -> void:
	if not photo_active: return
	photo_loading = false
	_update_loading()
	material.set_shader_parameter("video_texture", texture)
	video_size = Vector2i(texture.get_size())
	screen.show()
	world.set_panoramic(projection_mode != VideoProjection.Mode.SCREEN, VideoProjection.horizontal_angle(projection_mode))
	_resize_screen()
	status.text = ""
	_show_playback()

func _photo_failed(message: String) -> void:
	_close_photo()
	status.text = message + " Select the photo to try again."
	panel.show()

func _step_photo(direction: int) -> void:
	if not photo_active or photo_sequence.busy: return
	var current := page_generation
	player_overlay.set_photo_navigation(false, false)
	photo_loading = true
	_update_loading()
	var result := await photo_sequence.step(direction, api)
	if current != page_generation or not photo_active: return
	if result.has("item"):
		await _show_photo(result.item)
	else:
		photo_loading = false
		_update_loading()
		player_overlay.set_photo_navigation(photo_sequence.index > 0, photo_sequence.can_next())
		if result.has("error"): player_overlay.tooltip.text = result.error

func _close_photo() -> void:
	if not photo_active: return
	photo_active = false
	photo_loading = false
	world.player_loading.hide()
	photo_item = {}
	if is_instance_valid(photo_loader):
		remove_child(photo_loader)
		photo_loader.queue_free()
		photo_loader = null
	material = video_material
	screen.material_override = material
	world.panorama.material_override = material
	video_material = null
	world.set_panoramic(false)
	player_overlay.set_photo_mode(false)

func _start(item: Dictionary, from_start: bool = false) -> void:
	var requested_source := str(item.get("SelectedMediaSourceId", ""))
	if not from_start and playing and str(session.item.get("Id", "")) == str(item.get("Id", "")) and (requested_source.is_empty() or requested_source == session.media_source_id):
		if video.paused:
			video.toggle_pause()
			session.report("Progress", false)
		_show_playback()
		return
	if not video.available():
		status.text = video.unavailable_message()
		return
	await _stop(false)
	projection_overridden = false
	stereo_overridden = false
	projection_mode = VideoProjection.Mode.SCREEN
	world.set_panoramic(false)
	_resize_screen()
	status.text = "Preparing playback..."
	playing = true
	screen.show()
	_show_playback()
	player_overlay.title.text = DetailsMetadata.title(item, "Now playing")
	media_segments.load_item(api, str(item.Id))
	var selected := item
	if from_start:
		selected = item.duplicate(true)
		if not selected.get("UserData") is Dictionary: selected.UserData = {}
		selected.UserData.PlaybackPositionTicks = 0
	await session.open(selected)

func _choose_media_version(item: Dictionary) -> void:
	var sources: Array = item.get("MediaSources", []) if item.get("MediaSources") else []
	_clear_page()
	shell.heading.text = "Playback"
	panel.show()
	player_overlay.hide()
	Widgets.button("Back to details", _details.bind(item), page)
	var title := Widgets.label("Choose a version", page, 36)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var name_label := Widgets.label(DetailsMetadata.title(item), page, 26)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	page.add_child(scroll)
	var choices := VBoxContainer.new()
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.add_theme_constant_override("separation", 12)
	scroll.add_child(choices)
	for index in range(sources.size()):
		var source: Dictionary = sources[index]
		var selected := item.duplicate(true)
		selected["SelectedMediaSourceId"] = str(source.get("Id", ""))
		var label := str(source.get("Name", "")) if source.get("Name") else "Version %d" % (index + 1)
		var button := Widgets.button(label, _start.bind(selected), choices)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = selected.SelectedMediaSourceId.is_empty()
		if index == 0: button.grab_focus.call_deferred()
	status.text = "Select the version to play."

func _play_stream(url: String, source: Dictionary, start_ms: int) -> void:
	var keep_menu_open := playing and panel.visible
	decoder_ready = false
	if not seeking and not stereo_overridden: mode = Stereo.detect(source)
	if not seeking and not projection_overridden:
		projection_mode = VideoProjection.detect(source)
		world.set_panoramic(projection_mode != VideoProjection.Mode.SCREEN, VideoProjection.horizontal_angle(projection_mode))
	for stream in source.get("MediaStreams", []):
		if stream.get("Type", "") == "Video":
			video_size = Vector2i(int(stream.get("Width", 1920)), int(stream.get("Height", 1080)))
	transcode_offset = session.position_ticks if session.method == "Transcode" and not session.is_hls() else 0
	if not seeking: _resize_screen()
	screen.show()
	playing = true
	if not seeking and not keep_menu_open: _show_playback()
	_update_timeline()
	await video.open(url, api.authorization(), start_ms)

func _video_prepared() -> void:
	decoder_ready = true
	if seeking and seek_paused: video.toggle_pause()
	session.report("Playing", video.paused)
	status.text = "Playing. Press A for controls or B for the library."
	if get_viewport().use_xr and not seeking and not panel.visible:
		player_overlay.hide()
	seeking = false
	_update_timeline()

func _show_playback() -> void:
	keyboard.hide()
	panel.hide()
	player_overlay.set_photo_mode(photo_active)
	if photo_active: player_overlay.set_photo_navigation(photo_sequence.index > 0, photo_sequence.can_next())
	player_overlay.title.text = DetailsMetadata.title(photo_item if photo_active else session.item, "Now playing")
	player_overlay.show()
	_update_timeline()

func _player_action(action: String) -> void:
	if photo_active and action in ["pause", "back", "forward", "skip_segment"]: return
	match action:
		"previous_photo": _step_photo(-1)
		"next_photo": _step_photo(1)
		"pause":
			video.toggle_pause()
			session.report("Progress", video.paused)
			_update_timeline()
		"back": _skip(-10000)
		"forward": _skip(30000)
		"skip_segment": _skip_segment()
		"stop": _stop()
		"settings": _screen_settings()
		"library": _return_to_title()
		"hide": player_overlay.hide()

func _return_to_title() -> void:
	if photo_active:
		_show_library()
		return
	var item := session.item
	if item.is_empty():
		_show_library()
		return
	var target_id := str(item.get("SeriesId", "")) if item.get("Type", "") == "Episode" else str(item.Id)
	if target_id.is_empty(): target_id = str(item.Id)
	var season: Dictionary = {}
	if item.get("Type", "") == "Episode" and item.get("SeasonId"):
		season = {"Id": item.SeasonId, "Name": "Season %d" % int(item.get("ParentIndexNumber", 0)), "IndexNumber": item.get("ParentIndexNumber")}
	for child in page.get_children():
		if child is DetailsView and str(child.item.Id) == target_id:
			page_generation += 1
			player_overlay.hide()
			keyboard.hide()
			if get_viewport().use_xr: panel.show()
			if child.series_browser and not season.is_empty() and str(child.series_browser.selected_season.get("Id", "")) != str(season.Id):
				child.series_browser.open_season(season)
			return
	await _details({"Id": target_id}, season)

func _toggle_settings() -> void:
	if api.token.is_empty() or not shell.signed_in: return
	for child in page.get_children():
		if child is SettingsView:
			_toggle_panel()
			return
	_screen_settings()

func _screen_settings() -> void:
	if api.token.is_empty() or not shell.signed_in: return
	for child in page.get_children():
		if child is LibraryView or child is DetailsView:
			settings_return_page = child
			settings_return_heading = shell.heading.text
			settings_return_status = status.text
			child.hide()
			child.reparent(viewport)
	_clear_page(true)
	panel.show()
	shell.heading.text = "Settings"
	shell.set_settings_mode(true)
	var view := SettingsView.new()
	view.navigation_host = shell.settings_navigation
	view.settings = settings
	view.passthrough_supported = world.passthrough.is_supported()
	view.stereo_mode = mode
	view.projection_mode = projection_mode
	view.swap_eyes = material.get_shader_parameter("swap_eyes") == true
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.screen_changed.connect(func(): _resize_screen(); _position_screen())
	view.screen_follow_changed.connect(_update_screen_follow)
	view.environment_changed.connect(_change_environment)
	view.stereo_selected.connect(_select_stereo)
	view.projection_selected.connect(_select_projection)
	view.eyes_swapped.connect(func(): material.set_shader_parameter("swap_eyes", not material.get_shader_parameter("swap_eyes")))
	view.status.connect(func(message: String): status.text = message)
	page.add_child(view)
	status.text = "Changes take effect as you make them."

func _return_from_settings() -> void:
	if not is_instance_valid(settings_return_page):
		_show_library()
		return
	var previous := settings_return_page
	settings_return_page = null
	_clear_page()
	previous.reparent(page)
	previous.show()
	shell.heading.text = settings_return_heading
	status.text = settings_return_status
	panel.show()

func _resize_screen() -> void:
	var panoramic := projection_mode != VideoProjection.Mode.SCREEN
	var aspect_ratio := 16.0 / 9.0 if panoramic else Stereo.aspect(video_size.x, video_size.y, mode)
	var fixed_screen := settings.is_theatre() and not panoramic
	var dimensions := Vector2(settings.width, settings.width / aspect_ratio)
	if panoramic: dimensions = Vector2(3.6, 3.6 / aspect_ratio)
	elif fixed_screen: dimensions = theatre.video_size(aspect_ratio)
	var curvature := 0.0 if fixed_screen or panoramic else settings.curvature
	screen.mesh = null if panoramic else Stereo.mesh(dimensions.x, aspect_ratio, curvature)
	material.set_shader_parameter("stereo", mode != Stereo.Mode.MONO)
	material.set_shader_parameter("top_bottom", mode == Stereo.Mode.TOP_BOTTOM)
	player_overlay.fit_screen(dimensions.x, aspect_ratio, curvature)
	world.player_loading.fit_screen(dimensions.x, curvature)
	world.skip_screen_size = Vector3(dimensions.x, aspect_ratio, curvature)

func _select_projection(value: int) -> void:
	projection_mode = value
	projection_overridden = true
	world.set_panoramic(value != VideoProjection.Mode.SCREEN, VideoProjection.horizontal_angle(projection_mode))
	_recenter_video()

func _select_stereo(value: int) -> void:
	mode = value
	stereo_overridden = true
	_resize_screen()

func _change_environment() -> void:
	world.apply_environment()
	if not theatre.visible: screen.global_basis = camera.global_basis
	_position_screen()
	_resize_screen()

func _recenter() -> void:
	panel.global_transform = camera.global_transform
	panel.position += -camera.global_basis.z * 2.7
	_recenter_video()

func _recenter_video() -> void:
	screen.global_basis = camera.global_basis
	theatre.recenter(camera.global_transform)
	world.panorama.global_position = camera.global_position
	world.panorama.global_rotation = Vector3(0.0, camera.global_rotation.y, 0.0)
	_position_screen()
	_resize_screen()

func _position_screen() -> void:
	if projection_mode != VideoProjection.Mode.SCREEN:
		screen.global_position = camera.global_position - screen.global_basis.z * 3.0
	elif settings.is_theatre():
		screen.global_transform = theatre.projection_transform()
	else:
		screen.global_position = camera.global_position - screen.global_basis.z * settings.distance + screen.global_basis.y * settings.height

func _update_screen_follow() -> void:
	if not settings.follow_screen or settings.environment not in ["Void", "Passthrough"]: return
	if projection_mode != VideoProjection.Mode.SCREEN: return
	screen.global_basis = camera.global_basis
	_position_screen()

func _toggle_menu() -> void:
	if not get_viewport().use_xr: return
	if autoplay_pending:
		_show_library()
		return
	if playing or photo_active:
		if player_overlay.visible: player_overlay.hide()
		else: _show_playback()
	else: panel.visible = not panel.visible

func _skip(amount: int) -> void:
	_seek_to(int(transcode_offset / 10000) + video.position_ms() + amount)

func _duration_ms() -> int:
	var ticks := int(session.source.get("RunTimeTicks", 0))
	if ticks <= 0: ticks = int(session.item.get("RunTimeTicks", 0))
	if ticks > 0: return int(ticks / 10000)
	var duration := video.duration_ms()
	return duration + int(transcode_offset / 10000) if duration > 0 else 0

func _update_timeline() -> void:
	if autoplay_pending or photo_active: return
	player_overlay.update_time(int(transcode_offset / 10000) + video.position_ms(), _duration_ms(), decoder_ready and not seeking, video.paused)
	world.player_skip_popup.update_segment(_active_segment())
	_update_loading()

func _active_segment() -> Dictionary:
	if not playing or not decoder_ready or seeking: return {}
	return media_segments.active(int(transcode_offset / 10000) + video.position_ms(), _duration_ms())

func _skip_segment() -> void:
	var segment := _active_segment()
	if not segment.is_empty(): _seek_to(int(segment.target_ms))

func _update_loading() -> void:
	if autoplay_pending: return
	if photo_active and photo_loading:
		world.player_loading.show_photo_loading()
	elif playing and (not decoder_ready or seeking):
		world.player_loading.show_loading()
	elif playing and video.is_buffering():
		world.player_loading.show_buffering()
	else:
		world.player_loading.hide()

func _seek_to(milliseconds: int) -> void:
	if not playing or seeking or not decoder_ready: return
	var target := clampi(milliseconds, 0, maxi(0, _duration_ms() - 1000))
	if session.method != "Transcode" or session.is_hls():
		video.seek(target)
		return
	seeking = true
	seek_paused = video.paused
	decoder_ready = false
	var generation := countdown_generation
	_update_timeline()
	session.position_ticks = transcode_offset + video.position_ms() * 10000
	video.stop()
	status.text = "Seeking..."
	await session.report("Stopped")
	if generation != countdown_generation: return
	session.position_ticks = target * 10000
	await session.open(session.item, true)

func _stop(show_library: bool = true, completed: bool = false) -> void:
	_close_photo()
	media_segments.clear()
	world.player_skip_popup.update_segment({})
	countdown_generation += 1
	_cancel_countdown()
	world.player_loading.hide()
	player_overlay.hide()
	seeking = false
	decoder_ready = false
	if playing:
		session.position_ticks = transcode_offset + video.position_ms() * 10000
		if completed: session.position_ticks = maxi(session.position_ticks, _duration_ms() * 10000)
		video.stop()
		playing = false
		await session.report("Stopped")
	screen.hide()
	if show_library and not api.token.is_empty(): _show_library()

func _ended() -> void:
	if not playing: return
	var previous := session.item.duplicate(true)
	var generation := countdown_generation + 1
	await _stop(false, true)
	if generation != countdown_generation: return
	if previous.get("Type", "") != "Episode":
		_show_library()
		return
	panel.hide()
	screen.show()
	autoplay_pending = true
	world.player_loading.show_loading()
	var result := await api.next_episode(previous)
	if generation != countdown_generation: return
	if not result.ok:
		_show_library()
		status.text = "Could not load the next episode. " + result.error
		return
	if result.data.is_empty():
		_show_library()
		return
	await _countdown(result.data)

func _countdown(next: Dictionary) -> void:
	_clear_page()
	autoplay_pending = true
	panel.hide()
	screen.show()
	var generation := countdown_generation
	for seconds in range(5, 0, -1):
		if generation != countdown_generation: return
		world.player_loading.show_countdown(DetailsMetadata.title(next, "Next episode"), seconds)
		await get_tree().create_timer(1).timeout
	if generation == countdown_generation: _start(next)

func _cancel_countdown() -> void:
	if not autoplay_pending: return
	autoplay_pending = false
	world.player_loading.hide()
	screen.hide()

func _video_failed(message: String) -> void:
	status.text = message
	if video.available() and playing:
		decoder_ready = false
		_update_timeline()
		session.position_ticks = transcode_offset + video.position_ms() * 10000
		video.stop()
		await session.retry_transcode()

func _error(message: String) -> void:
	media_segments.clear()
	world.player_skip_popup.update_segment({})
	countdown_generation += 1
	_cancel_countdown()
	world.player_loading.hide()
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
	_clear_saved_session()
	_show_login()

func _process(delta: float) -> void:
	_update_screen_follow()
	if not playing: return
	_update_loading()
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
