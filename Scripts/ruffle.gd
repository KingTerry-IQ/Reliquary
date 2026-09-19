## Latest stable Ruffle desktop, fetched from GitHub and launched as its own
## process. The ROM is on-chain; the player is living software.

class_name Ruffle
extends Node

const VERSION_PATH := "user://bin/ruffle/VERSION"
const BIN_ROOT := "user://bin/ruffle"
const WEB_ROOT := "user://bin/ruffle-web"
const WEB_VERSION_PATH := "user://bin/ruffle-web/VERSION"
const GITHUB_LATEST := "https://api.github.com/repos/ruffle-rs/ruffle/releases/latest"
const UA := "Reliquary/0.1 (GodOnChain; Ruffle fetch)"

var last_error: String = ""
var tag: String = ""
var exe_path: String = ""
var _pid: int = -1


func current_tag() -> String:
	if not FileAccess.file_exists(VERSION_PATH):
		return ""
	var file := FileAccess.open(VERSION_PATH, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text().strip_edges()
	file.close()
	return text


func exe_for(installed_tag: String) -> String:
	var dir := ProjectSettings.globalize_path("%s/%s" % [BIN_ROOT, installed_tag])
	return _find_exe(dir)


## Download the latest stable if we do not already have it. Returns false if
## we still have no binary afterwards.
func ensure(recover: Callable = Callable()) -> bool:
	last_error = ""
	var installed := current_tag()
	if not installed.is_empty():
		var have := exe_for(installed)
		if FileAccess.file_exists(have):
			tag = installed
			exe_path = have

	var release: Dictionary = await _github_latest()
	if release.is_empty():
		if not exe_path.is_empty() and FileAccess.file_exists(exe_path):
			return true
		return await _recover_install(recover)

	var latest := str(release.get("tag_name", "")).strip_edges()
	if latest.is_empty():
		last_error = "GitHub release had no tag."
		if not exe_path.is_empty() and FileAccess.file_exists(exe_path):
			return true
		return await _recover_install(recover)

	if latest == installed and FileAccess.file_exists(exe_path):
		tag = latest
		await _ensure_web(release, latest)
		return true

	var url := _asset_url(release)
	if url.is_empty():
		last_error = "No Ruffle asset for this OS in %s." % latest
		await _ensure_web(release, latest)
		if not exe_path.is_empty() and FileAccess.file_exists(exe_path):
			return true
		return await _recover_install(recover)

	var archive := "user://bin/ruffle-download"
	var suffix := _asset_suffix()
	archive += ".zip" if suffix.ends_with(".zip") else ".tar.gz"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bin"))
	if not await _download(url, archive):
		await _ensure_web(release, latest)
		if not exe_path.is_empty() and FileAccess.file_exists(exe_path):
			return true
		return await _recover_install(recover)

	var dest := "%s/%s" % [BIN_ROOT, latest]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest))
	if not _extract(archive, dest):
		await _ensure_web(release, latest)
		if not exe_path.is_empty() and FileAccess.file_exists(exe_path):
			return true
		return await _recover_install(recover)

	var found := exe_for(latest)
	if found.is_empty() or not FileAccess.file_exists(found):
		last_error = "Extracted Ruffle but could not find the executable."
		await _ensure_web(release, latest)
		if not exe_path.is_empty() and FileAccess.file_exists(exe_path):
			return true
		return await _recover_install(recover)

	_write_version(latest)
	if not installed.is_empty() and installed != latest:
		_remove_dir("%s/%s" % [BIN_ROOT, installed])
	tag = latest
	exe_path = found
	await _ensure_web(release, latest)
	if not exe_path.is_empty() and FileAccess.file_exists(exe_path):
		return true
	return await _recover_install(recover)


func _recover_install(recover: Callable) -> bool:
	if not exe_path.is_empty() and FileAccess.file_exists(exe_path):
		return true
	if not recover.is_valid():
		return false
	var archive := "user://bin/ruffle-download.zip"
	if not await recover.call("Ruffle", archive):
		return false
	if not FileAccess.file_exists(archive):
		return false
	var dest := "%s/recovered" % BIN_ROOT
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest))
	if not _extract(archive, dest):
		return false
	var found := exe_for("recovered")
	if found.is_empty() or not FileAccess.file_exists(found):
		last_error = "Provided Ruffle archive had no executable."
		return false
	_write_version("recovered")
	tag = "recovered"
	exe_path = found
	return true


