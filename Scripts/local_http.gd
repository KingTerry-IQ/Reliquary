## Loopback static file server, plus an HTTP/FTP-style proxy Director/SPR use
## (absolute GET http://host/path via proxyServer on 127.0.0.1:port).

class_name LocalHttp
extends Node

const SPR_PORT := 22500
## ShiVa SecurePlayer rewrites http://host to http://localhost:22600/host
const PLUGIN_PORT := 22600

const HIT_LOG_MAX := 400

var port: int = 0
var last_path: String = ""
## What the player actually asked us for. The soak harness reads these to tell
## "the runtime opened the movie" from "the runtime opened and sat there".
var hits: PackedStringArray = []
var misses: PackedStringArray = []
var _server := TCPServer.new()
var _root: String = ""
var _remote: String = ""
var _ruffle_web: String = ""
var _rewrite_hosts: bool = true
## Directory of the last file we actually served (linked Director casts).
var _last_ok_dir: String = ""


func serve(
	root: String,
	prefer: int = 18765,
	remote: String = "",
	ruffle_web: String = "",
	rewrite_hosts: bool = true
) -> int:
	stop()
	_root = ProjectSettings.globalize_path(root)
	_remote = remote.rstrip("/") + "/" if not remote.is_empty() else ""
	_ruffle_web = ProjectSettings.globalize_path(ruffle_web) if not ruffle_web.is_empty() else ""
	_rewrite_hosts = rewrite_hosts
	_last_ok_dir = ""
	hits = PackedStringArray()
	misses = PackedStringArray()
	for p in range(prefer, prefer + 30):
		if _server.listen(p, "127.0.0.1") == OK:
			port = p
			set_process(true)
			return p
	port = 0
	return -1


## `__ruffle/ruffle.js` even when the request is host-mapped.
static func ruffle_asset_rel(path: String) -> String:
	var p := path.replace("\\", "/")
	var needle := "__ruffle/"
	var i := p.find(needle)
	if i >= 0:
		return p.substr(i + needle.length())
	if p.begins_with("__ruffle"):
		return p.substr(8).lstrip("/")
	return ""


## Map archived http(s)://host/path onto this origin so fetch/XHR stay same-origin.
static func rewrite_absolute_urls(html: String) -> String:
	var re := RegEx.new()
	if re.compile("https?://([^/\\s\"'<>]+)(/[^\\s\"'<>]*)?") != OK:
		return html
	var out := html
	var seen := {}
	for m in re.search_all(html):
		var full := m.get_string()
		if seen.has(full):
			continue
		seen[full] = true
		var host := m.get_string(1).to_lower()
		if host.begins_with("127.0.0.1") or host.begins_with("localhost"):
			continue
		var path := m.get_string(2)
		out = out.replace(full, "/" + m.get_string(1) + path)
	return out


const CARTRIDGE_JS := """<script>
(function(){
if(window.__reliquaryRewrite)return;window.__reliquaryRewrite=1;
function map(u){
if(!u||typeof u!=="string")return u;
if(u.charAt(0)==="/"||u.indexOf("data:")===0||u.indexOf("blob:")===0)return u;
try{
var x=new URL(u,location.href);
if(x.protocol!=="http:"&&x.protocol!=="https:")return u;
if(x.hostname==="127.0.0.1"||x.hostname==="localhost")return u;
return location.origin+"/"+x.host+x.pathname+x.search+x.hash;
}catch(e){return u;}
}
if(window.fetch){var f=window.fetch;window.fetch=function(i,n){
if(typeof i==="string")i=map(i);
else if(i&&i.url)i=new Request(map(i.url),i);
return f.call(this,i,n);};}
var xo=XMLHttpRequest.prototype.open;
XMLHttpRequest.prototype.open=function(m,u){if(typeof u==="string")arguments[1]=map(u);return xo.apply(this,arguments);};
if(window.Worker){var W=window.Worker;window.Worker=function(u,o){return new W(typeof u==="string"?map(u):u,o);};window.Worker.prototype=W.prototype;}
var sa=Element.prototype.setAttribute;
Element.prototype.setAttribute=function(n,v){
var k=String(n).toLowerCase();
if((k==="src"||k==="href"||k==="data")&&typeof v==="string")v=map(v);
return sa.call(this,n,v);};
})();
</script>
"""


