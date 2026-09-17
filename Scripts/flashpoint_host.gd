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


## Platforms that still need a full Flashpoint install (CLIFp). Shockwave uses
## auto-fetched SPR.exe instead. Unity Web Player is still plugin HTML.
static func needs_flashpoint(entry: Dictionary) -> bool:
	if needs_shockwave(entry):
		return false
	var launch := str(entry.get("launch", entry.get("launchCommand", ""))).to_lower()
	var plat := str(entry.get("platform", "")).to_lower()
	var app := str(entry.get("applicationPath", "")).to_lower()
	if plat.find("unity") >= 0 or app.find("startunity") >= 0:
		return true
	if plat.find("java") >= 0 or app.find("startjava") >= 0:
		return true
	if plat.find("silverlight") >= 0:
		return true
	if plat.find("authorware") >= 0:
		return true
	if plat.find("3dvia") >= 0 or plat.find("popcap") >= 0:
		return true
	if plat.find("shiva") >= 0 or plat.find("pulse") >= 0:
		return true
	if plat.find("activex") >= 0 or app.find("startactivex") >= 0:
		return true
	if plat.find("viscape") >= 0 or plat.find("vrml") >= 0:
		return true
	if app.find("secureplayer") >= 0 or app.find("startcosmo") >= 0:
		return true
	if launch.begins_with("shiva3d") or launch.begins_with("pulse ") or launch.begins_with("svr "):
		return true
	return false
