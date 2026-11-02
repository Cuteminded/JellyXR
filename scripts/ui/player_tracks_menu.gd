class_name PlayerTracksMenu
extends ScrollContainer

signal audio_selected(index: int)
signal subtitle_selected(index: int)

var state_provider: Callable
var kind := "Subtitle"
var body: VBoxContainer
var buttons: Dictionary = {}
var automatic_button: Button

func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	follow_focus = true
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	add_child(body)

func refresh() -> void:
	var scroll_position := scroll_vertical
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	buttons.clear()
	automatic_button = null
	if not state_provider.is_valid(): return
	var state: Dictionary = state_provider.call()
	var session: PlaybackSession = state.session
	var subtitles: SubtitleTrack = state.subtitles
	var busy: bool = state.get("busy", false)
	var original := session.active_playback_mode == "original"
	var group := ButtonGroup.new()
	var selected := subtitles.index if kind == "Subtitle" else session.audio_index
	if kind == "Audio" and selected < 0:
		selected = int(session.source.get("DefaultAudioStreamIndex", -1))
	if original:
		_hint("Select Automatic to change audio tracks or use picture subtitles.")
		automatic_button = _button("Use Automatic for this video", func():
			session.active_playback_mode = "auto"
			refresh())
		automatic_button.disabled = busy
	if kind == "Subtitle": _track_button("Off", -1, selected, group, busy)
	var count := 0
	for stream in session.source.get("MediaStreams", []):
		if stream.get("Type", "") != kind: continue
		count += 1
		var index := int(stream.get("Index", -1))
		var label := str(stream.get("DisplayTitle", stream.get("Language", "Track %d" % index)))
		var supported := kind == "Audio" or SubtitleTrack.supported(stream)
		if not supported: label += "\nJellyfin converts the video."
		_track_button(label, index, selected, group, busy or (original and (kind == "Audio" or not supported)))
	if count == 0: _hint("No %s tracks." % kind.to_lower())
	custom_minimum_size.y = minf(420, body.get_combined_minimum_size().y)
	set_deferred("scroll_vertical", scroll_position)

func _track_button(label: String, index: int, selected: int, group: ButtonGroup, disabled: bool) -> void:
	var button := _button(label, func():
		if kind == "Audio": audio_selected.emit(index)
		else: subtitle_selected.emit(index))
	button.toggle_mode = true
	button.button_group = group
	button.set_pressed_no_signal(index == selected or (index == -1 and selected < 0))
	button.disabled = disabled
	PlayerQuickAccess.style_button(button)
	buttons[index] = button

func _button(label: String, callback: Callable) -> Button:
	var button := Widgets.button(label, callback, body)
	button.custom_minimum_size = Vector2(0, 60)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.accessibility_name = label
	button.add_theme_font_size_override("font_size", 20)
	PlayerQuickAccess.style_button(button)
	return button

func _hint(text: String) -> Label:
	var label := Widgets.label(text, body, 17)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("a4aec0"))
	return label

func update_subtitle_status() -> void:
	if not is_visible_in_tree() or kind != "Subtitle" or not state_provider.is_valid(): return
	var state: Dictionary = state_provider.call()
	var subtitles: SubtitleTrack = state.subtitles
	for index in buttons: buttons[index].set_pressed_no_signal(index == subtitles.index)
