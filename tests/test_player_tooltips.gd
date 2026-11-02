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
	overlay.set_media({"Type": "Episode", "Name": "The long way home", "SeriesName": "Example series", "ParentIndexNumber": 1, "IndexNumber": 2})
	check(overlay.episode_label.text == "Example series - S01 E02" and overlay.title.text == "The long way home", "The player shows the series name before the season and episode numbers")
	overlay.set_media({"Type": "Episode", "Name": "Episode", "ParentIndexNumber": 1, "IndexNumber": 2})
	check(overlay.episode_label.text == "S01 E02", "Missing series names do not leave a leading separator")
	overlay.set_media({"Type": "Movie", "Name": "Movie"})
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
	check(overlay.tooltip.text.is_empty() and overlay.timeline.slider.tooltip_text.is_empty(), "Hovering the playback timeline does not show a tooltip")
	overlay.timeline.slider.grab_focus()
	await process_frame
	check(overlay.tooltip.text.is_empty(), "Focusing the playback timeline does not show a tooltip")
	pointer.cancel()
	var actions: Array[String] = []
	overlay.action.connect(func(value: String): actions.append(value))
	var compact_height := overlay.viewport.size.y
	check(overlay.bar.get_global_rect().end.y - overlay.controls_row.get_global_rect().end.y <= 31, "The player bar ends with only its normal padding below the buttons")
	var bar_position := overlay.bar.get_global_rect().position
	var tracks: Button = overlay.submenu_buttons["subtitles"]
	pointer.sample_trigger(0.0)
	pointer.aim(tracks.get_global_rect().get_center(), true)
	await process_frame
	pointer.sample_trigger(1.0)
	pointer.aim(tracks.get_global_rect().get_center(), true)
	pointer.sample_trigger(0.0)
	pointer.aim(tracks.get_global_rect().get_center(), true)
	await process_frame
	await process_frame
	check(actions.is_empty() and overlay.quick_access.tracks_menu.visible and overlay.quick_access.visible, "The player subtitle button opens its submenu directly")
	check(overlay.bar.get_global_rect().position.y - bar_position.y == 840 - compact_height, "Opening a submenu preserves the bar's position within the expanded viewport")
	check(overlay.quick_access.get_global_rect().end.y < tracks.get_global_rect().position.y, "The submenu stays above the player buttons")
	pointer.cancel()
	button.grab_focus()
	await process_frame
	check(overlay.tooltip.text == "Play", "Keyboard focus also exposes the button's label")
	var session := PlaybackSession.new()
	var video := VideoBackend.new()
	session.source = {"Bitrate": 25000000, "MediaStreams": [{"Type": "Video", "Width": 3840, "Height": 2160, "AverageFrameRate": 23.976, "Codec": "hevc"}]}
	overlay.statistics_provider = func(): return preload("res://scripts/ui/playback_statistics.gd").snapshot(session, video)
	overlay.set_statistics_visible(true)
	await process_frame
	await process_frame
	check(overlay.statistics_panel.visible and overlay.submenu_buttons["statistics"].button_pressed, "The statistics button opens and marks the panel active")
	check(overlay.statistics_values["Source video"].text == "3840 x 2160 / 23.976 fps", "Statistics show source resolution and frame rate")
	var renderer_fps: String = overlay.statistics_values["Renderer / FPS"].text
	check(renderer_fps != "N/A" and renderer_fps.contains(" / ") and renderer_fps.get_slice(" / ", 1).is_valid_int(), "Statistics display the rendering driver and app FPS")
	check(overlay.statistics_values["Dropped frames"].text == "N/A", "Missing decoder counters are not presented as zero")
	var statistics := preload("res://scripts/ui/playback_statistics.gd")
	check(statistics._hardware_decoder({"d3d11_gpu_copy": true}) == "D3D11VA", "Statistics identify Windows GPU frames")
	check(statistics._hardware_decoder({"d3d12_gpu_copy": true}) == "D3D12VA", "Statistics identify D3D12 GPU frames")
	check(statistics._hardware_decoder({"hardware_device": "d3d11va"}) == "d3d11va", "CPU-transfer fallback is not shown as GPU frames")
	video.paused = true
	overlay._process(1.0)
	check(overlay.statistics_values["Player state"].text == "Paused", "Open statistics refresh playback state")
	check(overlay.submenu_buttons["statistics"].get_global_rect().end.x <= overlay.viewport.size.x, "The rightmost button fits inside the player bar")
	check(overlay.statistics_panel.get_global_rect().end.y <= overlay.viewport.size.y, "The statistics panel fits inside the player viewport")
	overlay.submenu_buttons["screen_mode"].pressed.emit()
	await process_frame
	await process_frame
	check(overlay.quick_access.screen_mode.visible and not overlay.statistics_panel.visible and not overlay.quick_access.tracks_menu.visible, "Switching player buttons shows only the selected submenu")
	check(overlay.submenu_buttons["screen_mode"].button_pressed and not overlay.submenu_buttons["statistics"].button_pressed, "Only the active submenu button is selected")
	overlay.submenu_buttons["screen_mode"].pressed.emit()
	check(not overlay.quick_access.visible and overlay.viewport.size.y == compact_height, "Pressing the active button closes its submenu")
	overlay.show_menu("subtitles")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	overlay.quick_access._unhandled_key_input(cancel)
	check(not overlay.quick_access.visible and overlay.submenu_buttons["subtitles"].has_focus(), "Closing a submenu returns focus to its player button")
	for name in ["subtitles", "audio", "screen_mode", "statistics", "audio", "subtitles"]:
		overlay.submenu_buttons[name].pressed.emit()
		await process_frame
		await process_frame
		var visible_panels := int(overlay.quick_access.tracks_menu.visible) + int(overlay.quick_access.screen_mode.visible) + int(overlay.statistics_panel.visible)
		check(overlay.quick_access.visible and visible_panels == 1 and overlay.active_menu == name, "Switching between player buttons keeps exactly one panel open")
		check(overlay.quick_access.volume_control.visible == (name == "audio"), "Volume is shown only in the combined audio menu")
		check(is_equal_approx(overlay.quick_access.size.y, overlay.quick_access.get_combined_minimum_size().y), "Each panel fits its content without unused space below it")
		overlay._show_tooltip(overlay.submenu_buttons[name])
		await process_frame
		await process_frame
		check(overlay.tooltip.get_global_rect().position.y >= overlay.quick_access.get_global_rect().end.y + 8, "The player tooltip fits below the open submenu without overlap")
		overlay._hide_tooltip(overlay.submenu_buttons[name])
		var selected_buttons := 0
		for control in overlay.submenu_buttons.values(): selected_buttons += int(control.button_pressed)
		check(selected_buttons == 1, "Only one player submenu button remains selected")
	overlay.set_statistics_visible(true)
	overlay.hide()
	await process_frame
	check(overlay.tooltip.text.is_empty(), "Hiding controls clears the tooltip")
	check(not overlay.statistics_panel.visible, "Hiding playback controls also dismisses statistics")
	video.free()
	session.free()
	var row := button.get_parent()
	for control in row.get_children():
		if not control is Button: continue
		check(control.icon != null and "assets/icons/material/" in control.icon.resource_path, "Every player button loads a Material Symbols SVG")
	check(row.get_child(2).icon.resource_path.ends_with("replay_10.svg") and row.get_child(3).icon.resource_path.ends_with("forward_30.svg"), "Skip controls use symbols containing their durations")
	overlay.queue_free()
	await process_frame
	print("Player tooltip checks: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(1 if failures else 0)
