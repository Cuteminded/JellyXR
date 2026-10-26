class_name UiShell
extends HBoxContainer

signal navigate(id: String, title: String)
signal screen_settings
signal sign_out
signal return_from_settings
var page: VBoxContainer
var status: Label
var libraries: VBoxContainer
var settings_navigation: VBoxContainer
var navigation_heading: Label
var home: Button
var settings_button: Button
var logout: Button
var heading: Label
var rail: PanelContainer
var selected_id := ""
var signed_in := false
var settings_mode := false
var buttons: Dictionary = {}
var rail_background: StyleBoxFlat
var main_background: StyleBoxFlat

func _ready() -> void:
	theme = Widgets.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 24
	offset_right = -24
	offset_top = 24
	offset_bottom = -24
	add_theme_constant_override("separation", 24)
	rail = PanelContainer.new()
	rail.custom_minimum_size.x = 250
	rail_background = Widgets.surface(Color("111827"), 24, 14)
	rail.add_theme_stylebox_override("panel", rail_background)
	add_child(rail)
	var navigation := VBoxContainer.new()
	navigation.add_theme_constant_override("separation", 12)
	rail.add_child(navigation)
	var logo := TextureRect.new()
	logo.texture = preload("res://assets/logo/jellyframe-wordmark.png")
	logo.custom_minimum_size = Vector2(180, 72)
	logo.accessibility_name = "Jellyframe"
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	navigation.add_child(logo)
	home = Widgets.button("Home", _home_pressed, navigation)
	_style_navigation_button(home, preload("res://assets/icons/material/home.svg"))
	navigation_heading = Widgets.label("LIBRARIES", navigation, 14)
	navigation_heading.add_theme_color_override("font_color", Color("a4aec0"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	navigation.add_child(scroll)
	var lists := VBoxContainer.new()
	lists.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(lists)
	libraries = VBoxContainer.new()
	libraries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	libraries.add_theme_constant_override("separation", 10)
	lists.add_child(libraries)
	settings_navigation = VBoxContainer.new()
	settings_navigation.hide()
	lists.add_child(settings_navigation)
	settings_button = Widgets.button("Settings", func(): screen_settings.emit(), navigation)
	_style_navigation_button(settings_button, preload("res://assets/icons/material/settings.svg"))
	logout = Widgets.button("Sign out", func(): sign_out.emit(), navigation)
	_style_navigation_button(logout, preload("res://assets/icons/material/logout.svg"))
	var main := PanelContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_background = Widgets.surface(Color("101624"), 24, 28)
	main.add_theme_stylebox_override("panel", main_background)
	add_child(main)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	main.add_child(body)
	heading = Widgets.label("", body, 34)
	page = VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(page)
	status = Widgets.label("", body, 18)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", Color("a4aec0"))
	set_signed_in(false)

func set_signed_in(value: bool) -> void:
	set_settings_mode(false)
	signed_in = value
	rail.visible = value
	home.disabled = not value
	settings_button.disabled = not value
	logout.visible = value
	if not value:
		heading.text = ""
		clear_libraries()
		Widgets.label("Sign in to browse", libraries, 17)

func set_settings_mode(enabled: bool) -> void:
	settings_mode = enabled
	home.text = "Library" if enabled else "Home"
	home.icon = preload("res://assets/icons/material/video_library.svg") if enabled else preload("res://assets/icons/material/home.svg")
	libraries.visible = not enabled
	settings_navigation.visible = enabled
	navigation_heading.text = "SETTINGS" if enabled else "LIBRARIES"
	settings_button.visible = not enabled
	logout.visible = signed_in and not enabled
	if not enabled:
		for child in settings_navigation.get_children():
			settings_navigation.remove_child(child)
			child.queue_free()

func _home_pressed() -> void:
	if settings_mode:
		return_from_settings.emit()
	else:
		navigate.emit("", "Home")

func clear_libraries() -> void:
	buttons.clear()
	for child in libraries.get_children():
		libraries.remove_child(child)
		child.queue_free()

func set_libraries(items: Array) -> void:
	clear_libraries()
	for item in items:
		var library_type := str(item.get("CollectionType") if item.get("CollectionType") != null else "").to_lower()
		if library_type not in ["", "mixed", "movies", "tvshows", "homevideos", "photos"]: continue
		var id := str(item.get("Id", ""))
		var title := str(item.get("Name", "Library"))
		var button := Widgets.button(title, func(): navigate.emit(id, title), libraries)
		button.custom_minimum_size.x = 0
		button.clip_text = true
		button.tooltip_text = title
		_style_navigation_button(button, _library_icon(library_type))
		buttons[id] = button
	if buttons.is_empty():
		var empty := Widgets.label("No supported libraries", libraries, 17)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	select(selected_id, heading.text)

func _style_navigation_button(button: Button, icon: Texture2D) -> void:
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.icon = icon
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 24)
	button.add_theme_constant_override("h_separation", 10)
	button.add_theme_font_size_override("font_size", 18)

func _library_icon(library_type: String) -> Texture2D:
	match library_type:
		"movies": return preload("res://assets/icons/material/movie.svg")
		"tvshows": return preload("res://assets/icons/material/tv.svg")
		"homevideos": return preload("res://assets/icons/material/videocam.svg")
	return preload("res://assets/icons/material/video_library.svg")

func select(id: String, title: String) -> void:
	selected_id = id
	heading.text = title
	var all := buttons.duplicate()
	all[""] = home
	for key in all:
		var button: Button = all[key]
		button.add_theme_stylebox_override("normal", Widgets.surface(Color("2b4b50") if key == id else Color("182234"), 12, 16))

