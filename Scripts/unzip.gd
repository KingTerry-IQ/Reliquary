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


## Split a Flashpoint launch command into argv (quoted tokens kept intact).
static func tokens(command: String) -> PackedStringArray:
	var out := PackedStringArray()
	var s := command.strip_edges()
	var i := 0
	while i < s.length():
		while i < s.length() and s[i] == " ":
			i += 1
		if i >= s.length():
			break
		if s[i] == '"':
			var end := s.find('"', i + 1)
			if end == -1:
				out.append(s.substr(i + 1))
				break
			out.append(s.substr(i + 1, end - i - 1))
			i = end + 1
		else:
			var end2 := s.find(" ", i)
			if end2 == -1:
				out.append(s.substr(i))
				break
			out.append(s.substr(i, end2 - i))
			i = end2
	return out


static func movie_url(launch: String) -> String:
	var t := tokens(launch)
	return t[0] if t.size() > 0 else ""


static func extra_args(launch: String) -> PackedStringArray:
	var t := tokens(launch)
	if t.size() <= 1:
		return PackedStringArray()
	return t.slice(1)


## Host/path leftover from a Flashpoint launch command, no scheme.
static func path_from_launch(launch: String) -> String:
	var path := movie_url(launch)
	if path.is_empty():
		path = launch.strip_edges()
	if path.contains("?"):
		path = path.split("?")[0]
	if path.begins_with("http://"):
		path = path.substr(7)
	elif path.begins_with("https://"):
		path = path.substr(8)
	return path.lstrip("/")


## Map a Flashpoint launch URL onto a file inside the extracted zip.
static func file_for_launch(dest_dir: String, launch: String) -> String:
	var dest := ProjectSettings.globalize_path(dest_dir)
	var path := path_from_launch(launch)
	if path.contains("?"):
		path = path.split("?")[0]
	var candidates: PackedStringArray = [
		dest.path_join("content").path_join(path),
		dest.path_join(path),
	]
	for c in candidates:
		if FileAccess.file_exists(c):
			return c
	var want := path.get_extension().to_lower()
	if not want.is_empty():
		var by_ext := _first_with_ext(dest, want)
		if not by_ext.is_empty():
			return by_ext
	var html := _first_with_ext(dest, "html")
	if not html.is_empty():
		return html
	return _first_with_ext(dest, "swf")


static func swf_for_launch(dest_dir: String, launch: String) -> String:
	var hit := file_for_launch(dest_dir, launch)
	if hit.to_lower().ends_with(".swf"):
		return hit
	return _first_with_ext(ProjectSettings.globalize_path(dest_dir), "swf")


static func _first_with_ext(dir: String, ext: String) -> String:
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	var needle := "." + ext.to_lower()
	d.list_dir_begin()
	var fname := d.get_next()
	var nested: PackedStringArray = []
	while fname != "":
		if fname != "." and fname != "..":
			var full := dir.path_join(fname)
			if d.current_is_dir():
				nested.append(full)
			elif fname.to_lower().ends_with(needle):
				d.list_dir_end()
				return full
		fname = d.get_next()
	d.list_dir_end()
	for sub in nested:
		var hit := _first_with_ext(sub, ext)
		if not hit.is_empty():
			return hit
	return ""
