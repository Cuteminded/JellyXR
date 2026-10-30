extends SceneTree

var failures := 0

func _initialize() -> void:
	check_jellyfin_3d()
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

func check_jellyfin_3d() -> void:
	var formats := {"HSBS": Stereo.Mode.HALF_SBS, "FSBS": Stereo.Mode.FULL_SBS, "HTAB": Stereo.Mode.HALF_TOP_BOTTOM, "FTAB": Stereo.Mode.TOP_BOTTOM, "MVC": Stereo.Mode.MONO}
	for tag in formats:
		for separator in [" ", "-", ".", "_"]:
			for prefix in ["Awesome Movie (2022)", "Series S01E01 Title", "Movie (2022) -"]:
				var filename: String = prefix + separator + "3d" + separator + tag + ".mkv"
				check(Stereo.detect({"Path": filename}) == formats[tag], "Jellyfin filename: " + filename)
		check(Stereo.detect({"Path": "3D." + tag.to_lower()}) == formats[tag], "Filename boundary: " + tag)
	check(Stereo.detect({"Path": "Movie.3D_hTaB.mp4"}) == Stereo.Mode.HALF_TOP_BOTTOM, "Mixed separators and case")
	for filename in ["/Movie.3D.HTAB/Movie.mkv", "C:\\Movie.3D.FTAB\\Movie.mkv", "Movie.3D.HTABextra.mkv", "Movie.x3D.FTAB.mkv", "Movie[3D][HTAB].mkv", "Movie.HTAB.mkv", "Movie.FTAB.mkv", "Movie.3D.mkv"]:
		check(Stereo.detect({"Path": filename}) == Stereo.Mode.MONO, "Avoid false 3D detection: " + filename)
	check(Stereo.detect({"Video3DFormat": "HalfTopAndBottom"}) == Stereo.Mode.HALF_TOP_BOTTOM, "Jellyfin half top-bottom metadata")
	check(Stereo.detect({"Video3DFormat": "FullTopAndBottom"}) == Stereo.Mode.TOP_BOTTOM, "Jellyfin full top-bottom metadata")
	check(Stereo.detect({"Video3DFormat": null, "Path": "Movie.3D.HTAB.mkv"}) == Stereo.Mode.HALF_TOP_BOTTOM, "Missing metadata falls back to filename")
	check(Stereo.detect({"Video3DFormat": "HalfTopAndBottom", "Path": "Movie.3D.FSBS.mkv"}) == Stereo.Mode.HALF_TOP_BOTTOM, "Metadata takes priority over filename")
	check(Stereo.detect({"Video3DFormat": "MVC", "Path": "Movie.3D.HSBS.mkv"}) == Stereo.Mode.MONO, "MVC is not treated as packed SBS")
	check(is_equal_approx(Stereo.aspect(1920, 1080, Stereo.Mode.HALF_TOP_BOTTOM), 16.0 / 9.0), "Half top-bottom restores eye proportions")
	check(is_equal_approx(Stereo.aspect(1920, 2160, Stereo.Mode.TOP_BOTTOM), 16.0 / 9.0), "Full top-bottom preserves eye proportions")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