func has_web() -> bool:
	return FileAccess.file_exists(web_js())


func web_dir() -> String:
	return ProjectSettings.globalize_path(WEB_ROOT)


func web_js() -> String:
	return _find_named(web_dir(), "ruffle.js")


func _ensure_web(release: Dictionary, latest: String) -> void:
	if has_web() and _web_tag() == latest:
		return
	var url := _named_asset_url(release, "web-selfhosted.zip")
	if url.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(web_dir())
	var archive := "user://bin/ruffle-web-download.zip"
	if not await _download(url, archive):
		return
	if not _extract(archive, WEB_ROOT):
		return
	if has_web():
		_write_text(WEB_VERSION_PATH, latest)


func _web_tag() -> String:
	if not FileAccess.file_exists(WEB_VERSION_PATH):
		return ""
	var file := FileAccess.open(WEB_VERSION_PATH, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text().strip_edges()
	file.close()
	return text


func _named_asset_url(release: Dictionary, want: String) -> String:
	var assets: Variant = release.get("assets", [])
	if assets is Array:
		for asset: Variant in assets:
			if asset is Dictionary:
				var name := str((asset as Dictionary).get("name", ""))
				if name.ends_with(want) or name.find(want) >= 0:
					return str((asset as Dictionary).get("browser_download_url", ""))
	return ""


func _find_named(dir: String, filename: String) -> String:
	var want := filename.to_lower()
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	d.list_dir_begin()
	var fname := d.get_next()
	var nested: PackedStringArray = []
	while fname != "":
		var full := dir.path_join(fname)
		if d.current_is_dir() and not fname.begins_with("."):
			nested.append(full)
		elif fname.to_lower() == want:
			d.list_dir_end()
			return full
		fname = d.get_next()
	d.list_dir_end()
	for sub in nested:
		var hit := _find_named(sub, filename)
		if not hit.is_empty():
			return hit
	return ""


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.close()


## Default player window: 800px on the long side, height from the movie.
## Resizing Ruffle's wgpu surface is expensive; open already playable.
const WINDOW_WIDTH := 800


static func save_dir() -> String:
	var p := ProjectSettings.globalize_path("user://saves/ruffle")
	DirAccess.make_dir_recursive_absolute(p)
	if OS.get_name() == "Windows":
		p = p.replace("/", "\\")
	return p


static func cli_args(
	swf_path: String,
	base_dir: String = "",
	proxy: String = "",
	spoof_url: String = "",
	save_directory: String = ""
) -> PackedStringArray:
	var movie := swf_path
	var is_url := (
		movie.begins_with("http://")
		or movie.begins_with("https://")
		or movie.begins_with("ftp://")
	)
	if is_url:
		movie = Unzip.encode_launch_url(movie)
	var args: PackedStringArray = [
		movie,
		"--width",
		str(WINDOW_WIDTH),
		"--scale",
		"show-all",
		"--force-scale",
		"--letterbox",
		"on",
	]
	if not base_dir.is_empty():
		var base := base_dir
		if not base.begins_with("http://") and not base.begins_with("https://") and not base.begins_with("ftp://"):
			base = ProjectSettings.globalize_path(base_dir)
		else:
			base = Unzip.encode_launch_url(base)
		args.append_array(PackedStringArray(["--base", base]))
	if not proxy.is_empty():
		args.append_array(PackedStringArray(["--proxy", proxy]))
	if not spoof_url.is_empty():
		args.append_array(PackedStringArray(["--spoof-url", Unzip.encode_launch_url(spoof_url)]))
	if not save_directory.is_empty():
		args.append_array(PackedStringArray(["--storage", "disk", "--save-directory", save_directory]))
	return args


func play(
	swf_path: String,
	base_dir: String = "",
	proxy: String = "",
	spoof_url: String = "",
	throttle_mhz: int = 0,
	throttle_exe: String = ""
) -> int:
	if exe_path.is_empty() or not FileAccess.file_exists(exe_path):
		last_error = "Ruffle is not installed yet."
		return -1
	var movie := swf_path
	var is_url := (
		movie.begins_with("http://")
		or movie.begins_with("https://")
		or movie.begins_with("ftp://")
	)
	if not is_url:
		if not FileAccess.file_exists(swf_path):
			last_error = "No SWF at %s." % swf_path
			return -1
		movie = ProjectSettings.globalize_path(swf_path)
	var args := cli_args(movie, base_dir, proxy, spoof_url, save_dir())
	if OS.get_name() == "Windows":
		_pid = Spr.launch_shown(exe_path, args, "", throttle_mhz, throttle_exe)
	else:
		_pid = OS.create_process(exe_path, args, false)
	if _pid == -1:
		last_error = "Failed to launch Ruffle."
	return _pid


func _github_latest() -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 30
	var err := http.request(
		GITHUB_LATEST,
		PackedStringArray(["User-Agent: %s" % UA, "Accept: application/vnd.github+json"])
	)
	if err != OK:
		last_error = "Could not start GitHub request."
		http.queue_free()
		return {}
	var result: Array = await http.request_completed
	http.queue_free()
	if int(result[1]) != 200:
		last_error = "GitHub latest returned HTTP %s." % str(result[1])
		return {}
	var body: PackedByteArray = result[3]
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


func _asset_url(release: Dictionary) -> String:
	var want := _asset_suffix()
	var assets: Variant = release.get("assets", [])
	if assets is Array:
		for asset: Variant in assets:
			if asset is Dictionary:
				var name := str((asset as Dictionary).get("name", ""))
				if name.ends_with(want) or name.find(want) >= 0:
					return str((asset as Dictionary).get("browser_download_url", ""))
	return ""


func _asset_suffix() -> String:
	var osn := OS.get_name()
	if osn == "Windows":
		return "windows-x86_64.zip"
	if osn == "macOS":
		return "macos-universal.tar.gz"
	if OS.has_feature("arm64"):
		return "linux-aarch64.tar.gz"
	return "linux-x86_64.tar.gz"


func _download(url: String, dest: String) -> bool:
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 0
	http.download_file = dest
	var err := http.request(url, PackedStringArray(["User-Agent: %s" % UA]))
	if err != OK:
		last_error = "Could not start Ruffle download."
		http.queue_free()
		return false
	var result: Array = await http.request_completed
	http.queue_free()
	if int(result[1]) != 200:
		last_error = "Ruffle download returned HTTP %s." % str(result[1])
		return false
	return FileAccess.file_exists(dest)


func _extract(archive: String, dest: String) -> bool:
	var abs_archive := ProjectSettings.globalize_path(archive)
	var abs_dest := ProjectSettings.globalize_path(dest)
	if archive.ends_with(".zip"):
		return _extract_zip(abs_archive, abs_dest)
	var code := OS.execute("tar", PackedStringArray(["-xzf", abs_archive, "-C", abs_dest]), [], false, true)
	if code != 0:
		last_error = "tar failed extracting Ruffle (%s)." % str(code)
		return false
	return true


func _extract_zip(archive: String, dest: String) -> bool:
	var zip := ZIPReader.new()
	if zip.open(archive) != OK:
		last_error = "Could not open %s." % archive
		return false
	for name in zip.get_files():
		if name.ends_with("/"):
			continue
		var out_path := dest.path_join(name.replace("\\", "/"))
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var out := FileAccess.open(out_path, FileAccess.WRITE)
		if out == null:
			continue
		out.store_buffer(zip.read_file(name))
		out.close()
	return true


func _find_exe(dir: String) -> String:
	var names: PackedStringArray = ["ruffle.exe", "ruffle", "Ruffle"]
	for n in names:
		var p := dir.path_join(n)
		if FileAccess.file_exists(p):
			return p
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		var full := dir.path_join(fname)
		if d.current_is_dir() and not fname.begins_with("."):
			var nested := _find_exe(full)
			if not nested.is_empty():
				d.list_dir_end()
				return nested
		elif fname.to_lower().begins_with("ruffle"):
			d.list_dir_end()
			return full
		fname = d.get_next()
	d.list_dir_end()
	return ""


func _write_version(latest: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BIN_ROOT))
	var file := FileAccess.open(VERSION_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(latest)
	file.close()


func _remove_dir(path: String) -> void:
	var abs := ProjectSettings.globalize_path(path)
	var d := DirAccess.open(abs)
	if d == null:
		return
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if fname != "." and fname != "..":
			if d.current_is_dir():
				_remove_dir(path.path_join(fname))
			else:
				d.remove(fname)
		fname = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(abs)
