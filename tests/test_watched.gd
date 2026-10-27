extends SceneTree

class FixtureApi extends JellyfinClient:
	var calls: Array = []
	var fail := false
	var malformed := false

	func set_watched(id: String, watched: bool) -> Dictionary:
		calls.append([id, watched])
		await get_tree().process_frame
		if fail: return {"ok": false, "error": "Cannot reach the server."}
		return {"ok": true, "data": {} if malformed else {"Played": watched, "PlaybackPositionTicks": 0, "PlayCount": 1 if watched else 0}}

var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func settle() -> void:
	for frame in range(5): await process_frame

func run_checks() -> void:
	var api := FixtureApi.new()
	root.add_child(api)
	var view := DetailsView.new()
	view.api = api
	view.item = {"Id": "movie", "Type": "Movie", "Name": "Example", "UserData": {"Played": false, "PlaybackPositionTicks": 7200000000, "IsFavorite": true}}
	root.add_child(view)
	await settle()
	var control = view.watched_control
	check(control.button.text == "Mark as watched", "Unwatched movies offer Mark as watched")
	control.button.pressed.emit()
	control.button.pressed.emit()
	check(control.button.disabled and api.calls.size() == 1, "Saving prevents duplicate requests")
	check(not view.item.UserData.Played, "Watched status waits for server confirmation")
	await settle()
	check(view.item.UserData.Played and view.item.UserData.IsFavorite, "Confirmed user data preserves unrelated fields")
	check(control.button.text == "Mark as unwatched" and view.play_button.text == "Play movie", "Movie buttons reflect the confirmed watched state and cleared resume position")
	check(not view.resume_label.visible and not view.play_from_start_button.visible, "Cleared progress hides stale resume controls")
	control.button.pressed.emit()
	await settle()
	check(not view.item.UserData.Played and api.calls.back() == ["movie", false], "Movies can be marked unwatched again")
	api.fail = true
	control.button.pressed.emit()
	await settle()
	check(not view.item.UserData.Played and not control.button.disabled and control.status.visible, "Failed requests preserve state and allow retry")
	api.fail = false
	api.malformed = true
	control.button.pressed.emit()
	await settle()
	check(not view.item.UserData.Played and control.status.visible, "Incomplete responses do not claim a saved change")
	api.malformed = false
	var episode := EpisodeCard.new()
	episode.api = api
	episode.artwork = view.artwork
	episode.item = {"Id": "episode", "Type": "Episode", "Name": "Episode", "UserData": {"Played": true, "PlaybackPositionTicks": 7200000000}}
	root.add_child(episode)
	await settle()
	check(episode.watched_badge.visible, "Watched episodes show a badge")
	episode.watched_control.button.pressed.emit()
	await settle()
	check(not episode.watched_badge.visible and episode.play_button.text == "Play episode", "Marking an episode unwatched updates its badge and playback action")
	check(not "Continue from" in episode.facts_label.text and not "watched" in episode.play_button.accessibility_name, "Episode progress and accessibility labels are refreshed")
	episode.watched_control.button.pressed.emit()
	await settle()
	check(episode.watched_badge.visible and api.calls.back() == ["episode", true], "Episodes can be marked watched again")
	view.queue_free()
	episode.queue_free()
	api.queue_free()
	await process_frame
	print("Watched status checks: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(1 if failures else 0)
