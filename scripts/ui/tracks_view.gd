class_name TracksView
extends VBoxContainer

signal audio_selected(index: int)
signal subtitle_selected(index: int)
signal appearance_changed
signal closed
var session: PlaybackSession
var subtitles: SubtitleTrack
var settings: JellyXRSettings
var message: Label
var back_button: Button

func _ready() -> void:
	back_button = Widgets.button("Back to video", func(): closed.emit(), self)
	_focus_back.call_deferred()
	message = Widgets.label(subtitles.message, self, 20)
	if not subtitles.changed.is_connected(_subtitle_status): subtitles.changed.connect(_subtitle_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	Widgets.label("Audio", body, 28)
	if session.active_playback_mode == "original":
		Widgets.label("Audio switching and picture subtitles require server conversion.", body, 20)
		Widgets.button("Use Automatic for this video", func(): session.active_playback_mode = "auto"; _refresh(), body)
	_tracks(body, "Audio")
	Widgets.label("Subtitles", body, 28)
	var off := Widgets.button("Off", func(): subtitle_selected.emit(-1); _refresh(), body)
	off.toggle_mode = true
	off.button_pressed = subtitles.index < 0
	_tracks(body, "Subtitle")
	Widgets.label("Text subtitle appearance", body, 28)
	_adjustment(body, "Text size", func(): return str(settings.subtitle_size), func(step: int): settings.subtitle_size = clampi(settings.subtitle_size + step * 4, 28, 80))
	_adjustment(body, "Vertical position", func(): return "%d%%" % roundi(settings.subtitle_height * 100), func(step: int): settings.subtitle_height = clampf(settings.subtitle_height + step * 0.05, 0.1, 0.8))
	var colors := HBoxContainer.new()
	body.add_child(colors)
	for color in ["White", "Yellow", "Green"]:
		var button := Widgets.button(color, func(): settings.subtitle_color = color; _save(); _refresh(), colors)
		button.toggle_mode = true
		button.button_pressed = settings.subtitle_color == color
	_adjustment(body, "Delay", func(): return "%+.1f s" % (subtitles.delay_ms / 1000.0), func(step: int): subtitles.delay_ms = clampi(subtitles.delay_ms + step * 100, -10000, 10000))
	Widgets.label("Positive delay shows subtitles later. Timing resets for each video.", body, 20)
	Widgets.button("Reset timing", func(): subtitles.delay_ms = 0; _refresh(), body)

func _tracks(parent: Control, kind: String) -> void:
	var count := 0
	for stream in session.source.get("MediaStreams", []):
		if stream.get("Type", "") != kind: continue
		count += 1
		var index := int(stream.Index)
		var label := str(stream.get("DisplayTitle", stream.get("Language", "Track %d" % index)))
		var supported := kind == "Audio" or SubtitleTrack.supported(stream)
		if not supported: label += " (requires video conversion)"
		var button := Widgets.button(label, func():
			if kind == "Audio": audio_selected.emit(index)
			else: subtitle_selected.emit(index); _refresh(), parent)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		var selected := session.audio_index
		if selected < 0 and session.source.get("DefaultAudioStreamIndex") != null:
			selected = int(session.source.DefaultAudioStreamIndex)
		button.button_pressed = index == (selected if kind == "Audio" else subtitles.index)
		if button.button_pressed: button.text += " (selected)"
		button.disabled = session.active_playback_mode == "original" and (kind == "Audio" or not supported)
	if count == 0: Widgets.label("No %s tracks available." % kind.to_lower(), parent, 20)

func _adjustment(parent: Control, title: String, value: Callable, change: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Widgets.label(title + ": " + value.call(), row, 22)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for step in [-1, 1]:
		var button := Widgets.button("-" if step < 0 else "+", func():
			change.call(step)
			label.text = title + ": " + value.call()
			_save(), row)
		button.accessibility_name = ("Decrease " if step < 0 else "Increase ") + title.to_lower()

func _save() -> void:
	settings.save()
	appearance_changed.emit()

func _refresh() -> void:
	var scroll_position := 0
	for child in get_children():
		if child is ScrollContainer: scroll_position = child.scroll_vertical
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_ready()
	for child in get_children():
		if child is ScrollContainer: child.set_deferred("scroll_vertical", scroll_position)

func _subtitle_status() -> void:
	message.text = subtitles.message

func _focus_back() -> void:
	if is_inside_tree() and is_instance_valid(back_button): back_button.grab_focus()
