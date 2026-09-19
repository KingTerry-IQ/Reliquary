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
## Unquoted http(s)/ftp URLs keep spaces until a ` --` flag (Flashpoint Flash
## titles often ship `http://host/Swords and Sandals 2/game.swf`).
static func tokens(command: String) -> PackedStringArray:
	var s := command.strip_edges()
	if s.is_empty():
		return PackedStringArray()
	if not s.begins_with('"') and _is_url_prefix(s):
		var flag := s.find(" --")
		var url := s if flag < 0 else s.substr(0, flag).strip_edges()
		var out := PackedStringArray([url])
		if flag >= 0:
			out.append_array(_split_tokens(s.substr(flag + 1)))
		return out
	return _split_tokens(s)


static func _split_tokens(command: String) -> PackedStringArray:
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


static func _is_url_prefix(s: String) -> bool:
	var lower := s.to_lower()
	return (
		lower.begins_with("http://")
		or lower.begins_with("https://")
		or lower.begins_with("ftp://")
	)


## First http(s)/ftp URL in a Flashpoint launch command. Runtime prefixes
## (`5.x`, `Pulse`, OldCPUSimulator `-t -sw`) stay out of the path.
static func movie_url(launch: String) -> String:
	var url := _first_url(launch.strip_edges())
	if not url.is_empty():
		return url
	var t := tokens(launch)
	return t[0] if t.size() > 0 else ""


static func extra_args(launch: String) -> PackedStringArray:
	var s := launch.strip_edges()
	var movie := movie_url(s)
	if movie.is_empty():
		var t := tokens(s)
		return t.slice(1) if t.size() > 1 else PackedStringArray()
	var idx := s.find(movie)
	if idx < 0:
		return PackedStringArray()
	var end := idx + movie.length()
	if end < s.length() and s[end] == '"':
		end += 1
	return _split_tokens(s.substr(end))


## OldCPUSimulator `-t N` (MHz) from a Flashpoint launch command.
static func cpu_mhz(launch: String) -> int:
	var t := tokens(launch)
	var i := 0
	while i < t.size():
		var a := t[i]
		if a == "-t" or a == "--target-rate":
			if i + 1 < t.size() and str(t[i + 1]).is_valid_int():
				return maxi(0, int(t[i + 1]))
		i += 1
	return 0


## Curation `-t` wins. Authentic mode otherwise picks an era clock from releaseDate.
static func era_mhz(entry: Dictionary, launch: String = "", authentic: bool = true) -> int:
	var cmd := launch.strip_edges()
	if cmd.is_empty():
		cmd = str(entry.get("launch", entry.get("launchCommand", "")))
	var n := cpu_mhz(cmd)
	if n > 0:
		return n
	if not authentic:
		return 0
	var date := str(entry.get("releaseDate", "")).strip_edges()
	var year := 0
	if date.length() >= 4 and date.substr(0, 4).is_valid_int():
		year = int(date.substr(0, 4))
	if year <= 0:
		return 800
	if year < 1998:
		return 200
	if year < 2001:
		return 366
	if year < 2004:
		return 800
	if year < 2007:
		return 1600
	if year < 2010:
		return 2200
	return 2800


static func _first_url(s: String) -> String:
	if s.is_empty():
		return ""
	var lower := s.to_lower()
	var start := -1
	for sch in ["http://", "https://", "ftp://"]:
		var i := lower.find(sch)
		if i >= 0 and (start < 0 or i < start):
			start = i
	if start < 0:
		return ""
	if start > 0 and s[start - 1] == '"':
		var qend := s.find('"', start)
		if qend < 0:
			return s.substr(start)
		return s.substr(start, qend - start)
	var rest := s.substr(start)
	var endpos := rest.length()
	var flag := rest.find(" --")
	if flag >= 0:
		endpos = mini(endpos, flag)
	var bs := _backslash_arg_offset(rest)
	if bs >= 0:
		endpos = mini(endpos, bs)
	return rest.substr(0, endpos).strip_edges()


## ActiveX-style trailing `mjolauncher\foo.dll` is not part of the URL.
static func _backslash_arg_offset(rest: String) -> int:
	var i := 0
	while i < rest.length():
		var sp := rest.find(" ", i)
		if sp < 0:
			return -1
		var tok_start := sp + 1
		while tok_start < rest.length() and rest[tok_start] == " ":
			tok_start += 1
		var tok_end := rest.find(" ", tok_start)
		if tok_end < 0:
			tok_end = rest.length()
		var tok := rest.substr(tok_start, tok_end - tok_start)
		if tok.find("\\") >= 0 or (tok.find("/") >= 0 and tok.to_lower().ends_with(".dll")):
			return sp
		i = tok_start
	return -1


