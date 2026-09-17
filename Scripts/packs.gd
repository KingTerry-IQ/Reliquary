## Flashpoint support packs (FPNavigator + plugin runtimes), fetched from the
## same nexus Infinity uses. HTML5 plays in Navigator against local files —
## not the user's browser, and not the live site.

class_name Packs
extends Node

const COMPONENTS_XML := "https://nexus-dev.unstable.life/repository/stable/components.xml"
const ZIP_URL := "https://nexus-dev.unstable.life/repository/stable/%s.zip"
const BIN_ROOT := "user://bin/fpsoftware"
const UA := "Reliquary/0.1 (GodOnChain; support pack fetch)"
const PLUGIN_PORT := 22600
const SKIP_DEPENDS: PackedStringArray = [
	"supportpack-common-chromium",
	"supportpack-common-browsermode",
]
const NAV_PREFS := """pref("network.proxy.type", 1);
pref("network.proxy.http", "127.0.0.1");
pref("network.proxy.http_port", %d);
pref("network.proxy.ssl", "127.0.0.1");
pref("network.proxy.ssl_port", %d);
pref("network.proxy.share_proxy_settings", true);
pref("network.proxy.no_proxies_on", "");
pref("browser.shell.checkDefaultBrowser", false);
"""

var last_error: String = ""
var tag: String = ""
var _index: Dictionary = {}
var _pid: int = -1


static func pack_label(id: String) -> String:
	var tail := id.get_file().replace("supportpack-", "").replace("common-", "")
	match tail:
		"fpnavigator":
			return "Fetching Navigator"
		"secureplayer":
			return "Fetching Secure Player"
		"unity":
			return "Fetching Unity runtime"
		"java":
			return "Fetching Java runtime"
		"activex":
			return "Fetching ActiveX runtime"
		"shiva3d":
			return "Fetching ShiVa3D runtime"
		"silverlight":
			return "Fetching Silverlight runtime"
		"pulse":
			return "Fetching Pulse runtime"
		"viscape":
			return "Fetching Viscape runtime"
		"vrml":
			return "Fetching VRML runtime"
		"popcapplugin":
			return "Fetching PopCap runtime"
		"authorware":
			return "Fetching Authorware runtime"
		"3dviaplayer":
			return "Fetching 3DVIA runtime"
		_:
			return "Fetching %s" % tail


## ShiVa SecurePlayer rewrites http://host → http://localhost:22600/host.
static func uses_fp_url_rewrite(template: String) -> bool:
	return template.to_lower() == "shiva3d"


## FlashpointSecurePlayer template + URL. Bats unwrap to this.
static func secureplayer_invocation(
	entry: Dictionary,
	local_movie: String,
	original_movie: String
) -> PackedStringArray:
	var app := str(entry.get("applicationPath", "")).replace("\\", "/").to_lower()
	var raw := str(entry.get("launch", entry.get("launchCommand", ""))).strip_edges()
	var extra := Unzip.extra_args(raw)
	if app.ends_with("startactivex.bat"):
		var dll := extra[0] if extra.size() > 0 else ""
		return PackedStringArray(["ActiveX\\" + dll.replace("/", "\\"), local_movie])
	if app.ends_with("startjava.bat"):
		return PackedStringArray(["java", local_movie])
	if app.ends_with("startunity.bat"):
		var ver := Unzip.tokens(raw)[0] if Unzip.tokens(raw).size() > 0 else "5.x"
		var template := "unitywebplayer5"
		if ver == "1.x":
			template = "unitywebplayer1"
		elif ver == "2.x":
			template = "unitywebplayer2"
		elif ver == "3.x":
			template = "unitywebplayer3"
		elif ver == "4.x":
			template = "unitywebplayer4"
		return PackedStringArray([template, local_movie])
	if app.ends_with("flashpointsecureplayer.exe"):
		var t := Unzip.tokens(raw)
		var template := t[0] if t.size() > 0 and not t[0].to_lower().begins_with("http") else ""
		if template.is_empty():
			return PackedStringArray()
		var url := original_movie if uses_fp_url_rewrite(template) else local_movie
		return PackedStringArray([template, url])
	return PackedStringArray()


