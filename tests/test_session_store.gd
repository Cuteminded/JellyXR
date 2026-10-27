extends SceneTree

class FixtureSettings extends JellyXRSettings:
	func save(_path: String = PATH) -> Error: return OK

class FixtureApi extends JellyfinClient:
	var response := {"ok": true, "data": {"Id": "test-user"}}
	var requests: Array[String] = []
	func request(path: String, _method: HTTPClient.Method = HTTPClient.METHOD_GET, _body: Dictionary = {}) -> Dictionary:
		requests.append(path)
		await get_tree().process_frame
		return response

class FixtureApp extends "res://scripts/main.gd":
	var library_shown := false
	var login_shown := false
	func _ready() -> void: pass
	func _show_library() -> void: library_shown = true
	func _show_login() -> void: login_shown = true
	func _stop(_show_menu: bool = true, _report: bool = true) -> void: pass

var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run_checks() -> void:
	var store := SessionStore.new()
	store.path = "res://dist/session-test.cfg"
	store.clear_session()
	check(store.load_session().is_empty(), "Missing sessions load safely.")
	var data := {"server": "https://example.com", "token": "test-token", "user_id": "test-user"}
	check(store.save_session(data) == OK, "Session can be saved.")
	var restored := SessionStore.new()
	restored.path = store.path
	check(restored.load_session() == data, "Session survives a new store instance.")
	var config := ConfigFile.new()
	config.load(store.path)
	check(not config.has_section_key("session", "password"), "No password is stored.")
	config.set_value("session", "token", 42)
	config.save(store.path)
	check(store.load_session().is_empty(), "Malformed session values are rejected.")
	store.save_session(data)
	var app := FixtureApp.new()
	app.settings = FixtureSettings.new()
	app.settings.server = data.server
	app.session_store = restored
	app.api.free()
	var api := FixtureApi.new()
	app.api = api
	app.add_child(api)
	app.add_child(app.video)
	app.add_child(app.session)
	app.status = Label.new()
	app.add_child(app.status)
	app.page = VBoxContainer.new()
	app.add_child(app.page)
	app.shell = UiShell.new()
	app.add_child(app.shell)
	root.add_child(app)
	app.set_process(false)
	await app._restore_session()
	check(app.library_shown and api.token == data.token and api.requests == ["/Users/Me"], "Startup validates and restores the saved login.")
	app.library_shown = false
	api.response = {"ok": false, "error": "Offline"}
	await app._restore_session()
	check(not app.library_shown and api.token.is_empty() and restored.load_session() == data, "Connection failures preserve the saved session for the next launch.")
	api.response = {"ok": false, "status": 401, "error": "Expired"}
	await app._restore_session()
	check(restored.load_session().is_empty() and api.token.is_empty(), "Expired sessions are removed.")
	app.settings.server = "https://other.example.com"
	store.save_session(data)
	api.requests.clear()
	await app._restore_session()
	check(api.requests.is_empty() and api.token.is_empty(), "Tokens are not restored for a different server.")
	app.settings.server = data.server
	api.server = data.server
	api.token = data.token
	api.user_id = data.user_id
	store.clear_session()
	app._signed_in()
	check(store.load_session() == data, "Successful sign-in saves the PC session.")
	await app._sign_out()
	check(store.load_session().is_empty() and api.token.is_empty() and app.login_shown, "Sign-out removes the local session and returns to login.")
	check(store.clear_session() == OK, "Clearing an absent session succeeds.")
	app.queue_free()
	await process_frame
	print("Session failures: ", failures)
	quit(1 if failures else 0)
