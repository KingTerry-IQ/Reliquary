## Loopback static file server, plus an HTTP/FTP-style proxy Director/SPR use
## (absolute GET http://host/path via proxyServer on 127.0.0.1:port).

class_name LocalHttp
extends Node

const SPR_PORT := 22500

var port: int = 0
var last_path: String = ""
var _server := TCPServer.new()
var _root: String = ""
var _remote: String = ""


func serve(root: String, prefer: int = 18765, remote: String = "") -> int:
	stop()
	_root = ProjectSettings.globalize_path(root)
	_remote = remote.rstrip("/") + "/" if not remote.is_empty() else ""
	for p in range(prefer, prefer + 30):
		if _server.listen(p, "127.0.0.1") == OK:
			port = p
			set_process(true)
			return p
	port = 0
	return -1


func url_for(filename: String) -> String:
	var bits := filename.lstrip("/").split("/")
	var enc: PackedStringArray = []
	for b in bits:
		if not b.is_empty():
			enc.append(b.uri_encode())
	return "http://127.0.0.1:%d/%s" % [port, "/".join(enc)]


func stop() -> void:
	set_process(false)
	if _server.is_listening():
		_server.stop()
	port = 0


func _process(_dt: float) -> void:
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer:
			_serve_peer(peer)


func _serve_peer(peer: StreamPeerTCP) -> void:
	peer.poll()
	var req := PackedByteArray()
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 1500:
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			req.append_array(peer.get_data(n)[1])
			if req.get_string_from_utf8().find("\r\n\r\n") >= 0:
				break
		else:
			OS.delay_msec(2)
			peer.poll()
	var text := req.get_string_from_utf8()
	var line := text.split("\r\n")[0] if not text.is_empty() else ""
	var bits := line.split(" ")
	var method := bits[0].to_upper() if bits.size() > 0 else "GET"
	if method == "CONNECT":
		_reply(peer, 403, "text/plain", "forbidden".to_utf8_buffer(), true)
		return
	var path := target_path(text)
	last_path = path
	if path.contains(".."):
		_reply(peer, 403, "text/plain", "forbidden".to_utf8_buffer(), method == "HEAD")
		return
	var full := _root.path_join(path) if not path.is_empty() else _root
	if path.is_empty() or DirAccess.dir_exists_absolute(full):
		full = full.path_join("index.html") if not path.is_empty() else _root.path_join("index.html")
	if not FileAccess.file_exists(full) and not _remote.is_empty() and not path.is_empty():
		var fetched := _fetch_remote(path)
		if fetched.size() > 0:
			DirAccess.make_dir_recursive_absolute(full.get_base_dir())
			var out := FileAccess.open(full, FileAccess.WRITE)
			if out:
				out.store_buffer(fetched)
				out.close()
	if not FileAccess.file_exists(full):
		_reply(peer, 404, "text/plain", "not found".to_utf8_buffer(), method == "HEAD")
		return
	_reply(peer, 200, _mime(full), FileAccess.get_file_as_bytes(full), method == "HEAD")


## Map an origin-form or proxy absolute-form request onto host/path.
static func target_path(request: String) -> String:
	var line := request.split("\r\n")[0] if not request.is_empty() else ""
	var bits := line.split(" ")
	var target := bits[1].split("?")[0] if bits.size() >= 2 else "/"
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


func _reply(peer: StreamPeerTCP, code: int, mime: String, body: PackedByteArray, head_only: bool = false) -> void:
	var reason := "OK" if code == 200 else "Error"
	var head := (
		"HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\nProxy-Connection: close\r\n\r\n"
		% [code, reason, mime, body.size()]
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
	if http.request(HTTPClient.METHOD_GET, req_path, PackedStringArray(["User-Agent: FlashCartridge/0.1"])) != OK:
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


func _mime(path: String) -> String:
	var ext := path.get_extension().to_lower()
	match ext:
		"html", "htm":
			return "text/html; charset=utf-8"
		"js":
			return "application/javascript"
		"css":
			return "text/css"
		"json":
			return "application/json"
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
		"mp3":
			return "audio/mpeg"
		"ogg":
			return "audio/ogg"
		"wav":
			return "audio/wav"
		"mp4":
			return "video/mp4"
		"wasm":
			return "application/wasm"
		"swf":
			return "application/x-shockwave-flash"
		"dcr", "dir", "dxr", "cct", "cst", "cxt":
			return "application/x-director"
		"w3d", "fgd":
			return "application/octet-stream"
		_:
			return "application/octet-stream"