## Prefix (shiva3d, 5.x) + local movie URL + trailing extras (dll paths).
static func launch_argv(entry: Dictionary, local_movie: String) -> PackedStringArray:
	var raw := str(entry.get("launch", entry.get("launchCommand", ""))).strip_edges()
	var movie := Unzip.movie_url(raw)
	var out := PackedStringArray()
	if not movie.is_empty():
		var idx := raw.find(movie)
		if idx > 0:
			out = Unzip.tokens(raw.substr(0, idx))
	if not local_movie.is_empty():
		out.append(local_movie)
	else:
		out.append(movie)
	out.append_array(Unzip.extra_args(raw))
	return out


static func pack_id_for(entry: Dictionary) -> String:
	var plat := str(entry.get("platform", "")).to_lower()
	var app := str(entry.get("applicationPath", "")).to_lower()
	var launch := str(entry.get("launch", entry.get("launchCommand", ""))).to_lower()
	if plat.find("unity") >= 0 or app.find("startunity") >= 0:
		return "supportpack-unity"
	if plat.find("java") >= 0 or app.find("startjava") >= 0:
		return "supportpack-java"
	if plat.find("silverlight") >= 0:
		return "supportpack-silverlight"
	if plat.find("authorware") >= 0:
		return "supportpack-authorware"
	if plat.find("3dvia") >= 0:
		return "supportpack-3dviaplayer"
	if plat.find("popcap") >= 0:
		return "supportpack-popcapplugin"
	if plat.find("shiva") >= 0 or launch.begins_with("shiva3d"):
		return "supportpack-shiva3d"
	if plat.find("pulse") >= 0 or launch.begins_with("pulse"):
		return "supportpack-pulse"
	if plat.find("activex") >= 0 or app.find("startactivex") >= 0:
		return "supportpack-activex"
	if plat.find("viscape") >= 0:
		return "supportpack-viscape"
	if plat.find("vrml") >= 0 or app.find("startcosmo") >= 0:
		return "supportpack-vrml"
	if app.find("secureplayer") >= 0:
		return "supportpack-common-secureplayer"
	return "supportpack-common-fpnavigator"


func has_navigator() -> bool:
	return FileAccess.file_exists(navigator_exe())


func navigator_exe() -> String:
	return _find_named(_pack_root(), "fpnavigator.exe")


func secureplayer_exe() -> String:
	var root := _pack_root()
	var direct := root.path_join("FlashpointSecurePlayer.exe")
	if FileAccess.file_exists(direct):
		return direct
	return _find_named(root, "flashpointsecureplayer.exe")


func mark_compat(exe: String) -> void:
	if exe.is_empty() or not FileAccess.file_exists(exe):
		return
	var path := ProjectSettings.globalize_path(exe).replace("/", "\\")
	OS.execute(
		"reg",
		PackedStringArray([
			"add",
			"HKCU\\Software\\Microsoft\\Windows NT\\CurrentVersion\\AppCompatFlags\\Layers",
			"/v",
			path,
			"/t",
			"REG_SZ",
			"/d",
			"~ RUNASINVOKER",
			"/f",
		]),
		[],
		false,
		true
	)


func pack_root() -> String:
	return _pack_root()


func can_play(entry: Dictionary) -> bool:
	if has_navigator():
		return true
	return not resolve_app(str(entry.get("applicationPath", ""))).is_empty()


func resolve_app(application_path: String) -> String:
	var rel := application_path.replace("\\", "/").strip_edges()
	if rel.is_empty():
		return navigator_exe()
	if rel.to_lower().begins_with("fpsoftware/"):
		rel = rel.substr(11)
	var root := _pack_root()
	var cands: PackedStringArray = [
		root.path_join(rel),
		root.path_join("FPSoftware").path_join(rel),
		root.path_join(rel.get_file()),
	]
	for c in cands:
		if FileAccess.file_exists(c):
			return c
	var fname := rel.get_file().to_lower()
	if fname.ends_with(".exe") or fname.ends_with(".bat"):
		var hit := _find_named(root, fname)
		if not hit.is_empty():
			return hit
	return navigator_exe()


func ensure_for(
	entry: Dictionary,
	progress: Callable = Callable(),
	status: Callable = Callable()
) -> bool:
	last_error = ""
	if OS.get_name() != "Windows":
		last_error = "Plugin runtimes are Windows-only."
		return can_play(entry)
	var primary := pack_id_for(entry)
	var ids := await _needed_ids(primary)
	if ids.is_empty():
		ids = PackedStringArray([primary])
	for id in ids:
		if status.is_valid():
			status.call(pack_label(id))
		if not await _ensure_id(id, progress):
			if id == pack_id_for(entry) or id == "supportpack-common-secureplayer":
				return can_play(entry) and FileAccess.file_exists(resolve_app(str(entry.get("applicationPath", ""))))
	if progress.is_valid():
		progress.call(100.0)
	tag = pack_id_for(entry)
	return not resolve_app(str(entry.get("applicationPath", ""))).is_empty() or has_navigator()


