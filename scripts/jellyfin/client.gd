class_name JellyfinClient
extends Node

var server := ""
var token := ""
var user_id := ""
var device_id := ""
var library_sort_by := "SortName"
var library_sort_order := "Ascending"
var random_library_ids: Dictionary = {}
var random_library_generation: Dictionary = {}

func authorization() -> String:
	var name := headset_name().replace("\\", "\\\\").replace('"', '\\"').replace("\r", " ").replace("\n", " ")
	var value := 'MediaBrowser Client="jellyXR", Device="%s", DeviceId="%s", Version="0.2.0"' % [name, device_id]
	if not token.is_empty():
		value += ', Token="%s"' % token
	return value

func headset_name() -> String:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized():
		var name := str(xr.get_system_info().get("OpenXRSystemName", "")).strip_edges()
		if not name.is_empty():
			return name
	return "OpenXR"

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
	var values := {"UserId": user_id, "Recursive": "true", "IncludeItemTypes": "Movie,Series,Video,Photo", "Fields": "Overview,UserData", "Limit": 25, "StartIndex": offset, "SortBy": library_sort_by, "SortOrder": library_sort_order}
	if search.is_empty() and parent_id.is_empty():
		values["SortBy"] = "DateCreated"
		values["SortOrder"] = "Descending"
	if not search.is_empty(): values["SearchTerm"] = search
	if not parent_id.is_empty(): values["ParentId"] = parent_id
	if values["SortBy"] == "Random":
		return await _random_library(values, offset)
	return await request("/Items" + query(values))

func _random_library(values: Dictionary, offset: int) -> Dictionary:
	var key := JSON.stringify([server, user_id, values.get("ParentId", ""), values.get("SearchTerm", "")])
	var ids: Array = random_library_ids.get(key, [])
	if offset == 0 or not random_library_ids.has(key):
		var generation := int(random_library_generation.get(key, 0)) + 1
		random_library_generation[key] = generation
		var catalog := values.duplicate()
		for field in ["Limit", "StartIndex", "Fields"]: catalog.erase(field)
		catalog["EnableImages"] = "false"
		catalog["EnableUserData"] = "false"
		var snapshot := await request("/Items" + query(catalog))
		if not snapshot.ok: return snapshot
		ids = snapshot.data.get("Items", []).map(func(item: Dictionary): return str(item.Id))
		if int(random_library_generation.get(key, 0)) == generation:
			random_library_ids[key] = ids
	var page_ids := ids.slice(offset, offset + 25)
	if page_ids.is_empty():
		return {"ok": true, "data": {"Items": [], "TotalRecordCount": ids.size()}}
	var page_values := values.duplicate()
	for field in ["SortBy", "SortOrder", "StartIndex"]: page_values.erase(field)
	page_values["Ids"] = ",".join(page_ids)
	var result := await request("/Items" + query(page_values))
	if not result.ok: return result
	var by_id := {}
	for item in result.data.get("Items", []): by_id[str(item.Id)] = item
	var items := []
	for id in page_ids:
		if by_id.has(id): items.append(by_id[id])
	return {"ok": true, "data": {"Items": items, "TotalRecordCount": ids.size()}}

func views() -> Dictionary:
	return await request("/UserViews" + query({"UserId": user_id, "IncludeHidden": "false"}))

func resume_items() -> Dictionary:
	return await request("/Users/%s/Items/Resume" % user_id + query({"Limit": 12, "MediaTypes": "Video", "Fields": "Overview,UserData"}))

func details(id: String) -> Dictionary:
	return await request("/Users/%s/Items/%s" % [user_id, id.uri_encode()])

