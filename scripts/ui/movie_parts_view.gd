class_name MoviePartsView
extends VBoxContainer

signal play_requested(item: Dictionary)

var api: JellyfinClient
var item: Dictionary
var choices: VBoxContainer
var loading := false

func _ready() -> void:
	add_theme_constant_override("separation", 14)
	Widgets.label("Movie parts", self, 28)
	choices = VBoxContainer.new()
	choices.add_theme_constant_override("separation", 12)
	add_child(choices)
	load_parts()

func load_parts() -> void:
	if loading: return
	loading = true
	_clear_choices()
	Widgets.label("Loading movie parts...", choices, 22)
	var result := await api.movie_parts(item)
	if not is_inside_tree(): return
	loading = false
	_clear_choices()
	if not result.ok:
		Widgets.label("Could not load movie parts. Try again.", choices, 22)
		Widgets.button("Retry", load_parts, choices)
		return
	var parts: Array = result.data.Items
	if parts.size() < 2:
		hide()
		return
	for index in range(parts.size()):
		var selected := MovieParts.select(parts, index, str(item.Id))
		var duration := int(parts[index].get("RunTimeTicks", 0))
		var user: Dictionary = parts[index].get("UserData", {}) if parts[index].get("UserData") else {}
		var action := "Resume" if int(user.get("PlaybackPositionTicks", 0)) > 0 else "Play"
		var text := "%s part %d" % [action, index + 1]
		if duration > 0:
			text += " / " + ("%d sec" % int(duration / 10000000) if duration < 600000000 else DetailsMetadata.duration(duration))
		var button := Widgets.button(text, func(): play_requested.emit(selected), choices)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.y = 64

func _clear_choices() -> void:
	for child in choices.get_children():
		choices.remove_child(child)
		child.queue_free()