static func inject_cartridge_html(html: String) -> String:
	if html.find("__reliquaryRewrite") >= 0:
		return html
	var lower := html.to_lower()
	var i := lower.find("<head>")
	if i >= 0:
		return html.substr(0, i + 6) + CARTRIDGE_JS + html.substr(i + 6)
	i = lower.find("<head ")
	if i >= 0:
		var gt := html.find(">", i)
		if gt >= 0:
			return html.substr(0, gt + 1) + CARTRIDGE_JS + html.substr(gt + 1)
	i = lower.find("<html")
	if i >= 0:
		var gt2 := html.find(">", i)
		if gt2 >= 0:
			return html.substr(0, gt2 + 1) + CARTRIDGE_JS + html.substr(gt2 + 1)
	return CARTRIDGE_JS + html


static func inject_ruffle_html(html: String) -> String:
	if html.find("ruffle.js") >= 0:
		return html
	var snippet := '<script src="/__ruffle/ruffle.js"></script>\n'
	var lower := html.to_lower()
	var i := lower.find("</head>")
	if i < 0:
		i = lower.find("</body>")
	if i >= 0:
		return html.substr(0, i) + snippet + html.substr(i)
	return snippet + html


static func browser_exe() -> String:
	var cands := PackedStringArray()
	var osn := OS.get_name()
	if osn == "Windows":
		var pf := OS.get_environment("ProgramFiles").replace("\\", "/")
		var pf86 := OS.get_environment("ProgramFiles(x86)").replace("\\", "/")
		var local := OS.get_environment("LOCALAPPDATA").replace("\\", "/")
		cands = PackedStringArray([
			pf.path_join("Microsoft/Edge/Application/msedge.exe"),
			pf86.path_join("Microsoft/Edge/Application/msedge.exe"),
			pf.path_join("Google/Chrome/Application/chrome.exe"),
			pf86.path_join("Google/Chrome/Application/chrome.exe"),
			local.path_join("Google/Chrome/Application/chrome.exe"),
		])
	elif osn == "macOS":
		cands = PackedStringArray([
			"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
			"/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
		])
	else:
		cands = PackedStringArray(["google-chrome", "chromium", "microsoft-edge", "chromium-browser"])
	for p in cands:
		if p.is_empty():
			continue
		if FileAccess.file_exists(p) or FileAccess.file_exists(p + ".exe"):
			return p
	return ""


static func browser_launch_args(url: String, proxy_port: int, profile: String) -> PackedStringArray:
	return PackedStringArray([
		"--proxy-server=http=127.0.0.1:%d;https=direct://" % proxy_port,
		"--proxy-bypass-list=*.google.com;*.gstatic.com;*.googleapis.com;localhost;127.0.0.1",
		"--user-data-dir=%s" % profile,
		"--no-first-run",
		"--no-default-browser-check",
		"--disable-sync",
		"--disable-background-networking",
		"--disable-features=HttpsUpgrades,HttpsFirstBalancedModeAutoEnable,CaptivePortal",
		"--allow-running-insecure-content",
		url,
	])


func open_proxied(url: String) -> int:
	var exe := browser_exe()
	if exe.is_empty() or port <= 0:
		return -1
	var profile := ProjectSettings.globalize_path("user://bin/browser-profile")
	DirAccess.make_dir_recursive_absolute(profile)
	var args := browser_launch_args(url, port, profile)
	return OS.create_process(exe, args, false)


func url_for(filename: String, loopback: String = "127.0.0.1") -> String:
	var bits := filename.lstrip("/").split("/")
	var enc: PackedStringArray = []
	for b in bits:
		if not b.is_empty():
			enc.append(b.uri_encode())
	var host := loopback if not loopback.is_empty() else "127.0.0.1"
	return "http://%s:%d/%s" % [host, port, "/".join(enc)]


