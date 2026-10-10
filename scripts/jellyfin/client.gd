class_name JellyfinClient
extends Node

var server := ""
var token := ""
var user_id := ""
var device_id := ""

func authorization() -> String:
	var value := 'MediaBrowser Client="Jellyframe", Device="Standalone VR", DeviceId="%s", Version="0.1.0"' % device_id
	if not token.is_empty():
		value += ', Token="%s"' % token
	return value

func configure(address: String) -> bool:
	var clean := address.strip_edges().trim_suffix("/")
	if not (clean.begins_with("https://") or clean.begins_with("http://")):
		return false
	if "@" in clean or "?" in clean or "#" in clean or clean.contains("\n"):
		return false
	var authority := clean.split("://", true, 1)[1].split("/", true, 1)[0]
	if authority.is_empty() or " " in clean or "\r" in clean or "\t" in clean:
		return false
	server = clean
	return true

func request(path: String, method: HTTPClient.Method = HTTPClient.METHOD_GET, body: Dictionary = {}) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	var headers := PackedStringArray(["Authorization: " + authorization(), "Content-Type: application/json"])
	var error := http.request(server + path, headers, method, JSON.stringify(body) if method != HTTPClient.METHOD_GET else "")
	if error != OK:
		http.queue_free()
		return {"ok": false, "error": "Could not start the request."}
	var response: Array = await http.request_completed
	http.queue_free()
	var code := int(response[1])
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "Cannot reach the server. Check the address and connection."}
	if code < 200 or code >= 300:
		var message := "Server returned HTTP %d." % code
		if code == 401: message = "Your session has expired, or your username or password is incorrect."
		if code == 403: message = "This account does not have permission for this action."
		return {"ok": false, "error": message, "status": code}
	var raw: String = response[3].get_string_from_utf8()
	if raw.is_empty(): return {"ok": true, "data": {}}
	var parser := JSON.new()
	if parser.parse(raw) != OK:
		return {"ok": false, "error": "The server returned an unexpected response. Check your Jellyfin server address."}
	var data: Variant = parser.data
	return {"ok": true, "data": data if data != null else {}}

func login(username: String, password: String) -> Dictionary:
	var result := await request("/Users/AuthenticateByName", HTTPClient.METHOD_POST, {"Username": username, "Pw": password})
	return accept_login(result)

func accept_login(result: Dictionary) -> Dictionary:
	if result.ok:
		var data: Dictionary = result.data
		token = data.get("AccessToken", "")
		user_id = data.get("User", {}).get("Id", "")
		if token.is_empty() or user_id.is_empty():
			return {"ok": false, "error": "The server returned an incomplete sign-in response."}
	return result

func query(values: Dictionary) -> String:
	var pairs := PackedStringArray()
	for key in values:
		pairs.append(str(key).uri_encode() + "=" + str(values[key]).uri_encode())
	return "?" + "&".join(pairs)

func library(search: String = "", offset: int = 0, parent_id: String = "") -> Dictionary:
	var values := {"UserId": user_id, "Recursive": "true", "IncludeItemTypes": "Movie,Series,Video", "Fields": "Overview,UserData", "Limit": 24, "StartIndex": offset, "SortBy": "SortName", "SortOrder": "Ascending"}
	if not search.is_empty(): values["SearchTerm"] = search
	if not parent_id.is_empty(): values["ParentId"] = parent_id
	return await request("/Items" + query(values))

func views() -> Dictionary:
	return await request("/UserViews" + query({"UserId": user_id, "IncludeHidden": "false"}))

func resume_items() -> Dictionary:
	return await request("/Users/%s/Items/Resume" % user_id + query({"Limit": 12, "MediaTypes": "Video", "Fields": "Overview,UserData"}))

func details(id: String) -> Dictionary:
	return await request("/Users/%s/Items/%s" % [user_id, id.uri_encode()])

func image_url(item: Dictionary, backdrop: bool = false) -> String:
	var kind := "Backdrop/0" if backdrop else "Primary"
	var tags: Array = item.get("BackdropImageTags", []) if item.get("BackdropImageTags") else []
	var primary: Dictionary = item.get("ImageTags", {}) if item.get("ImageTags") else {}
	var tag: String = str(tags[0]) if backdrop and not tags.is_empty() else str(primary.get("Primary", ""))
	return server + "/Items/%s/Images/%s" % [str(item.Id).uri_encode(), kind] + query({"maxWidth": 1280 if backdrop else 360, "quality": 85, "tag": tag})

func stream_url(path: String) -> String:
	if path.is_empty() or path.begins_with("//") or "://" in path or "\\" in path or ".." in path.split("?")[0]:
		return ""
	return server + "/" + path.trim_prefix("/")