func configure_proxy(port: int) -> bool:
	var exe := navigator_exe()
	if exe.is_empty():
		last_error = "Flashpoint Navigator is not installed yet."
		return false
	var prefs := NAV_PREFS % [port, port]
	var user := prefs.replace("pref(", "user_pref(")
	var root := exe.get_base_dir()
	var pref_dir := root.path_join("defaults").path_join("pref")
	DirAccess.make_dir_recursive_absolute(pref_dir)
	_write_text(pref_dir.path_join("reliquary-proxy.js"), prefs)
	var profiles: PackedStringArray = [
		root.path_join("Profile"),
		root.path_join("Data").path_join("profile"),
		root.path_join("browser").path_join("defaults").path_join("profile"),
		ProjectSettings.globalize_path("user://bin/nav-profile"),
	]
	for p in profiles:
		DirAccess.make_dir_recursive_absolute(p)
		_write_text(p.path_join("user.js"), user)
	return true


func play_url(movie: String) -> int:
	var exe := navigator_exe()
	if exe.is_empty() or not FileAccess.file_exists(exe):
		last_error = "Flashpoint Navigator is not installed yet."
		return -1
	var profile := ProjectSettings.globalize_path("user://bin/nav-profile")
	DirAccess.make_dir_recursive_absolute(profile)
	var args := PackedStringArray(["-no-remote", "-profile", profile, movie])
	if OS.get_name() == "Windows":
		_pid = Spr.launch_shown(exe, args)
	else:
		_pid = OS.create_process(exe, args, false)
	if _pid == -1:
		last_error = "Failed to launch Navigator."
	return _pid


func play_app(entry: Dictionary, local_movie: String, original_movie: String = "") -> int:
	var root := _pack_root()
	var sp := secureplayer_exe()
	var inv := secureplayer_invocation(entry, local_movie, original_movie)
	if not inv.is_empty() and FileAccess.file_exists(sp):
		mark_compat(sp)
		mark_compat(root.path_join("ShiVa3D").path_join("S3DEngine.exe"))
		if OS.get_name() == "Windows":
			_pid = Spr.launch_shown(sp, inv, root)
		else:
			_pid = OS.create_process(sp, inv, false)
		if _pid == -1:
			last_error = "Failed to launch Secure Player."
		return _pid
	var app := resolve_app(str(entry.get("applicationPath", "")))
	if app.is_empty():
		last_error = "No runtime exe in the support pack."
		return -1
	var lower := app.to_lower()
	if lower.ends_with("fpnavigator.exe") or lower.ends_with("startchrome.bat"):
		return play_url(local_movie)
	var argv := launch_argv(entry, local_movie)
	var cwd := app.get_base_dir()
	if lower.ends_with(".bat"):
		var bat_args := PackedStringArray(["/c", "call", app])
		bat_args.append_array(argv)
		if OS.get_name() == "Windows":
			_pid = Spr.launch_shown("cmd.exe", bat_args, cwd)
		else:
			_pid = OS.create_process(app, argv, false)
	elif OS.get_name() == "Windows":
		_pid = Spr.launch_shown(app, argv, cwd)
	else:
		_pid = OS.create_process(app, argv, false)
	if _pid == -1:
		last_error = "Failed to launch %s." % app.get_file()
	return _pid


func _needed_ids(primary: String) -> PackedStringArray:
	var index := await _load_index()
	var out: PackedStringArray = []
	_collect_ids(index, primary, out)
	return out


func _collect_ids(index: Dictionary, id: String, out: PackedStringArray) -> void:
	if id.is_empty() or SKIP_DEPENDS.has(id) or out.has(id):
		return
	out.append(id)
	var rec: Variant = index.get(id, {})
	if rec is Dictionary:
		var deps: Variant = (rec as Dictionary).get("depends", PackedStringArray())
		if deps is PackedStringArray:
			for d in deps:
				_collect_ids(index, d, out)
		elif deps is Array:
			for d: Variant in deps:
				_collect_ids(index, str(d), out)


