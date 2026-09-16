## Extract a GameZIP and find the SWF the launch command points at.

class_name Unzip
extends RefCounted


static func extract(zip_path: String, dest_dir: String) -> bool:
	var zip := ZIPReader.new()
	if zip.open(ProjectSettings.globalize_path(zip_path)) != OK:
		return false
	var dest := ProjectSettings.globalize_path(dest_dir)
	DirAccess.make_dir_recursive_absolute(dest)
	for name in zip.get_files():
		if name.ends_with("/"):
			continue
		var out_path := dest.path_join(name)
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var out := FileAccess.open(out_path, FileAccess.WRITE)
		if out == null:
			continue
		out.store_buffer(zip.read_file(name))
		out.close()
	return true


## Map a Flashpoint launch URL onto a file inside the extracted zip.
static func swf_for_launch(dest_dir: String, launch: String) -> String:
	var dest := ProjectSettings.globalize_path(dest_dir)
	var path := launch.strip_edges()
	if path.begins_with("http://"):
		path = path.substr(7)
	elif path.begins_with("https://"):
		path = path.substr(8)
	path = path.lstrip("/")

	var candidates: PackedStringArray = [
		dest.path_join("content").path_join(path),
		dest.path_join(path),
	]
	# Hostname/path as Flashpoint stores it under content/.
	if path.find("/") >= 0:
		candidates.append(dest.path_join("content").path_join(path))
	for c in candidates:
		if FileAccess.file_exists(c):
			return c

	var found := _first_swf(dest)
	return found


static func _first_swf(dir: String) -> String:
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	d.list_dir_begin()
	var fname := d.get_next()
	var nested: PackedStringArray = []
	while fname != "":
		if fname != "." and fname != "..":
			var full := dir.path_join(fname)
			if d.current_is_dir():
				nested.append(full)
			elif fname.to_lower().ends_with(".swf"):
				d.list_dir_end()
				return full
		fname = d.get_next()
	d.list_dir_end()
	for sub in nested:
		var hit := _first_swf(sub)
		if not hit.is_empty():
			return hit
	return ""
