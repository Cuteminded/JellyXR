extends SceneTree

var failures := 0

func _initialize() -> void:
	check(Stereo.detect({"Video3DFormat": "HalfSideBySide"}) == Stereo.Mode.HALF_SBS, "Jellyfin half-SBS enum")
	check(Stereo.detect({"Video3DFormat": "FullSideBySide"}) == Stereo.Mode.FULL_SBS, "Jellyfin full-SBS enum")
	check(Stereo.detect({"Video3DFormat": "HalfSBS"}) == Stereo.Mode.HALF_SBS, "Half-SBS metadata")
	check(Stereo.detect({"Video3DFormat": "FullSBS"}) == Stereo.Mode.FULL_SBS, "Full-SBS metadata")
	check(Stereo.detect({"Path": "/films/Movie.2024.H-SBS.mkv"}) == Stereo.Mode.HALF_SBS, "Half-SBS filename")
	check(Stereo.detect({"Path": "/films/Movie Full-SBS.mkv"}) == Stereo.Mode.FULL_SBS, "Full-SBS filename")
	check(Stereo.detect({"Path": "/SBS/Normal.Movie.mkv"}) == Stereo.Mode.MONO, "Parent directory must not select SBS")
	check(Stereo.detect({"Path": "Movie.3D.SBS.mkv"}) == Stereo.Mode.MONO, "Ambiguous SBS needs manual override")
	check(is_equal_approx(Stereo.aspect(3840, 1080, Stereo.Mode.FULL_SBS), 16.0 / 9.0), "Full-SBS eye proportions")
	check(is_equal_approx(Stereo.aspect(1920, 1080, Stereo.Mode.HALF_SBS), 16.0 / 9.0), "Half-SBS restores eye proportions")
	check(is_equal_approx(Stereo.aspect(0, 0, Stereo.Mode.MONO), 16.0 / 9.0), "Invalid dimensions have a safe aspect")
	var mesh := Stereo.mesh(4.0, 2.0, 0.0)
	check(is_equal_approx(mesh.get_aabb().size.x, 4.0), "Flat screen width")
	check(is_equal_approx(mesh.get_aabb().size.y, 2.0), "Flat screen height")
	var api := JellyfinClient.new()
	check(api.configure("https://example.com/jellyfin/"), "Server subpath accepted")
	check(api.server == "https://example.com/jellyfin", "Trailing slash removed")
	check(not api.configure("file:///etc/passwd"), "Non-HTTP schemes rejected")
	check(not api.configure("https://name:secret@example.com"), "Embedded credentials rejected")
	check(not api.configure("https://example.com/?token=secret"), "Query credentials rejected")
	check(api.query({"SearchTerm": "a & b"}) == "?SearchTerm=a%20%26%20b", "Query values escaped")
	check(api.stream_url("videos/a/master.m3u8") == "https://example.com/jellyfin/videos/a/master.m3u8", "Relative transcoding paths preserve the base URL")
	check(api.stream_url("/videos/a/master.m3u8") == "https://example.com/jellyfin/videos/a/master.m3u8", "Leading slash transcoding paths")
	check(api.stream_url("https://other.example/movie.mp4").is_empty(), "Do not forward authentication to another server")
	check(api.stream_url("//other.example/movie.mp4").is_empty(), "Protocol-relative stream URLs rejected")
	api.free()
	print("Core checks: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
