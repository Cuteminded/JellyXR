class_name PhotoView
extends Node

signal photo_ready(texture: Texture2D)
signal failed(message: String)
var api: JellyfinClient
var item: Dictionary
var request: HTTPRequest

static func stereo_mode(photo: Dictionary) -> Stereo.Mode:
	var source := {"Path": photo.get("Path", photo.get("Name", "")), "Video3DFormat": photo.get("Video3DFormat", "")}
	var detected := Stereo.detect(source)
	if detected != Stereo.Mode.MONO: return detected
	var pattern := RegEx.new()
	pattern.compile("(?i)(?:^|[ ._\\-])sbs(?:$|[ ._\\-])")
	return Stereo.Mode.FULL_SBS if pattern.search(str(source.Path).get_file()) else Stereo.Mode.MONO

func _ready() -> void:
	request = HTTPRequest.new()
	request.timeout = 30
	request.body_size_limit = 32 * 1024 * 1024
	request.request_completed.connect(_loaded)
	add_child(request)

func _load() -> void:
	var url := api.server + "/Items/%s/Images/Primary" % str(item.Id).uri_encode()
	url += api.query({"maxWidth": 3840, "maxHeight": 3840, "quality": 95, "format": "Jpg"})
	if request.request(url, ["Authorization: " + api.authorization()]) != OK:
		_failed("Could not start the photo request.")

func _loaded(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_failed("Could not load the photo. Check your connection and try again.")
		return
	if code != 200:
		_failed("Could not load the photo. Server returned HTTP %d." % code)
		return
	var image := Image.new()
	if image.load_jpg_from_buffer(body) != OK:
		_failed("The server returned an unreadable photo.")
		return
	photo_ready.emit(ImageTexture.create_from_image(image))

func _failed(text: String) -> void:
	failed.emit(text)

func _exit_tree() -> void:
	if is_instance_valid(request): request.cancel_request()
