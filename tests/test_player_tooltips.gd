extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run_checks() -> void:
	var overlay := PlayerOverlay.new()
	root.add_child(overlay)
	overlay.show()
	await process_frame
	await process_frame
	var pointer := PointerInput.new()
	pointer.viewport = overlay.viewport
	var button := overlay.pause_button
	var point := button.get_global_rect().get_center()
	pointer.aim(point, true)
	await process_frame
	check(overlay.tooltip.text == "Pause", "Controller hover shows a tooltip inside the player viewport")
	for frame in range(10):
		pointer.aim(point + Vector2(frame % 2, 0), true)
		await process_frame
	check(overlay.tooltip.text == "Pause", "Repeated controller motion keeps the tooltip visible")
	overlay.update_time(10000, 120000, true, true)
	check(overlay.tooltip.text == "Play" and button.icon == overlay.play_icon, "Paused playback updates the icon and visible tooltip")
	pointer.cancel()
	await process_frame
	check(overlay.tooltip.text.is_empty(), "Leaving the controls clears the tooltip")
	pointer.aim(overlay.timeline.slider.get_global_rect().get_center(), true)
	await process_frame
	check(overlay.tooltip.text == "Seek to a time", "The playback timeline also shows its tooltip inside the player")
	pointer.cancel()
	var tracks: Button = button.get_parent().get_child(5)
	var actions: Array[String] = []
	overlay.action.connect(func(value: String): actions.append(value))
	pointer.sample_trigger(0.0)
	pointer.aim(tracks.get_global_rect().get_center(), true)
	await process_frame
	check(overlay.tooltip.text == "Audio and subtitles (coming soon)", "The disabled track placeholder explains its unavailable state on hover")
	pointer.sample_trigger(1.0)
	pointer.aim(tracks.get_global_rect().get_center(), true)
	pointer.sample_trigger(0.0)
	pointer.aim(tracks.get_global_rect().get_center(), true)
	await process_frame
	check(actions.is_empty(), "The track placeholder cannot trigger playback actions")
	pointer.cancel()
	button.grab_focus()
	await process_frame
	check(overlay.tooltip.text == "Play", "Keyboard focus also exposes the button's label")
	overlay.hide()
	await process_frame
	check(overlay.tooltip.text.is_empty(), "Hiding controls clears the tooltip")
	var row := button.get_parent()
	for control in row.get_children():
		if not control is Button: continue
		check(control.icon != null and "assets/icons/material/" in control.icon.resource_path, "Every player button loads a Material Symbols SVG")
	check(row.get_child(2).icon.resource_path.ends_with("replay_10.svg") and row.get_child(3).icon.resource_path.ends_with("forward_30.svg"), "Skip controls use symbols containing their durations")
	overlay.queue_free()
	await process_frame
	print("Player tooltip checks: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(1 if failures else 0)