func stop() -> void:
	set_process(false)
	if _server.is_listening():
		_server.stop()
	port = 0
	_last_ok_dir = ""


func _process(_dt: float) -> void:
	if not _server.is_listening():
		return
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer:
			_serve_peer(peer)


func _peer_connected(peer: StreamPeerTCP) -> bool:
	peer.poll()
	return peer.get_status() == StreamPeerTCP.STATUS_CONNECTED


func _serve_peer(peer: StreamPeerTCP) -> void:
	var req := PackedByteArray()
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 1500:
		if not _peer_connected(peer):
			return
		var n := peer.get_available_bytes()
		if n < 0:
			peer.disconnect_from_host()
			return
		if n > 0:
			req.append_array(peer.get_data(n)[1])
			if req.get_string_from_utf8().find("\r\n\r\n") >= 0:
				break
		else:
			OS.delay_msec(2)
	if req.get_string_from_utf8().find("\r\n\r\n") < 0:
		peer.disconnect_from_host()
		return
	var text := req.get_string_from_utf8()
	var line := text.split("\r\n")[0] if not text.is_empty() else ""
	var method := line.split(" ")[0].to_upper() if not line.is_empty() else "GET"
	if method == "CONNECT":
		_reply(peer, 403, "text/plain", "forbidden".to_utf8_buffer(), true, text)
		return
	if method == "OPTIONS":
		_reply(peer, 204, "text/plain", PackedByteArray(), true, text)
		return
	var path := target_path(text)
	last_path = path
	if path.contains(".."):
		_reply(peer, 403, "text/plain", "forbidden".to_utf8_buffer(), method == "HEAD", text)
		return
	var ruffle_rel := ruffle_asset_rel(path)
	if not ruffle_rel.is_empty() and not _ruffle_web.is_empty():
		var rf := _ruffle_web.path_join(ruffle_rel)
		if not FileAccess.file_exists(rf):
			rf = _find_in(_ruffle_web, ruffle_rel.get_file())
		if FileAccess.file_exists(rf):
			_reply(peer, 200, _mime(rf), FileAccess.get_file_as_bytes(rf), method == "HEAD", text, FileAccess.get_modified_time(rf))
			return
	var full := file_in_tree(_root, path, _last_ok_dir)
	if full.is_empty():
		var as_dir := _root.path_join(path) if not path.is_empty() else _root
		if path.is_empty() or DirAccess.dir_exists_absolute(as_dir):
			full = index_file(as_dir if not path.is_empty() else _root)
	if (
		full.is_empty()
		and not _remote.is_empty()
		and not path.is_empty()
		and not is_filesystem_rel(path)
	):
		var dest := _root.path_join(path)
		var fetched := _fetch_remote(path)
		if fetched.size() > 0:
			DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
			var out := FileAccess.open(dest, FileAccess.WRITE)
			if out:
				out.store_buffer(fetched)
				out.close()
			if FileAccess.file_exists(dest):
				full = dest
	if full.is_empty() or not FileAccess.file_exists(full):
		var policy := policy_body(path)
		if not policy.is_empty():
			_reply(peer, 200, "text/xml", policy.to_utf8_buffer(), method == "HEAD", text)
			return
		_note(misses, path)
		_reply(peer, 404, "text/plain", "not found".to_utf8_buffer(), method == "HEAD", text)
		return
	_note(hits, path)
	_last_ok_dir = full.get_base_dir()
	var body := FileAccess.get_file_as_bytes(full)
	var mime := mime_for_body(full, body)
	if mime.begins_with("text/html"):
		var html := body.get_string_from_utf8()
		if _rewrite_hosts:
			html = rewrite_absolute_urls(html)
			html = inject_cartridge_html(html)
		if not _ruffle_web.is_empty():
			html = inject_ruffle_html(html)
		body = html.to_utf8_buffer()
	_reply(peer, 200, mime, body, method == "HEAD", text, FileAccess.get_modified_time(full))


