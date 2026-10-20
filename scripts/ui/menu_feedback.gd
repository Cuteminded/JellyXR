class_name MenuFeedback
extends Node

var player := AudioStreamPlayer.new()

func _ready() -> void:
	player.stream = _click_sound()
	player.volume_db = -16.0
	player.max_polyphony = 4
	add_child(player)
	get_tree().node_added.connect(_connect_button)
	_connect_existing(get_tree().root)

func _connect_existing(node: Node) -> void:
	_connect_button(node)
	for child in node.get_children(): _connect_existing(child)

func _connect_button(node: Node) -> void:
	if not node is BaseButton: return
	var button := node as BaseButton
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	if not button.pressed.is_connected(_play): button.pressed.connect(_play)

func _play() -> void:
	player.play()

func _click_sound() -> AudioStreamWAV:
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 48000
	var samples := 1440
	var data := PackedByteArray()
	data.resize(samples * 2)
	for index in range(samples):
		var time := float(index) / sound.mix_rate
		var envelope := minf(time / 0.0015, 1.0) * exp(-time * 180.0) * (1.0 - float(index) / samples)
		var sample := (sin(TAU * 1250.0 * time) + 0.3 * sin(TAU * 2300.0 * time)) * envelope * 0.65
		data.encode_s16(index * 2, int(sample * 32767.0))
	sound.data = data
	return sound
