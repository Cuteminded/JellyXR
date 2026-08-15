class_name ArtworkLoader
extends Node

var api: JellyfinClient
var queue: Array[Dictionary] = []
var active := 0
var cache: Dictionary = {}
var order: Array[String] = []

func fetch(target: TextureRect, item: Dictionary, backdrop: bool = false) -> void:
	var tags: Dictionary = item.get("ImageTags", {}) if item.get("ImageTags") else {}
	if not backdrop and not tags.has("Primary"): return
	if backdrop and not item.get("BackdropImageTags"): return
	var url := api.image_url(item, backdrop)
	if cache.has(url):
		target.texture = cache[url]
		return
	queue.append({"target": weakref(target), "url": url})
	_drain()

func _drain() -> void:
	while active < 4 and not queue.is_empty():
		var job: Dictionary = queue.pop_front()
		if not is_instance_valid(job.target.get_ref()): continue
		active += 1
		_load(job)

func _load(job: Dictionary) -> void:
	var request := HTTPRequest.new()
	request.timeout = 12
	add_child(request)
	var texture: Texture2D
	if request.request(job.url, ["Authorization: " + api.authorization()]) == OK:
		var response: Array = await request.request_completed
		if response[0] == HTTPRequest.RESULT_SUCCESS and response[1] == 200:
			var image := Image.new()
			var data: PackedByteArray = response[3]
			var error := ERR_FILE_UNRECOGNIZED
			if data.size() >= 12:
				if data[0] == 0xff and data[1] == 0xd8: error = image.load_jpg_from_buffer(data)
				elif data.slice(0, 8) == PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]): error = image.load_png_from_buffer(data)
				elif data.slice(8, 12).get_string_from_ascii() == "WEBP": error = image.load_webp_from_buffer(data)
			if error == OK: texture = ImageTexture.create_from_image(image)
	request.queue_free()
	if texture:
		cache[job.url] = texture
		order.append(job.url)
		if order.size() > 48: cache.erase(order.pop_front())
		var target: TextureRect = job.target.get_ref()
		if is_instance_valid(target): target.texture = texture
	active -= 1
	_drain()