static func _note(into: PackedStringArray, path: String) -> void:
	if path.is_empty() or into.has(path):
		return
	if into.size() >= HIT_LOG_MAX:
		return
	into.append(path)


func served(path: String) -> bool:
	return hits.has(path)


## Request-line target (METHOD may be followed by a URL that contains spaces).
static func request_target(line: String) -> String:
	var s := line.strip_edges()
	if s.is_empty():
		return "/"
	var sp := s.find(" ")
	if sp < 0:
		return "/"
	var rest := s.substr(sp + 1).strip_edges()
	var http := rest.rfind(" HTTP/")
	if http >= 0:
		return rest.substr(0, http).strip_edges()
	return rest.split(" ")[0] if not rest.is_empty() else "/"


## Map an origin-form or proxy absolute-form request onto host/path.
static func target_path(request: String) -> String:
	var line := request.split("\r\n")[0] if not request.is_empty() else ""
	var target := request_target(line).split("?")[0]
	var host := ""
	var path := ""
	if target.begins_with("http://") or target.begins_with("https://") or target.begins_with("ftp://"):
		var rest := target.substr(target.find("://") + 3)
		var slash := rest.find("/")
		if slash == -1:
			host = rest
			path = ""
		else:
			host = rest.substr(0, slash)
			path = rest.substr(slash + 1)
		if host.contains(":"):
			host = host.split(":")[0]
	else:
		path = target
		for hdr in request.split("\r\n"):
			if hdr.to_lower().begins_with("host:"):
				var hv := hdr.substr(5).strip_edges()
				if hv.contains(":") and not hv.begins_with("["):
					host = hv.split(":")[0]
				else:
					host = hv
				break
	host = host.strip_edges()
	path = path.uri_decode().replace("\\", "/")
	while path.begins_with("/"):
		path = path.substr(1)
	if host.is_empty() or host == "127.0.0.1" or host.to_lower() == "localhost":
		return path
	return host + "/" + path if not path.is_empty() else host


## Echo the request's HTTP version. Shockwave's NetLingo is HTTP/1.0.
static func http_version(request: String) -> String:
	var line := request.split("\r\n")[0] if not request.is_empty() else ""
	var i := line.rfind(" HTTP/")
	if i < 0:
		return "HTTP/1.1"
	var ver := line.substr(i + 1).strip_edges()
	if ver.begins_with("HTTP/1.0"):
		return "HTTP/1.0"
	return "HTTP/1.1"