func movie_parts(item: Dictionary) -> Dictionary:
	var id := str(item.get("SelectedMediaSourceId", ""))
	var sources: Array = item.get("MediaSources", []) if item.get("MediaSources") else []
	if id.is_empty() and not sources.is_empty(): id = str(sources[0].get("Id", ""))
	if id.is_empty(): id = str(item.Id)
	var result := await request("/Videos/%s/AdditionalParts" % id.uri_encode() + query({"UserId": user_id}))
	if not result.ok: return result
	var parts: Array = [item.duplicate(true)]
	var seen := {str(item.Id): true, id: true}
	for part in result.data.get("Items", []):
		var part_id := str(part.get("Id", ""))
		if part_id.is_empty() or seen.has(part_id): continue
		seen[part_id] = true
		parts.append(part.duplicate(true))
	return {"ok": true, "data": {"Items": parts}}

func set_watched(id: String, watched: bool) -> Dictionary:
	return await request("/Users/%s/PlayedItems/%s" % [user_id.uri_encode(), id.uri_encode()], HTTPClient.METHOD_POST if watched else HTTPClient.METHOD_DELETE)

func seasons(series_id: String) -> Dictionary:
	return await request("/Shows/%s/Seasons" % series_id.uri_encode() + query({"UserId": user_id, "Fields": "Overview,UserData", "EnableUserData": "true"}))

func series_playback(series_id: String) -> Dictionary:
	var result := await request("/Shows/NextUp" + query(_next_up_parameters(series_id)))
	if not result.ok or not result.data.get("Items", []).is_empty(): return result
	return await request("/Shows/%s/Episodes" % series_id.uri_encode() + query({"UserId": user_id, "StartIndex": 0, "Limit": 1, "SortBy": "ParentIndexNumber,IndexNumber", "SortOrder": "Ascending", "Fields": "Overview,UserData,MediaSources", "EnableUserData": "true", "IsMissing": "false"}))

func _next_up_parameters(series_id: String) -> Dictionary:
	return {"UserId": user_id, "SeriesId": series_id, "Limit": 1, "Fields": "Overview,UserData,MediaSources", "EnableUserData": "true", "EnableResumable": "true", "EnableRewatching": "false"}

func next_up(series_id: String) -> Dictionary:
	var parameters := _next_up_parameters(series_id)
	var result := await request("/Shows/NextUp" + query(parameters))
	if not result.ok: return result
	var items: Array = result.data.get("Items", [])
	if items.is_empty(): return result
	var user: Dictionary = items[0].get("UserData", {}) if items[0].get("UserData") else {}
	if int(user.get("PlaybackPositionTicks", 0)) > 0: return result
	parameters["DisableFirstEpisode"] = "true"
	return await request("/Shows/NextUp" + query(parameters))

func episodes(series_id: String, season_id: String, offset: int = 0) -> Dictionary:
	return await request("/Shows/%s/Episodes" % series_id.uri_encode() + query({"UserId": user_id, "SeasonId": season_id, "StartIndex": offset, "Limit": 100, "Fields": "Overview,UserData,MediaSources", "EnableUserData": "true", "IsMissing": "false"}))

func next_episode(item: Dictionary) -> Dictionary:
	var series_id := str(item.get("SeriesId", ""))
	if series_id.is_empty():
		var detail := await details(str(item.Id))
		if not detail.ok: return detail
		series_id = str(detail.data.get("SeriesId", ""))
	if series_id.is_empty():
		return {"ok": false, "error": "This episode has no series information."}
	var result := await request("/Shows/%s/Episodes" % series_id.uri_encode() + query({"UserId": user_id, "StartItemId": item.Id, "Limit": 2, "Fields": "Overview,UserData", "EnableUserData": "true", "IsMissing": "false"}))
	if not result.ok: return result
	var items: Array = result.data.get("Items", [])
	if items.size() < 2 or str(items[0].get("Id", "")) != str(item.Id):
		return {"ok": true, "data": {}}
	var next: Dictionary = items[1].duplicate(true)
	next["Type"] = "Episode"
	next["SeriesId"] = series_id
	return {"ok": true, "data": next}

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
