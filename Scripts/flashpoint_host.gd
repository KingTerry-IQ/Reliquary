## Finds a Flashpoint Archive install and launches titles through CLIFp
## (same path the GUI uses: proxy, SPR.exe, data packs).

class_name FlashpointHost
extends RefCounted

var root: String = ""
var last_error: String = ""


func clifp() -> String:
	if root.is_empty():
		return ""
	for name in ["CLIFp.exe", "clifp.exe", "CLIFp", "clifp"]:
		var p := root.path_join(name)
		if FileAccess.file_exists(p):
			return p
		p = root.path_join("CLIFp").path_join("bin").path_join(name)
		if FileAccess.file_exists(p):
			return p
	return ""


func looks_like_root(path: String) -> bool:
	if path.is_empty():
		return false
	var fp := path.replace("\\", "/")
	if DirAccess.dir_exists_absolute(fp.path_join("FPSoftware")):
		return true
	if FileAccess.file_exists(fp.path_join("CLIFp.exe")) or FileAccess.file_exists(fp.path_join("clifp.exe")):
		return true
	if FileAccess.file_exists(fp.path_join("version.txt")) and DirAccess.dir_exists_absolute(fp.path_join("Data")):
		return true
	return false


func set_root(path: String) -> bool:
	var p := path.replace("\\", "/").rstrip("/")
	if not looks_like_root(p):
		last_error = "That folder does not look like a Flashpoint install (need FPSoftware or CLIFp)."
		return false
	root = p
	last_error = ""
	return true


func autodetect() -> bool:
	var homes: PackedStringArray = [
		OS.get_environment("USERPROFILE"),
		OS.get_environment("HOME"),
		"C:/",
		"D:/",
		"E:/",
	]
	var names: PackedStringArray = [
		"Flashpoint",
		"Flashpoint Archive",
		"Flashpoint Infinity",
		"Flashpoint Ultimate",
		"Games/Flashpoint",
		"Games/Flashpoint Archive",
		"Documents/Flashpoint",
		"Desktop/Flashpoint",
	]
	for home in homes:
		if home.is_empty():
			continue
		var base := home.replace("\\", "/").rstrip("/")
		for n in names:
			var cand := base + "/" + n
			if looks_like_root(cand) and set_root(cand):
				return true
	return false


func play_id(uuid: String) -> int:
	last_error = ""
	var exe := clifp()
	if exe.is_empty():
		last_error = "CLIFp not found in the Flashpoint folder. Put CLIFp.exe in the Flashpoint root (next to the launcher)."
		return -1
	var id := uuid.strip_edges()
	if id.is_empty():
		last_error = "No Flashpoint UUID."
		return -1
	var pid := OS.create_process(exe, PackedStringArray(["play", "-i", id]), false)
	if pid == -1:
		last_error = "Failed to start CLIFp."
	return pid


static func needs_shockwave(entry: Dictionary) -> bool:
	var launch := str(entry.get("launch", entry.get("launchCommand", ""))).to_lower()
	var plat := str(entry.get("platform", "")).to_lower()
	var app := str(entry.get("applicationPath", "")).to_lower()
	if launch.find(".dcr") >= 0 or launch.find(".dir") >= 0 or launch.find(".dxr") >= 0:
		return true
	if launch.find(".cct") >= 0 or launch.find(".cst") >= 0 or launch.find(".cxt") >= 0:
		return true
	if plat.find("shockwave") >= 0:
		return true
	if app.find("shockwave") >= 0 or app.find("spr.exe") >= 0:
		return true
	return false


## Plugin / Navigator host. Flash SWF+HTML and HTML5 play locally; Shockwave
## uses SPR. Everything else (Unity, Vitalize, SVG plugin, start*.bat, a
## SecurePlayer template prefix before the URL, unnamed NPAPI platforms…)
## goes through the fetched support pack, not Chrome or a file association.
static func needs_flashpoint(entry: Dictionary) -> bool:
	if needs_shockwave(entry):
		return false
	var launch := str(entry.get("launch", entry.get("launchCommand", "")))
	var plat := str(entry.get("platform", "")).to_lower()
	var app := str(entry.get("applicationPath", "")).replace("\\", "/").to_lower()
	if app.find("flashplayer") >= 0:
		return false
	if app.ends_with("spr.exe") or app.find("/spr.exe") >= 0:
		return false
	if app.find("secureplayer") >= 0:
		return true
	if app.find(".bat") >= 0 and app.get_file().begins_with("start"):
		return true
	if app.find("netscape") >= 0 or app.find("basilisk") >= 0:
		return true
	## An entry whose applicationPath names the browser is a page, and Flashpoint
	## opens pages in Navigator — for HTML5 as much as for plugin-in-page Flash.
	## Whether we follow it there is the operator's call; this only reports what
	## Flashpoint would do.
	if app.find("fpnavigator") >= 0:
		return true
	var movie := Unzip.movie_url(launch)
	if not movie.is_empty():
		var idx := launch.find(movie)
		if idx > 0:
			var prefix := launch.substr(0, idx).strip_edges().trim_prefix("\"").strip_edges()
			if not prefix.is_empty() and not prefix.to_lower().begins_with("http"):
				return true
	if _plays_in_ruffle_or_html(plat):
		return false
	return not plat.strip_edges().is_empty()


## A page we could equally well open in an ordinary browser, if the operator
## would rather have a modern engine than Flashpoint's.
static func page_entry(entry: Dictionary) -> bool:
	var plat := str(entry.get("platform", "")).to_lower()
	if plat.find("flash") >= 0 or plat.find("html") >= 0:
		return true
	var launch := str(entry.get("launch", entry.get("launchCommand", ""))).to_lower()
	return launch.find(".htm") >= 0


## Flash and HTML5 we host ourselves. "HTML+TIME" is a plugin, not HTML5.
static func _plays_in_ruffle_or_html(plat: String) -> bool:
	var p := plat.strip_edges()
	if p.is_empty():
		return false
	var primary := p.split(";")[0].strip_edges()
	if primary == "flash" or primary.begins_with("flash "):
		return true
	if primary == "html5" or primary == "html 5":
		return true
	if p.find("flash") >= 0 and p.find("html5") >= 0:
		return true
	return false
