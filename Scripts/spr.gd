## Flashpoint Shockwave projector (SPR.exe + Director runtime). Fetched from
## the same component zip Infinity/Manager use — not a user-installed copy.

class_name Spr
extends Node

const BIN_ROOT := "user://bin/shockwave"
const VERSION_PATH := "user://bin/shockwave/VERSION"
const COMPONENTS_XML := "https://nexus-dev.unstable.life/repository/stable/components.xml"
const ZIP_URL := "https://nexus-dev.unstable.life/repository/stable/supportpack-shockwave.zip"
const UA := "FlashCartridge/0.1 (GodOnChain; SPR fetch)"
const DEFAULT_PJ := "PJ101"

var last_error: String = ""
var tag: String = ""
var pack_dir: String = ""
var _pid: int = -1


func has_runtime() -> bool:
	return not _find_exe(_pack_root(), DEFAULT_PJ).is_empty()


func current_tag() -> String:
	if not FileAccess.file_exists(VERSION_PATH):
		return ""
	var file := FileAccess.open(VERSION_PATH, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text().strip_edges()
	file.close()
	return text


## applicationPath like FPSoftware\Shockwave\PJ1159\SPR.exe → PJ1159.
static func projector_folder(application_path: String) -> String:
	var p := application_path.replace("\\", "/")
	for part in p.split("/"):
		var up := part.to_upper()
		if up.begins_with("PJ") and up.length() >= 3:
			return part
	return DEFAULT_PJ


func exe_for(pj: String = DEFAULT_PJ) -> String:
	return _find_exe(_pack_root(), pj)


func ensure(progress: Callable = Callable()) -> bool:
	last_error = ""
	if OS.get_name() != "Windows":
		last_error = "Shockwave projector is Windows-only."
		return false

	var installed := current_tag()
	if not installed.is_empty():
		pack_dir = "%s/%s" % [BIN_ROOT, installed]
		var have := _find_exe(ProjectSettings.globalize_path(pack_dir), DEFAULT_PJ)
		if FileAccess.file_exists(have):
			tag = installed

	var latest := await _remote_hash()
	if latest.is_empty():
		if not tag.is_empty():
			return true
		latest = "pack"
	if latest == installed and has_runtime():
		tag = latest
		return true

	if progress.is_valid():
		progress.call(2.0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bin"))
	var archive := "user://bin/shockwave-download.zip"
	if not await _download(ZIP_URL, archive, progress):
		return has_runtime()

	var dest := "%s/%s" % [BIN_ROOT, latest]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest))
	if not _extract(archive, dest):
		return has_runtime()

	var found := _find_exe(ProjectSettings.globalize_path(dest), DEFAULT_PJ)
	if found.is_empty() or not FileAccess.file_exists(found):
		last_error = "Extracted Shockwave pack but could not find SPR.exe."
		return has_runtime()

	_write_version(latest)
	if not installed.is_empty() and installed != latest:
		_remove_dir("%s/%s" % [BIN_ROOT, installed])
	tag = latest
	pack_dir = dest
	if progress.is_valid():
		progress.call(100.0)
	return true


## SPR.dir Lingo: if proxy.txt is 1, proxyServer(#http, "127.0.0.1", port.txt).
func configure_proxy(proxy_port: int, pj: String = DEFAULT_PJ) -> bool:
	var exe := exe_for(pj)
	if exe.is_empty() or not FileAccess.file_exists(exe):
		last_error = "SPR.exe is not installed yet."
		return false
	var dir := exe.get_base_dir()
	if not _write_text(dir.path_join("port.txt"), str(proxy_port)):
		last_error = "Could not write SPR port.txt."
		return false
	if not _write_text(dir.path_join("proxy.txt"), "1"):
		last_error = "Could not write SPR proxy.txt."
		return false
	return true


func play(movie: String, extra: PackedStringArray = PackedStringArray(), pj: String = DEFAULT_PJ) -> int:
	var exe := exe_for(pj)
	if exe.is_empty() or not FileAccess.file_exists(exe):
		last_error = "SPR.exe is not installed yet."
		return -1
	var args := PackedStringArray([movie])
	args.append_array(extra)
	_pid = OS.create_process(exe, args, false)
	if _pid == -1:
		last_error = "Failed to launch SPR.exe."
	return _pid


func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


