## Flashpoint's own Flash runtime: the patched standalone projectors plus
## FlashpointProxy, fetched from the same component zip Infinity uses.
##
## Flashpoint launches 158k of its 167k Flash entries through these — Ruffle is
## its secondary player, not its default. The projectors are import-patched to
## load FlashpointProxy, which reads `proxy.txt`/`port.txt` beside the exe and
## points that process's WinINET at our loopback server. So the movie URL stays
## the archived `http://host/path`, exactly as the launch command records it.

class_name Flash
extends Node

const BIN_ROOT := "user://bin/flash"
const VERSION_PATH := "user://bin/flash/VERSION"
const COMPONENTS_XML := "https://nexus-dev.unstable.life/repository/stable/components.xml"
const ZIP_URL := "https://nexus-dev.unstable.life/repository/stable/supportpack-flash.zip"
const UA := "Reliquary/0.1 (GodOnChain; Flash projector fetch)"
## What the overwhelming majority of Flash entries name.
const DEFAULT_EXE := "flashplayer_32_sa.exe"

var last_error: String = ""
var tag: String = ""
var pack_dir: String = ""
var _pid: int = -1


func has_runtime() -> bool:
	return not _find_exe(_pack_root(), DEFAULT_EXE).is_empty()


func current_tag() -> String:
	if not FileAccess.file_exists(VERSION_PATH):
		return ""
	var file := FileAccess.open(VERSION_PATH, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text().strip_edges()
	file.close()
	return text


## applicationPath like FPSoftware\Flash\flashplayer9r277_win_sa.exe names the
## projector a curator pinned. OldCPUSimulator entries name it in `-sw`.
static func projector_name(entry: Dictionary) -> String:
	var app := str(entry.get("applicationPath", ""))
	var name := _exe_from_path(app)
	if name.is_empty() or name.to_lower() == "oldcpusimulator.exe":
		var launch := str(entry.get("launch", entry.get("launchCommand", "")))
		var swapped := _exe_from_path(Unzip.sw_exe(launch))
		if not swapped.is_empty():
			name = swapped
	if name.is_empty() or name.to_lower() == "oldcpusimulator.exe":
		return DEFAULT_EXE
	return name


## Flashpoint runs these in the standalone projector. Entries whose
## applicationPath names a browser (FPNavigator, Basilisk, a start*.bat) embed
## the movie in a page instead and belong to the Navigator path.
static func projector_entry(entry: Dictionary) -> bool:
	if FlashpointHost.needs_shockwave(entry):
		return false
	var app := str(entry.get("applicationPath", "")).strip_edges()
	if is_projector(app):
		return true
	if app.replace("\\", "/").get_file().to_lower() == "oldcpusimulator.exe":
		var launch := str(entry.get("launch", entry.get("launchCommand", "")))
		return is_projector(Unzip.sw_exe(launch))
	if not app.is_empty():
		return false
	## Rows cached before we kept applicationPath: fall back to the platform,
	## which for Flash is what Flashpoint's own default amounts to.
	return Flashpoint.uses_ruffle(entry)


static func is_projector(application_path: String) -> bool:
	var file := application_path.replace("\\", "/").get_file().to_lower()
	if not file.ends_with(".exe"):
		return false
	return (
		file.begins_with("flashplayer")
		or file.begins_with("saflashplayer")
		or file.begins_with("flashpla")
	)


## Flashpoint hands the projector the whole launch URL — flashvars ride in the
## query string — so keep the query even when the file resolves elsewhere.
static func movie_for(dest_dir: String, launch: String) -> String:
	var url := Unzip.movie_url(launch)
	var query := ""
	var q := url.find("?")
	if q >= 0:
		query = url.substr(q)
		url = url.substr(0, q)
	var rel := Unzip.resolved_rel(dest_dir, launch)
	if not rel.is_empty():
		return Unzip.encode_launch_url("http://" + rel) + query
	if url.begins_with("https://") or url.begins_with("ftp://"):
		url = "http://" + url.substr(url.find("://") + 3)
	if not url.begins_with("http://"):
		return ""
	return Unzip.encode_launch_url(url) + query


func exe_for(entry: Dictionary) -> String:
	return _find_exe(_pack_root(), projector_name(entry))


func ensure(progress: Callable = Callable(), recover: Callable = Callable()) -> bool:
	last_error = ""
	if OS.get_name() != "Windows":
		last_error = "The Flashpoint Flash projector is Windows-only."
		return false

	var installed := current_tag()
	if not installed.is_empty():
		pack_dir = "%s/%s" % [BIN_ROOT, installed]
		if has_runtime():
			tag = installed

	var latest := await _remote_hash()
	if latest.is_empty():
		if has_runtime():
			return true
		latest = "pack"
	if latest == installed and has_runtime():
		tag = latest
		return true

	if progress.is_valid():
		progress.call(2.0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bin"))
	var archive := "user://bin/flash-download.zip"
	if not await _download(ZIP_URL, archive, progress):
		if has_runtime():
			return true
		if not (recover.is_valid() and await recover.call("Flash player", archive)):
			return false
	if not FileAccess.file_exists(archive):
		return has_runtime()

	var dest := "%s/%s" % [BIN_ROOT, latest]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest))
	if not _extract(archive, dest):
		return has_runtime()

	if _find_exe(ProjectSettings.globalize_path(dest), DEFAULT_EXE).is_empty():
		last_error = "Extracted the Flash pack but could not find a projector."
		return has_runtime()

	_write_version(latest)
	if not installed.is_empty() and installed != latest:
		_remove_dir("%s/%s" % [BIN_ROOT, installed])
	tag = latest
	pack_dir = dest
	if progress.is_valid():
		progress.call(100.0)
	return true


