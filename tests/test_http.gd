extends SceneTree

var server := TCPServer.new()
var peer: StreamPeerTCP
var incoming := ""
var payload := "{}"
var code := 200
var last_request := ""
var queued_payloads: Array[String] = []
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
	if not queued_payloads.is_empty(): payload = queued_payloads.pop_front()
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
	queued_payloads = [payload, '{"Items":[{"Id":"first","SeasonId":"season-one","UserData":{"Played":true}}]}']
	result = await api.series_playback("finished show")
	check(result.ok and result.data.Items[0].Id == "first", "Completed series fall back to their first episode")
	check(last_request.begins_with("GET /jellyfin/Shows/finished%20show/Episodes?") and "Limit=1" in last_request and "SortBy=ParentIndexNumber%2CIndexNumber" in last_request and "SortOrder=Ascending" in last_request and "IsMissing=false" in last_request, "Fallback loads the first available episode in season and episode order")
	payload = '{"Items":[],"TotalRecordCount":0}'
	await api.next_up("finished show")
	check(last_request.begins_with("GET /jellyfin/Shows/NextUp?"), "The Next Up section does not fall back to watched episodes")
	code = 500
	result = await api.series_playback("offline show")
	check(not result.ok and last_request.begins_with("GET /jellyfin/Shows/NextUp?"), "Failed Next Up requests do not restart a series")
	code = 200
	await api.library("hello & world", 24)
	check("SearchTerm=hello%20%26%20world" in last_request, "Search escaping survives HTTP")
	check('Token="fixture-token"' in last_request, "Authenticated calls send the token header")
	check("StartIndex=24" in last_request, "Library pagination is sent")
	check("Limit=25" in last_request, "Library pages request 25 titles")
	check("IncludeItemTypes=Movie%2CSeries%2CVideo%2CPhoto" in last_request, "Browsing and search include photos")
	await api.library("space", 48, "movies-id")
	check("ParentId=movies-id" in last_request and "StartIndex=48" in last_request and "SearchTerm=space" in last_request, "Search and pagination stay inside the selected library")
	await api.views()
	check(last_request.begins_with("GET /jellyfin/UserViews?") and "UserId=fixture-user" in last_request, "Sidebar loads the signed-in user's libraries")
	await api.seasons("show id")
	check(last_request.begins_with("GET /jellyfin/Shows/show%20id/Seasons?"), "Seasons load from the selected series with an escaped ID")
	payload = '{"Items":[{"Id":"part-two","Type":"Movie"}]}'
	result = await api.movie_parts({"Id": "movie id", "Type": "Movie"})
	check(result.ok and result.data.Items.size() == 2 and result.data.Items[1].Id == "part-two", "Multipart responses include the main movie followed by additional parts")
	check(last_request.begins_with("GET /jellyfin/Videos/movie%20id/AdditionalParts?") and "UserId=fixture-user" in last_request, "Multipart requests preserve the server base path and escape the movie ID")
	payload = '{"Items":[{"Id":"next","UserData":{"PlaybackPositionTicks":100}}]}'
	result = await api.next_up("show & id")
	check(result.ok and last_request.begins_with("GET /jellyfin/Shows/NextUp?") and "SeriesId=show%20%26%20id" in last_request and "UserId=fixture-user" in last_request, "Next Up is scoped to the selected series and signed-in user")
	check("DisableFirstEpisode" not in last_request and "EnableResumable=true" in last_request, "A partially watched first episode remains resumable")
	payload = '{"Items":[{"Id":"next","UserData":{"PlaybackPositionTicks":0}}]}'
	result = await api.series_playback("new show")
	check(result.ok and result.data.Items[0].Id == "next" and "SeriesId=new%20show" in last_request and "DisableFirstEpisode" not in last_request, "Series playback allows the first episode for a new show")
	await api.next_up("show id")
	check("DisableFirstEpisode=true" in last_request and "EnableRewatching=false" in last_request, "Unstarted episodes require prior series watch history")
	payload = '{"Items":[],"TotalRecordCount":0}'
	await api.episodes("show id", "season & id", 100)
	check("SeasonId=season%20%26%20id" in last_request and "StartIndex=100" in last_request, "Episode pagination stays inside the selected season")
	check("Fields=Overview%2CUserData%2CMediaSources" in last_request and "IsMissing=false" in last_request, "Episode cards request versions and summaries and exclude missing episodes")
	payload = '{"Played":true,"PlaybackPositionTicks":0}'
	code = 200
	result = await api.set_watched("movie id", true)
	check(result.ok and result.data.Played and last_request.begins_with("POST /jellyfin/Users/fixture-user/PlayedItems/movie%20id "), "Mark watched sends an authenticated POST for the selected item")
	payload = '{"Played":false,"PlaybackPositionTicks":0}'
	result = await api.set_watched("episode id", false)
	check(result.ok and not result.data.Played and last_request.begins_with("DELETE /jellyfin/Users/fixture-user/PlayedItems/episode%20id "), "Mark unwatched sends DELETE and returns updated user data")
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
	await check_playback_reports(api)
	server.stop()
	print("HTTP integration checks: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)

func check_playback_reports(api: JellyfinClient) -> void:
	var session := PlaybackSession.new()
	session.api = api
	session.item = {"Id": "fixture-item"}
	session.source = JSON.parse_string('{"Id":"fixture-source","DefaultAudioStreamIndex":1}')
	session.session_id = "fixture-session"
	root.add_child(session)
	code = 204
	payload = ""
	for event in ["Playing", "Progress", "Stopped"]:
		await session.report(event)
		var body := last_request.split("\r\n\r\n", true, 1)[1]
		check('"AudioStreamIndex":1,' in body, "%s sends the parsed server audio index as a JSON integer, not 1.0" % event)
	session.source["DefaultAudioStreamIndex"] = null
	await session.report("Playing")
	check('"AudioStreamIndex"' not in last_request, "Sources without a default audio track omit the optional index")
	session.audio_index = 3
	await session.report("Progress")
	check('"AudioStreamIndex":3,' in last_request, "Explicit audio selection is reported as an integer")
	var errors: Array[String] = []
	session.reporting_failed.connect(func(message: String): errors.append(message))
	code = 400
	await session.report("Progress")
	check(errors.size() == 1 and "HTTP 400" in errors[0], "Rejected playback reports are exposed instead of silently ignored")
	session.queue_free()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