## Percent-encode path segments so Ruffle's URL parser accepts spaces.
static func encode_launch_url(url: String) -> String:
	var s := url.strip_edges()
	var scheme := ""
	if s.to_lower().begins_with("http://"):
		scheme = s.substr(0, 7)
		s = s.substr(7)
	elif s.to_lower().begins_with("https://"):
		scheme = s.substr(0, 8)
		s = s.substr(8)
	elif s.to_lower().begins_with("ftp://"):
		scheme = s.substr(0, 6)
		s = s.substr(6)
	else:
		return url
	var query := ""
	var q := s.find("?")
	if q >= 0:
		query = s.substr(q)
		s = s.substr(0, q)
	var bits := s.split("/")
	var enc: PackedStringArray = []
	for i in bits.size():
		if i == 0:
			enc.append(bits[i])
		elif bits[i].is_empty():
			enc.append(bits[i])
		else:
			enc.append(bits[i].uri_encode())
	return scheme + "/".join(enc) + query


## Host/path leftover from a Flashpoint launch command, no scheme.
static func path_from_launch(launch: String) -> String:
	var path := movie_url(launch)
	if path.is_empty():
		path = launch.strip_edges()
	if path.contains("#"):
		path = path.split("#")[0]
	if path.contains("?"):
		path = path.split("?")[0]
	if path.begins_with("http://"):
		path = path.substr(7)
	elif path.begins_with("https://"):
		path = path.substr(8)
	elif path.begins_with("ftp://"):
		path = path.substr(6)
	return path.lstrip("/")


static func content_root(dest_dir: String) -> String:
	var dest := ProjectSettings.globalize_path(dest_dir)
	var nested := dest.path_join("content")
	if DirAccess.dir_exists_absolute(nested):
		return nested
	return dest


static func rel_under(root: String, path: String) -> String:
	var a := ProjectSettings.globalize_path(root).replace("\\", "/").rstrip("/")
	var b := ProjectSettings.globalize_path(path).replace("\\", "/")
	if b.begins_with(a + "/"):
		return b.substr(a.length() + 1)
	return ""


## Exact launch path, else the extract file whose name/path best overlaps.
static func file_matching(dest_dir: String, launch: String) -> String:
	var dest := ProjectSettings.globalize_path(dest_dir)
	var path := path_from_launch(launch)
	if path.contains("?"):
		path = path.split("?")[0]
	var root := content_root(dest)
	for c in [root.path_join(path), dest.path_join(path)]:
		if FileAccess.file_exists(c):
			return c
	if path.is_empty():
		return ""
	var want := path.replace("\\", "/")
	var best := ""
	var best_score := -1
	for full in _collect_files(root):
		var rel := rel_under(root, full)
		if rel.is_empty():
			continue
		var sc := _path_score(want, rel)
		if sc < 0:
			continue
		if sc < best_score:
			continue
		if sc == best_score and not best.is_empty():
			if rel.length() >= rel_under(root, best).length():
				continue
		best_score = sc
		best = full
	return best


## Host/path under the extract that the local server should serve.
static func resolved_rel(dest_dir: String, launch: String) -> String:
	var hit := file_matching(dest_dir, launch)
	if hit.is_empty():
		return ""
	return rel_under(content_root(dest_dir), hit)


## Movie URL that maps onto a file in the extract (so relative loads stay there).
static func resolved_movie(dest_dir: String, launch: String) -> String:
	var rel := resolved_rel(dest_dir, launch)
	if not rel.is_empty():
		return "http://" + rel
	var movie := movie_url(launch)
	if movie.begins_with("https://") or movie.begins_with("ftp://"):
		return "http://" + movie.substr(movie.find("://") + 3)
	return movie


## Map a Flashpoint launch URL onto a file inside the extracted zip.
static func file_for_launch(dest_dir: String, launch: String) -> String:
	var hit := file_matching(dest_dir, launch)
	if not hit.is_empty():
		return hit
	var dest := ProjectSettings.globalize_path(dest_dir)
	var path := path_from_launch(launch)
	if path.contains("?"):
		path = path.split("?")[0]
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


static func _collect_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var fname := d.get_next()
	var nested: PackedStringArray = []
	while fname != "":
		if fname != "." and fname != "..":
			var full := dir.path_join(fname)
			if d.current_is_dir():
				nested.append(full)
			else:
				out.append(full)
		fname = d.get_next()
	d.list_dir_end()
	for sub in nested:
		out.append_array(_collect_files(sub))
	return out


static func _tokens(path: String) -> PackedStringArray:
	var raw := path.replace("\\", "/").to_lower()
	var buf := ""
	var out := PackedStringArray()
	for i in raw.length():
		var ch := raw[i]
		var alnum := (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9")
		if alnum:
			buf += ch
		else:
			if buf.length() >= 3:
				out.append(buf)
			buf = ""
	if buf.length() >= 3:
		out.append(buf)
	return out


static func _path_score(want: String, cand: String) -> int:
	var wf := want.get_file().to_lower()
	var cf := cand.get_file().to_lower()
	var score := 0
	if wf == cf:
		score += 10000
	var shared := 0
	for w in _tokens(want):
		for c in _tokens(cand):
			if w == c or w.find(c) >= 0 or c.find(w) >= 0:
				shared += 1
				break
	score += shared * 50
	if wf != cf and shared < 2:
		return -1
	if score <= 0:
		return -1
	return score


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