func _ensure_id(id: String, progress: Callable = Callable()) -> bool:
	var marker := "%s/VERSION-%s" % [BIN_ROOT, id.get_file()]
	var rec: Dictionary = _index.get(id, {})
	var want := str(rec.get("hash", "pack"))
	if FileAccess.file_exists(marker):
		var have := _read_text(marker)
		if have == want or want == "pack":
			if progress.is_valid():
				progress.call(100.0)
			return true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BIN_ROOT))
	var archive := "user://bin/%s-download.zip" % id.get_file()
	if not await _download(ZIP_URL % id, archive, progress):
		return false
	if not _extract(archive, BIN_ROOT):
		return false
	_write_text(marker, want if not want.is_empty() else "pack")
	return true


func _load_index() -> Dictionary:
	if not _index.is_empty():
		return _index
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 30
	var err := http.request(COMPONENTS_XML, PackedStringArray(["User-Agent: %s" % UA]))
	if err != OK:
		last_error = "Could not start component list request."
		http.queue_free()
		return {}
	var result: Array = await http.request_completed
	http.queue_free()
	if int(result[1]) != 200:
		last_error = "Component list returned HTTP %s." % str(result[1])
		return {}
	_index = _parse_components(result[3] as PackedByteArray)
	return _index


static func _parse_components(body: PackedByteArray) -> Dictionary:
	var parser := XMLParser.new()
	if parser.open_buffer(body) != OK:
		return {}
	var stack: PackedStringArray = []
	var out := {}
	while parser.read() == OK:
		var kind := parser.get_node_type()
		if kind == XMLParser.NODE_ELEMENT_END:
			if parser.get_node_name() == "category" and stack.size() > 0:
				stack.remove_at(stack.size() - 1)
			continue
		if kind != XMLParser.NODE_ELEMENT:
			continue
		var node := parser.get_node_name()
		if node == "category":
			var cid := ""
			for i in parser.get_attribute_count():
				if parser.get_attribute_name(i) == "id":
					cid = parser.get_attribute_value(i)
			if not cid.is_empty():
				stack.append(cid)
			continue
		if node != "component":
			continue
		var id := ""
		var hash := ""
		var depends := PackedStringArray()
		for i in parser.get_attribute_count():
			var key := parser.get_attribute_name(i)
			var val := parser.get_attribute_value(i)
			match key:
				"id":
					id = val
				"hash":
					hash = val
				"depends":
					depends = PackedStringArray(val.split(" "))
		if id.is_empty():
			continue
		var parts := stack.duplicate()
		parts.append(id)
		var full := "-".join(parts)
		out[full] = {"id": id, "hash": hash, "depends": depends}
	return out


func _pack_root() -> String:
	return ProjectSettings.globalize_path(BIN_ROOT)


func _download(url: String, dest: String, progress: Callable = Callable()) -> bool:
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 0
	http.download_file = dest
	var ticker := Timer.new()
	ticker.wait_time = 0.25
	ticker.timeout.connect(func() -> void:
		if not progress.is_valid():
			return
		var total := http.get_body_size()
		if total > 0:
			progress.call(100.0 * float(http.get_downloaded_bytes()) / float(total))
	)
	add_child(ticker)
	var err := http.request(url, PackedStringArray(["User-Agent: %s" % UA]))
	if err != OK:
		last_error = "Could not start pack download."
		ticker.queue_free()
		http.queue_free()
		return false
	ticker.start()
	var result: Array = await http.request_completed
	ticker.stop()
	ticker.queue_free()
	http.queue_free()
	if int(result[1]) != 200:
		last_error = "Pack download returned HTTP %s." % str(result[1])
		return false
	if progress.is_valid():
		progress.call(100.0)
	return FileAccess.file_exists(dest)


func _extract(archive: String, dest: String) -> bool:
	var abs_archive := ProjectSettings.globalize_path(archive)
	var abs_dest := ProjectSettings.globalize_path(dest)
	if _extract_zip(abs_archive, abs_dest):
		return true
	if OS.get_name() == "Windows":
		var ps := PackedStringArray([
			"-NoProfile",
			"-Command",
			"Expand-Archive -Force -Path '%s' -DestinationPath '%s'"
			% [abs_archive.replace("'", "''"), abs_dest.replace("'", "''")],
		])
		if OS.execute("powershell", ps, [], false, true) == 0:
			return true
	last_error = "Could not extract %s." % archive.get_file()
	return false


func _extract_zip(archive: String, dest: String) -> bool:
	var zip := ZIPReader.new()
	if zip.open(archive) != OK:
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


func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text().strip_edges()
	file.close()
	return text