## FlashpointProxy, loaded by every patched projector, reads these from the
## working directory: proxy.txt turns it on, port.txt is our loopback port.
func configure_proxy(proxy_port: int) -> bool:
	var exe := _find_exe(_pack_root(), DEFAULT_EXE)
	if exe.is_empty():
		last_error = "The Flash projector is not installed yet."
		return false
	var dir := exe.get_base_dir()
	if not _write_text(dir.path_join("port.txt"), str(proxy_port)):
		last_error = "Could not write the Flash proxy port."
		return false
	if not _write_text(dir.path_join("proxy.txt"), "1"):
		last_error = "Could not write the Flash proxy flag."
		return false
	return true


func play(
	entry: Dictionary,
	movie: String,
	throttle_mhz: int = 0,
	throttle_exe: String = ""
) -> int:
	var want := projector_name(entry)
	var exe := _find_exe(_pack_root(), want)
	if exe.is_empty():
		last_error = "The Flash projector is not installed yet."
		return -1
	var args := PackedStringArray([movie])
	if OS.get_name() == "Windows":
		## cwd is the projector's own folder so FlashpointProxy finds port.txt.
		_pid = Spr.launch_shown(exe, args, exe.get_base_dir(), throttle_mhz, throttle_exe)
	else:
		_pid = OS.create_process(exe, args, false)
	if _pid == -1:
		last_error = "Failed to launch %s." % exe.get_file()
	return _pid


## `Flash/8r22/SAFlashPlayer.exe` ships in the pack as `SAFlashPlayer_8r22.exe`.
static func _exe_from_path(path: String) -> String:
	var p := path.replace("\\", "/").strip_edges()
	if p.is_empty():
		return ""
	var file := p.get_file()
	if not file.to_lower().ends_with(".exe"):
		return ""
	var dir := p.get_base_dir().get_file()
	if _is_version_dir(dir):
		return "%s_%s.exe" % [file.get_basename(), dir]
	return file


static func _is_version_dir(name: String) -> bool:
	if name.length() < 2 or name.length() > 8:
		return false
	if not (name[0] >= "0" and name[0] <= "9"):
		return false
	return name.to_lower().find("r") > 0


func _find_exe(dir: String, want: String) -> String:
	if dir.is_empty():
		return ""
	var name := want if not want.is_empty() else DEFAULT_EXE
	var cands: PackedStringArray = [
		dir.path_join("Flash").path_join(name),
		dir.path_join("FPSoftware").path_join("Flash").path_join(name),
		dir.path_join(name),
	]
	for p in cands:
		if FileAccess.file_exists(p):
			return p
	var hit := _walk_named(dir, name.to_lower())
	if not hit.is_empty():
		return hit
	if name != DEFAULT_EXE:
		return _find_exe(dir, DEFAULT_EXE)
	return ""


func _walk_named(dir: String, want: String) -> String:
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
		var found := _walk_named(sub, want)
		if not found.is_empty():
			return found
	return ""


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
		last_error = "Could not start the Flash component list request."
		http.queue_free()
		return ""
	var result: Array = await http.request_completed
	http.queue_free()
	if int(result[1]) != 200:
		last_error = "Flash component list returned HTTP %s." % str(result[1])
		return ""
	var parser := XMLParser.new()
	if parser.open_buffer(result[3] as PackedByteArray) != OK:
		last_error = "Could not parse the Flash component list."
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
		if id == "flash" and title == "Flash" and download_size > 1_000_000 and hash.length() >= 8:
			return hash
	last_error = "Component list had no Flash support pack."
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
		last_error = "Could not start the Flash pack download."
		ticker.queue_free()
		http.queue_free()
		return false
	ticker.start()
	var result: Array = await http.request_completed
	ticker.stop()
	ticker.queue_free()
	http.queue_free()
	if int(result[1]) != 200:
		last_error = "Flash pack download returned HTTP %s." % str(result[1])
		return false
	return FileAccess.file_exists(dest)


func _extract(archive: String, dest: String) -> bool:
	var abs_archive := ProjectSettings.globalize_path(archive)
	var abs_dest := ProjectSettings.globalize_path(dest)
	if _extract_zip(abs_archive, abs_dest):
		if not _find_exe(abs_dest, DEFAULT_EXE).is_empty():
			return true
	if OS.get_name() == "Windows":
		var ps := PackedStringArray([
			"-NoProfile",
			"-Command",
			"Expand-Archive -Force -Path '%s' -DestinationPath '%s'"
			% [abs_archive.replace("'", "''"), abs_dest.replace("'", "''")],
		])
		var code := OS.execute("powershell", ps, [], false, true)
		if code == 0 and not _find_exe(abs_dest, DEFAULT_EXE).is_empty():
			return true
	if last_error.is_empty():
		last_error = "Could not extract the Flash pack."
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


func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


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
