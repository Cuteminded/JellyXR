extends VBoxContainer

signal play_requested(item: Dictionary)
signal version_requested(item: Dictionary)

const EXTRA_LABELS := {
	"BehindTheScenes": "Behind the scenes", "DeletedScene": "Deleted scene",
	"Interview": "Interview", "Scene": "Scene", "Sample": "Sample",
	"Clip": "Clip", "Short": "Short", "Featurette": "Featurette", "Trailer": "Trailer"
}

var api: JellyfinClient
var artwork: ArtworkLoader
var item_id := ""
var return_item: Dictionary = {}
var return_season: Dictionary = {}
var choices: VBoxContainer
var loading := false

func _ready() -> void:
	add_theme_constant_override("separation", 18)
	Widgets.label("Extras", self, 28)
	choices = VBoxContainer.new()
	choices.add_theme_constant_override("separation", 16)
	add_child(choices)
	load_extras()

func load_extras() -> void:
	if loading: return
	loading = true
	show()
	_clear_choices()
	Widgets.label("Loading extras...", choices, 22)
	var result := await api.extras(item_id)
	if not is_inside_tree(): return
	loading = false
	_clear_choices()
	var items: Array = result.get("data", {}).get("Items", [])
	for extra in items:
		var card := EpisodeCard.new()
		card.item = extra.duplicate(true)
		card.item["ExtraReturnItem"] = return_item.duplicate(true)
		card.item["ExtraReturnSeason"] = return_season.duplicate(true)
		card.media_label = "extra"
		card.category = EXTRA_LABELS.get(str(extra.get("ExtraType", "")), "Extra")
		card.api = api
		card.artwork = artwork
		card.chosen.connect(func(selected: Dictionary): play_requested.emit(selected))
		card.version_requested.connect(func(selected: Dictionary): version_requested.emit(selected))
		choices.add_child(card)
	if not result.ok:
		Widgets.label("Some extras could not be loaded. Try again.", choices, 22)
		Widgets.button("Retry extras", load_extras, choices)
	elif items.is_empty():
		hide()

func _clear_choices() -> void:
	for child in choices.get_children():
		choices.remove_child(child)
		child.queue_free()
