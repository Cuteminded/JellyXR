extends SceneTree

var server := TCPServer.new()
var peer: StreamPeerTCP
var incoming := ""
var payload := "{}"
var code := 200
var last_request := ""
var failures := 0

func _initialize() -> void:
	if server.listen(18963, "127.0.0.1") != OK:
		push_error("Test port 18963 is unavailable.")
		quit(1)
		return
	call_deferred("run_checks")

func _process(_delta: float) -> bool:
	if server.is_connection_available():
		peer = server.take_connection()
		incoming = ""
	if peer == null: return false
	peer.poll()
	if peer.get_available_bytes() > 0:
		incoming += peer.get_utf8_string(peer.get_available_bytes())
	var end := incoming.find("\r\n\r\n")
	if end < 0: return false
	var content_length := 0
	for line in incoming.substr(0, end).split("\r\n"):
		if line.to_lower().begins_with("content-length:"):
			content_length = int(line.split(":")[1].strip_edges())
	if incoming.substr(end + 4).to_utf8_buffer().size() < content_length: return false
	last_request = incoming
	var response := "HTTP/1.1 %d Test\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [code, payload.to_utf8_buffer().size(), payload]
	peer.put_data(response.to_utf8_buffer())
	peer.disconnect_from_host()
	peer = null
	return false

func run_checks() -> void:
	var api := JellyfinClient.new()
	root.add_child(api)
	api.configure("http://127.0.0.1:18963/jellyfin")
	api.device_id = "test-device"
	payload = JSON.stringify({"AccessToken": "fixture-token", "User": {"Id": "fixture-user"}})
	var result := await api.login("a\"b", "test-only-password")
	check(result.ok and api.user_id == "fixture-user", "Login consumes the user and token")
	check(last_request.begins_with("POST /jellyfin/Users/AuthenticateByName "), "Login preserves the server base path")
	var body: Dictionary = JSON.parse_string(last_request.split("\r\n\r\n", true, 1)[1])
	check(body.Username == 'a"b' and body.Pw == "test-only-password", "Credentials are JSON encoded")
	payload = '{"Items":[],"TotalRecordCount":0}'
	await api.library("hello & world", 24)
	check("SearchTerm=hello%20%26%20world" in last_request, "Search escaping survives HTTP")
	check('Token="fixture-token"' in last_request, "Authenticated calls send the token header")
	check("StartIndex=24" in last_request, "Library pagination is sent")
	check("Limit=25" in last_request, "Library pages request 25 titles")
	await api.library("space", 48, "movies-id")
	check("ParentId=movies-id" in last_request and "StartIndex=48" in last_request and "SearchTerm=space" in last_request, "Search and pagination stay inside the selected library")
	await api.views()
	check(last_request.begins_with("GET /jellyfin/UserViews?") and "UserId=fixture-user" in last_request, "Sidebar loads the signed-in user's libraries")
	await api.seasons("show id")
	check(last_request.begins_with("GET /jellyfin/Shows/show%20id/Seasons?"), "Seasons load from the selected series with an escaped ID")
	await api.episodes("show id", "season & id", 100)
	check("SeasonId=season%20%26%20id" in last_request and "StartIndex=100" in last_request, "Episode pagination stays inside the selected season")
	check("Fields=Overview%2CUserData" in last_request and "IsMissing=false" in last_request, "Episode cards request summaries and exclude missing episodes")
	code = 401
	payload = ""
	result = await api.request("/Users/Me")
	check(not result.ok and result.status == 401, "Unauthorised responses are actionable")
	code = 204
	result = await api.request("/Sessions/Playing/Stopped", HTTPClient.METHOD_POST)
	check(result.ok, "Empty success responses are accepted")
	code = 200
	payload = "<html>Wrong proxy route</html>"
	result = await api.request("/Users/Me")
	check(not result.ok, "Non-JSON proxy responses are rejected")
	server.stop()
	print("HTTP integration checks: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