## RFC 1123 date. Shockwave requires Last-Modified on Director files.
static func http_date(unix: int) -> String:
	if unix <= 0:
		unix = int(Time.get_unix_time_from_system())
	var d := Time.get_datetime_dict_from_unix_time(unix)
	var wdays := PackedStringArray(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
	var months := PackedStringArray([
		"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
	])
	var wd := int(d.get("weekday", (unix / 86400 + 4) % 7))
	var mo := int(d.get("month", 1))
	if wd < 0 or wd > 6:
		wd = int((unix / 86400 + 4) % 7)
	if mo < 1 or mo > 12:
		mo = 1
	return "%s, %02d %s %04d %02d:%02d:%02d GMT" % [
		wdays[wd],
		int(d.get("day", 1)),
		months[mo - 1],
		int(d.get("year", 1970)),
		int(d.get("hour", 0)),
		int(d.get("minute", 0)),
		int(d.get("second", 0)),
	]


## Published/unpublished Director extensions live next to each other.
static func director_alt_rel(path: String) -> String:
	var ext := path.get_extension().to_lower()
	var stem := path.get_basename()
	match ext:
		"cst", "cxt":
			return stem + ".cct"
		"cct":
			return stem + ".cst"
		"dir", "dxr":
			return stem + ".dcr"
		"dcr":
			return stem + ".dir"
		_:
			return ""


## Other published/unpublished pairs old runtimes request.
static func alt_rels(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := director_alt_rel(path)
	if not d.is_empty():
		out.append(d)
	var ext := path.get_extension().to_lower()
	var stem := path.get_basename()
	match ext:
		"htm":
			out.append(stem + ".html")
		"html":
			out.append(stem + ".htm")
		"jpg":
			out.append(stem + ".jpeg")
		"jpeg":
			out.append(stem + ".jpg")
	return out


## html/htm first, the way Flashpoint's router orders them, then the server-page
## names an archived site kept as its directory index.
const INDEX_NAMES: PackedStringArray = [
	"index.html",
	"index.htm",
	"default.html",
	"default.htm",
	"index.php",
	"index.php5",
	"index.phtml",
	"index.jsp",
	"index.asp",
	"index.aspx",
	"index.shtml",
	"index.cgi",
	"default.asp",
	"default.aspx",
]


static func index_file(dir: String) -> String:
	if dir.is_empty() or not DirAccess.dir_exists_absolute(dir):
		return ""
	for n in INDEX_NAMES:
		var p := dir.path_join(n)
		if FileAccess.file_exists(p):
			return p
	return ""


static func www_fold_rel(path: String) -> String:
	var rel := path.replace("\\", "/")
	while rel.begins_with("/"):
		rel = rel.substr(1)
	var slash := rel.find("/")
	var host := rel if slash < 0 else rel.substr(0, slash)
	var rest := "" if slash < 0 else rel.substr(slash)
	var h := host.to_lower()
	if h.begins_with("www.") and h.length() > 4:
		return host.substr(4) + rest
	if h.find(".") >= 0 and not h.begins_with("www."):
		return "www." + host + rest
	return ""


## Flash / Silverlight sandbox policy when the zip has no copy.
static func policy_body(path: String) -> String:
	var name := path.get_file().to_lower()
	if name == "crossdomain.xml":
		return "<?xml version=\"1.0\"?>\n<cross-domain-policy>\n<allow-access-from domain=\"*\"/>\n</cross-domain-policy>\n"
	if name == "clientaccesspolicy.xml":
		return "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<access-policy><cross-domain-access><policy><allow-from http-request-headers=\"*\"><domain uri=\"*\"/></allow-from><grant-to><resource path=\"/\" include-subpaths=\"true\"/></grant-to></policy></cross-domain-access></access-policy>\n"
	return ""


## Absolute Windows/UNC path that leaked through as a request target.
static func is_filesystem_rel(path: String) -> bool:
	var p := path.replace("\\", "/").lstrip("/")
	if p.length() >= 2:
		var drive := p[0]
		var letter := (drive >= "A" and drive <= "Z") or (drive >= "a" and drive <= "z")
		if letter and p[1] == ":":
			return true
	return p.begins_with("//")


## Exact extract path, else Director extension fold, else next to the last hit.
static func file_in_tree(root: String, path: String, hint_dir: String = "") -> String:
	var dest := ProjectSettings.globalize_path(root)
	var rel := path.replace("\\", "/")
	while rel.begins_with("/"):
		rel = rel.substr(1)
	var full := dest.path_join(rel) if not rel.is_empty() else dest
	if FileAccess.file_exists(full):
		return full
	for alt in alt_rels(full):
		if FileAccess.file_exists(alt):
			return alt
	var folded := www_fold_rel(rel)
	if not folded.is_empty():
		var fold_full := dest.path_join(folded)
		if FileAccess.file_exists(fold_full):
			return fold_full
		for alt in alt_rels(fold_full):
			if FileAccess.file_exists(alt):
				return alt
	var fname := rel.get_file()
	if fname.is_empty():
		return ""
	var hint := ProjectSettings.globalize_path(hint_dir) if not hint_dir.is_empty() else ""
	if not hint.is_empty():
		var sib := hint.path_join(fname)
		if FileAccess.file_exists(sib):
			return sib
		for salt in alt_rels(sib):
			if FileAccess.file_exists(salt):
				return salt
	if is_filesystem_rel(rel):
		var hit := _find_in(dest, fname)
		if not hit.is_empty() and FileAccess.file_exists(hit):
			return hit
		var altf := director_alt_rel(fname)
		if not altf.is_empty():
			hit = _find_in(dest, altf)
			if not hit.is_empty() and FileAccess.file_exists(hit):
				return hit
	return ""


func _cors_origin(request: String) -> String:
	for hdr in request.split("\r\n"):
		if hdr.to_lower().begins_with("origin:"):
			var o := hdr.substr(7).strip_edges()
			if not o.is_empty():
				return o
	return "*"


func _reply(
	peer: StreamPeerTCP,
	code: int,
	mime: String,
	body: PackedByteArray,
	head_only: bool = false,
	request: String = "",
	last_modified: int = 0
) -> void:
	var reason := "OK"
	if code == 204:
		reason = "No Content"
	elif code == 403:
		reason = "Forbidden"
	elif code == 404:
		reason = "Not Found"
	elif code != 200:
		reason = "Error"
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var origin := _cors_origin(request)
	var cred := "" if origin == "*" else "Access-Control-Allow-Credentials: true\r\n"
	var lm := ""
	if last_modified > 0:
		lm = "Last-Modified: %s\r\n" % http_date(last_modified)
	## Shockwave NetLingo wants the request's HTTP version, Last-Modified, and
	## no extra hop-by-hop/CORP headers ("not a valid Director file").
	var head := (
		"%s %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\n%sAccess-Control-Allow-Origin: %s\r\nAccess-Control-Allow-Methods: GET, HEAD, POST, OPTIONS\r\nAccess-Control-Allow-Headers: *\r\n%s\r\n"
		% [http_version(request), code, reason, mime, body.size(), lm, origin, cred]
	)
	peer.put_data(head.to_utf8_buffer())
	if not head_only:
		peer.put_data(body)
	peer.disconnect_from_host()


func _fetch_remote(rel: String) -> PackedByteArray:
	var bits := rel.split("/")
	var enc: PackedStringArray = []
	for b in bits:
		if not b.is_empty():
			enc.append(b.uri_encode())
	var url := _remote + "/".join(enc)
	var http := HTTPClient.new()
	var host := url.get_slice("://", 1).get_slice("/", 0)
	var tls := url.begins_with("https://")
	if http.connect_to_host(host, 443 if tls else 80, TLSOptions.client() if tls else null) != OK:
		return PackedByteArray()
	var start := Time.get_ticks_msec()
	while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
		if Time.get_ticks_msec() - start > 8000:
			return PackedByteArray()
		http.poll()
		OS.delay_msec(10)
	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		return PackedByteArray()
	var req_path := "/" + url.get_slice("://", 1).get_slice("/", 1)
	if url.find("/", url.find("://") + 3) >= 0:
		req_path = url.substr(url.find("/", url.find("://") + 3))
	if http.request(HTTPClient.METHOD_GET, req_path, PackedStringArray(["User-Agent: Reliquary/0.1"])) != OK:
		return PackedByteArray()
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		if Time.get_ticks_msec() - start > 15000:
			return PackedByteArray()
		http.poll()
		OS.delay_msec(10)
	if http.get_response_code() != 200:
		return PackedByteArray()
	var body := PackedByteArray()
	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()
		var chunk := http.read_response_body_chunk()
		if chunk.size() == 0:
			OS.delay_msec(5)
		else:
			body.append_array(chunk)
		if Time.get_ticks_msec() - start > 30000:
			break
	return body


static func _find_in(dir: String, filename: String) -> String:
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
		var hit := _find_in(sub, filename)
		if not hit.is_empty():
			return hit
	return ""


static func mime_for(path: String) -> String:
	return _mime_of(path)


func _mime(path: String) -> String:
	return _mime_of(path)


## Archived launch targets are often a page with no extension (`/2048`) or a
## server-page one (`index.jsp`). Flashpoint's router calls both
## application/octet-stream and leans on Navigator to render them regardless;
## Chromium downloads them instead. So when the name tells us nothing, read the
## first bytes and say what the file actually is.
static func mime_for_body(path: String, body: PackedByteArray) -> String:
	var named := _mime_of(path)
	if named != "application/octet-stream":
		return named
	var sniffed := sniff_mime(body)
	return sniffed if not sniffed.is_empty() else named


const HTML_OPENERS: PackedStringArray = [
	"<!doctype html",
	"<html",
	"<head",
	"<body",
	"<frameset",
	"<title",
	"<meta",
	"<script",
]


static func sniff_mime(body: PackedByteArray) -> String:
	if body.size() < 4:
		return ""
	if body[0] == 0x89 and body[1] == 0x50 and body[2] == 0x4E and body[3] == 0x47:
		return "image/png"
	if body[0] == 0x47 and body[1] == 0x49 and body[2] == 0x46:
		return "image/gif"
	if body[0] == 0xFF and body[1] == 0xD8 and body[2] == 0xFF:
		return "image/jpeg"
	var tag := PackedByteArray([body[0], body[1], body[2]]).get_string_from_ascii()
	if (tag == "FWS" or tag == "CWS" or tag == "ZWS") and body[3] < 64:
		return "application/x-shockwave-flash"
	if _looks_like_html(body):
		return "text/html"
	return ""


## Leading whitespace, a BOM and an HTML comment or doctype all come before the
## first real tag, so skip past them before deciding.
static func _looks_like_html(body: PackedByteArray) -> bool:
	var head := body.slice(0, mini(body.size(), 1024))
	var text := head.get_string_from_utf8()
	if text.is_empty():
		text = head.get_string_from_ascii()
	text = text.strip_edges().lstrip("﻿").strip_edges().to_lower()
	if text.is_empty():
		return false
	if text.begins_with("<?php") or text.begins_with("<%"):
		return true
	while text.begins_with("<!--"):
		var end := text.find("-->")
		if end < 0:
			return false
		text = text.substr(end + 3).strip_edges()
	if text.begins_with("<?xml"):
		var gt := text.find("?>")
		if gt < 0:
			return false
		text = text.substr(gt + 2).strip_edges()
	for opener in HTML_OPENERS:
		if text.begins_with(opener):
			return true
	return false


static func _mime_of(path: String) -> String:
	var ext := path.get_extension().to_lower()
	match ext:
		"html", "htm":
			return "text/html"
		"js":
			return "text/javascript"
		"css":
			return "text/css"
		"json":
			return "application/json"
		"xml":
			return "text/xml"
		"txt":
			return "text/plain"
		"png":
			return "image/png"
		"jpg", "jpeg":
			return "image/jpeg"
		"gif":
			return "image/gif"
		"webp":
			return "image/webp"
		"svg":
			return "image/svg+xml"
		"bmp":
			return "image/bmp"
		"ico":
			return "image/x-icon"
		"mp3":
			return "audio/mpeg"
		"ogg":
			return "audio/ogg"
		"wav":
			return "audio/wav"
		"mid", "midi":
			return "audio/midi"
		"mp4":
			return "video/mp4"
		"wasm":
			return "application/wasm"
		"swf", "spl", "swt":
			return "application/x-shockwave-flash"
		"dcr", "dir", "dxr", "cct", "cst", "cxt", "swa", "w3d", "fgd":
			return "application/x-director"
		"aam", "aas", "aab":
			return "application/x-authorware-map"
		"class":
			return "application/java"
		"jar":
			return "application/java-archive"
		"jnlp":
			return "application/x-java-jnlp-file"
		"xap":
			return "application/x-silverlight-app"
		"unity3d":
			return "application/vnd.unity"
		"cmo", "vmo", "nmo", "nms":
			return "application/x-virtools"
		"cnc":
			return "application/x-cnc"
		"pwc":
			return "application/x-pulse-player"
		"pwn":
			return "application/x-pulse-download"
		"pw3":
			return "application/x-pulse-player-32"
		"pws":
			return "application/x-pulse-stream"
		"wrl", "wrz":
			return "model/vrml"
		"vrt":
			return "x-world/x-vrt"
		"svr":
			return "x-world/x-svr"
		"xvr":
			return "x-world/x-xvr"
		_:
			return "application/octet-stream"