func _pack_root() -> String:
	if not pack_dir.is_empty():
		return ProjectSettings.globalize_path(pack_dir)
	var installed := current_tag()
	if installed.is_empty():
		return ProjectSettings.globalize_path(BIN_ROOT)
	return ProjectSettings.globalize_path("%s/%s" % [BIN_ROOT, installed])


func _remote_hash() -> String:
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 30
	var err := http.request(COMPONENTS_XML, PackedStringArray(["User-Agent: %s" % UA]))
	if err != OK:
		last_error = "Could not start Shockwave component list request."
		http.queue_free()
		return ""
	var result: Array = await http.request_completed
	http.queue_free()
	if int(result[1]) != 200:
		last_error = "Shockwave component list returned HTTP %s." % str(result[1])
		return ""
	var body: PackedByteArray = result[3]
	var parser := XMLParser.new()
	if parser.open_buffer(body) != OK:
		last_error = "Could not parse Shockwave component list."
		return ""
	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		if parser.get_node_name() != "component":
			continue
		var id := ""
		var title := ""
		var hash := ""
		var download_size := 0
		for i in parser.get_attribute_count():
			var key := parser.get_attribute_name(i)
			var val := parser.get_attribute_value(i)
			match key:
				"id":
					id = val
				"title":
					title = val
				"hash":
					hash = val
				"download-size":
					download_size = int(val)
		if id == "shockwave" and title == "Shockwave" and download_size > 1_000_000 and hash.length() >= 8:
			return hash
	last_error = "Component list had no Shockwave support pack."
	return ""


func _download(url: String, dest: String, progress: Callable = Callable()) -> bool:
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 0
	http.download_file = dest
	var ticker := Timer.new()
	ticker.wait_time = 0.4
	ticker.timeout.connect(func() -> void:
		if not progress.is_valid():
			return
		var total := http.get_body_size()
		if total > 0:
			progress.call(5.0 + 80.0 * float(http.get_downloaded_bytes()) / float(total))
	)
	add_child(ticker)
	var err := http.request(url, PackedStringArray(["User-Agent: %s" % UA]))
	if err != OK:
		last_error = "Could not start Shockwave pack download."
		ticker.queue_free()
		http.queue_free()
		return false
	ticker.start()
	var result: Array = await http.request_completed
	ticker.stop()
	ticker.queue_free()
	http.queue_free()
	if int(result[1]) != 200:
		last_error = "Shockwave pack download returned HTTP %s." % str(result[1])
		return false
	return FileAccess.file_exists(dest)


func _extract(archive: String, dest: String) -> bool:
	var abs_archive := ProjectSettings.globalize_path(archive)
	var abs_dest := ProjectSettings.globalize_path(dest)
	if _extract_zip(abs_archive, abs_dest):
		if not _find_exe(abs_dest, DEFAULT_PJ).is_empty():
			return true
	if OS.get_name() == "Windows":
		var ps := PackedStringArray([
			"-NoProfile",
			"-Command",
			"Expand-Archive -Force -Path '%s' -DestinationPath '%s'" % [abs_archive.replace("'", "''"), abs_dest.replace("'", "''")],
		])
		var code := OS.execute("powershell", ps, [], false, true)
		if code == 0 and not _find_exe(abs_dest, DEFAULT_PJ).is_empty():
			return true
	if last_error.is_empty():
		last_error = "Could not extract the Shockwave pack."
	return false


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


func _find_exe(dir: String, pj: String) -> String:
	if dir.is_empty():
		return ""
	var want := pj if not pj.is_empty() else DEFAULT_PJ
	var names: PackedStringArray = [
		dir.path_join("Shockwave").path_join(want).path_join("SPR.exe"),
		dir.path_join("FPSoftware").path_join("Shockwave").path_join(want).path_join("SPR.exe"),
		dir.path_join(want).path_join("SPR.exe"),
	]
	for p in names:
		if FileAccess.file_exists(p):
			return p
	if want != DEFAULT_PJ:
		var fallback := _find_exe(dir, DEFAULT_PJ)
		if not fallback.is_empty():
			return fallback
	return _walk_spr(dir)


func _walk_spr(dir: String) -> String:
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
		elif fname.to_lower() == "spr.exe":
			d.list_dir_end()
			return full
		fname = d.get_next()
	d.list_dir_end()
	for sub in nested:
		var hit := _walk_spr(sub)
		if not hit.is_empty():
			return hit
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
