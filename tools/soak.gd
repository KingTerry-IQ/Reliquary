extends SceneTree

## Launch archive titles one at a time and record whether each one actually
## starts, deleting every download afterwards so the disk never fills.
##
##   Godot --headless --path . --script res://tools/soak.gd -- --limit 25
##
## Options (all optional):
##   --limit N        how many titles to try            (default 25)
##   --platform NAME  Flash, HTML5, Shockwave, …        (default Flash)
##   --library NAME   arcade or theatre                 (default arcade)
##   --query TEXT     extra smart-search terms
##   --seed N         pick a different random sample    (default 1)
##   --dwell S        seconds to let each title settle  (default 12)
##   --extreme        include what the tag filters hide (default: excluded)
##   --keep           do not delete the downloads
##   --out PATH       CSV report (default user://soak-report.csv)
##   --ids A,B,C      test exactly these uuids, skipping the sample
##   --net-timeout S  give up on a stalled download     (default 240)
##
## Verdicts, and exactly what each one is evidence of:
##
##   STARTED    the player fetched the launch file from us, its own process is
##              still alive, it has a visible window, and nothing 404'd
##   DEGRADED   all of the above, but assets were missing — the page or movie
##              is up and incomplete
##   ERROR-PAGE alive with a window, but the window is the runtime telling us
##              it could not load (Gecko's "Problem loading page" and friends)
##   NO-WINDOW  alive, fetched the movie, never opened a window — a runtime
##              that loaded and then died on its own
##   NO-FETCH   never asked us for the launch file. Whatever it is showing,
##              it is not this game
##   EXITED     fetched the movie, then the process went away
##   STUCK      a previous title's player would not close, so this one never
##              got a fair run
##
## None of this proves a game is *playable* — only a human or a pixel check can
## say that. It proves the launch path worked end to end, which is the part we
## can get wrong.

const DWELL_DEFAULT := 12.0
## How long the server must go untouched before we call the launch settled.
const QUIET_MS := 15000

var _limit := 25
var _platform := "Flash"
var _library := "arcade"
var _query := ""
var _seed := 1
var _dwell := DWELL_DEFAULT
var _extreme := false
var _keep := false
var _out := "user://soak-report.csv"
var _ids := PackedStringArray()
## A stalled download would hang the whole run, so the harness caps it.
var _net_timeout := 240.0

var flashpoint: Flashpoint
var httpd: LocalHttp
var ruffle: Ruffle
var flash: Flash
var spr: Spr
var packs: Packs
var tag_filter := TagFilter.new()

var _rows: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_parse_args()
	flashpoint = Flashpoint.new()
	root.add_child(flashpoint)
	httpd = LocalHttp.new()
	root.add_child(httpd)
	ruffle = Ruffle.new()
	root.add_child(ruffle)
	flash = Flash.new()
	root.add_child(flash)
	spr = Spr.new()
	root.add_child(spr)
	packs = Packs.new()
	root.add_child(packs)
	root.add_child(tag_filter)
	await process_frame

	print("soak: platform=%s library=%s limit=%d dwell=%.0fs extreme=%s" % [
		_platform, _library, _limit, _dwell, _extreme
	])
	if not _extreme:
		await tag_filter.ensure()
		print("      hiding: ", ", ".join(tag_filter.active_names()))

	var pool := await _pick()
	if pool.is_empty():
		print("soak: nothing to test (", flashpoint.last_error, ")")
		quit(1)
		return
	print("soak: %d titles selected\n" % pool.size())

	var n := 0
	for entry: Variant in pool:
		n += 1
		var rec: Dictionary = entry
		print("[%d/%d] %s" % [n, pool.size(), str(rec.get("title", "?"))])
		var row := await _try_one(rec)
		_rows.append(row)
		print("        %s  %s" % [str(row["verdict"]), str(row["detail"])])
		_write_report()
	_summary()
	quit(0)


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := str(args[i])
		var next := str(args[i + 1]) if i + 1 < args.size() else ""
		match a:
			"--limit":
				_limit = maxi(1, int(next))
				i += 1
			"--platform":
				_platform = next
				i += 1
			"--library":
				_library = next
				i += 1
			"--query":
				_query = next
				i += 1
			"--seed":
				_seed = int(next)
				i += 1
			"--dwell":
				_dwell = maxf(2.0, float(next))
				i += 1
			"--out":
				_out = next
				i += 1
			"--ids":
				_ids = PackedStringArray(next.split(","))
				i += 1
			"--extreme":
				_extreme = true
			"--net-timeout":
				_net_timeout = maxf(30.0, float(next))
				i += 1
			"--keep":
				_keep = true
		i += 1


## A deterministic spread across the catalog rather than the first N titles,
## which would all share a publisher and tell us very little.
func _pick() -> Array:
	## Named titles bypass sampling entirely — the way to re-check a known
	## failure after a fix.
	if not _ids.is_empty():
		print("soak: looking up %d named titles…" % _ids.size())
		return await flashpoint.search_ids(_ids)
	print("soak: fetching the catalog…")
	var rows: Array = await flashpoint.search(
		_query, _library, 0, _platform, false, Flashpoint.LIST_FIELDS
	)
	if rows.is_empty():
		return []
	print("      %d in the catalog" % rows.size())
	if not _extreme:
		var before := rows.size()
		rows = tag_filter.apply(rows)
		print("      %d hidden by tag filters" % (before - rows.size()))
	var playable: Array = []
	for entry: Variant in rows:
		if entry is Dictionary and flashpoint.playable_here(entry):
			playable.append(entry)
	print("      %d playable here" % playable.size())
	if playable.size() <= _limit:
		return playable
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var picked: Array = []
	var taken := {}
	while picked.size() < _limit and taken.size() < playable.size():
		var idx := rng.randi_range(0, playable.size() - 1)
		if taken.has(idx):
			continue
		taken[idx] = true
		picked.append(playable[idx])
	return picked


func _try_one(rec: Dictionary) -> Dictionary:
	var uuid := str(rec.get("id", ""))
	var launch := Flashpoint.launch_of(rec)
	var row := {
		"id": uuid,
		"title": str(rec.get("title", "")),
		"platform": str(rec.get("platform", "")),
		"app": str(rec.get("applicationPath", "")),
		"route": "",
		"verdict": "FAIL",
		"detail": "",
		"served": 0,
		"missing": 0,
		"window": "",
	}
	var dest := "user://soak/%s" % uuid
	var zip := "user://soak/%s.zip" % uuid
	var pid := -1
	## Never inherit the previous title's leftovers: a stuck player makes the
	## next one look broken when it is only being blocked.
	if not await _reap():
		row["verdict"] = "STUCK"
		row["detail"] = "a previous player would not close: %s" % ", ".join(_running())
		return row
	if flashpoint.is_gamezip(rec):
		if not await flashpoint.download_zip(uuid, zip, Callable(), _net_timeout):
			row["detail"] = "download: %s" % flashpoint.last_error
			_cleanup(dest, zip)
			return row
		if not Unzip.extract(zip, dest):
			row["detail"] = "could not extract the GameZIP"
			_cleanup(dest, zip)
			return row
	else:
		if (await flashpoint.fetch_legacy(launch, dest, Callable(), _net_timeout)).is_empty():
			row["detail"] = "legacy: %s" % flashpoint.last_error
			_cleanup(dest, zip)
			return row

	var serve_root := Unzip.content_root(dest)
	var rel := Unzip.resolved_rel(dest, launch)
	if rel.is_empty():
		rel = Unzip.path_from_launch(launch)
	row["route"] = _route_of(rec)
	pid = await _launch(rec, dest, serve_root, launch, row)
	if pid == -1:
		if str(row["detail"]).is_empty():
			row["detail"] = "the player did not start"
		await _reap()
		httpd.stop()
		_cleanup(dest, zip)
		return row

	## Watch until the traffic goes quiet, not until it starts. Secure Player
	## downloads the movie itself before it ever launches the browser, so the
	## first request can arrive long before the player is up — cutting the
	## window short there scores a working title as dead.
	var start := Time.get_ticks_msec()
	var budget := int(_dwell * 1000.0)
	var seen_count := 0
	var last_hit := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < budget:
		httpd._process(0.0)
		await process_frame
		var total := httpd.hits.size() + httpd.misses.size()
		if total != seen_count:
			seen_count = total
			last_hit = Time.get_ticks_msec()
		elif seen_count > 0 and Time.get_ticks_msec() - last_hit > QUIET_MS:
			break
	row["served"] = httpd.hits.size()
	row["missing"] = httpd.misses.size()

	## Evidence, in order of how much it actually proves. "A player process
	## exists" proves the least — a crashed runtime and an error page both
	## satisfy it — so it is never enough on its own.
	## The tracked pid is OldCPUSimulator when a title is throttled, and that
	## wrapper can exit while the player it started keeps running. Since the
	## machine was reaped clean before this title, any player process now is
	## this title's, so the name check is sound here and the pid check is not.
	var real_pid := Spr.launch_pid()
	if real_pid <= 0:
		real_pid = pid
	var by_pid := real_pid > 0 and OS.is_process_running(real_pid)
	var still := _running()
	var alive := by_pid or not still.is_empty()
	var windowed := Spr.player_ready()
	var title := _player_window_title()
	row["window"] = title
	var got_movie := httpd.served(rel)

	if not got_movie:
		row["verdict"] = "NO-FETCH"
		row["detail"] = (
			"never asked for %s (%d other requests)" % [rel, httpd.hits.size()]
			if httpd.hits.size() > 0
			else "never asked us for anything"
		)
	elif not alive:
		row["verdict"] = "EXITED"
		row["detail"] = "fetched the movie then quit (%d served)" % httpd.hits.size()
	elif _is_error_page(title):
		row["verdict"] = "ERROR-PAGE"
		row["detail"] = "player is showing an error: %s" % title
	elif not windowed:
		row["verdict"] = "NO-WINDOW"
		row["detail"] = "running but never opened a visible window"
	elif _real_misses(httpd.misses).size() > 0:
		row["verdict"] = "DEGRADED"
		var real := _real_misses(httpd.misses)
		row["detail"] = "started, but %d assets 404: %s" % [
			real.size(), ", ".join(_first(real, 3))
		]
	else:
		row["verdict"] = "STARTED"
		row["detail"] = "%d served, window %s" % [
			httpd.hits.size(), "\"%s\"" % title if not title.is_empty() else "open"
		]
	await _reap(pid)
	httpd.stop()
	_cleanup(dest, zip)
	return row


func _route_of(rec: Dictionary) -> String:
	if FlashpointHost.needs_shockwave(rec):
		return "spr"
	if FlashpointHost.needs_flashpoint(rec):
		return "navigator"
	if Flash.projector_entry(rec):
		return "flash"
	return "page"


func _launch(
	rec: Dictionary, dest: String, serve_root: String, launch: String, row: Dictionary
) -> int:
	match str(row["route"]):
		"spr":
			if not await spr.ensure():
				row["detail"] = spr.last_error
				return -1
			var port := httpd.serve(serve_root, LocalHttp.SPR_PORT, Flashpoint.LEGACY_HTDOCS)
			var pj := Spr.projector_for(rec)
			if port < 0 or not spr.configure_proxy(port, pj):
				row["detail"] = spr.last_error
				return -1
			return spr.play(Unzip.resolved_movie(dest, launch), Unzip.extra_args(launch), pj)
		"navigator":
			if not await packs.ensure_for(rec):
				row["detail"] = packs.last_error
				return -1
			var prefer := (
				LocalHttp.PLUGIN_PORT if Packs.wants_plugin_port(rec) else LocalHttp.SPR_PORT
			)
			var port := httpd.serve(serve_root, prefer, Flashpoint.LEGACY_HTDOCS)
			if port < 0:
				row["detail"] = "no local HTTP"
				return -1
			packs.configure_proxy(port)
			var rel := Unzip.resolved_rel(dest, launch)
			if rel.is_empty():
				rel = Unzip.path_from_launch(launch)
			return packs.play_app(rec, httpd.url_for(rel, "localhost"), Unzip.resolved_movie(dest, launch))
		"flash":
			if not await flash.ensure():
				row["detail"] = flash.last_error
				return -1
			var port := httpd.serve(serve_root, LocalHttp.SPR_PORT, Flashpoint.LEGACY_HTDOCS)
			if port < 0 or not flash.configure_proxy(port):
				row["detail"] = flash.last_error
				return -1
			var movie := Flash.movie_for(dest, launch)
			if movie.is_empty():
				row["detail"] = "no movie URL"
				return -1
			return flash.play(rec, movie)
		_:
			## A page with no plugin: Ruffle's own web build in our server is the
			## closest thing to a headless browser we have.
			if not await ruffle.ensure():
				row["detail"] = ruffle.last_error
				return -1
			var port := httpd.serve(serve_root, 18765, Flashpoint.LEGACY_HTDOCS)
			if port < 0:
				row["detail"] = "no local HTTP"
				return -1
			var swf := Unzip.swf_for_launch(dest, launch)
			if swf.is_empty():
				row["detail"] = "page entry needs a browser; not checked headlessly"
				return -1
			return ruffle.play(
				Unzip.resolved_movie(dest, launch), "", "http://127.0.0.1:%d" % port,
				Unzip.resolved_movie(dest, launch)
			)


## Every process a title can leave behind. Patterns, because the Flash pack
## ships a dozen differently-named projectors.
const PLAYER_PATTERNS: PackedStringArray = [
	"fpnavigator.exe",
	"basilisk*",
	"flashplayer*",
	"saflashplayer*",
	"flashpla*",
	"spr.exe",
	"ruffle.exe",
	"flashpointsecureplayer.exe",
	"oldcpusimulator.exe",
]


static func _is_player(name: String) -> bool:
	var n := name.to_lower().strip_edges()
	for pat in PLAYER_PATTERNS:
		if pat.ends_with("*"):
			if n.begins_with(pat.substr(0, pat.length() - 1)):
				return true
		elif n == pat:
			return true
	return false


## One tasklist call rather than one per name — this is polled while reaping.
func _running() -> PackedStringArray:
	var out: Array = []
	OS.execute("tasklist", PackedStringArray(["/NH", "/FO", "CSV"]), out, false)
	var found := PackedStringArray()
	for line in str(out[0] if out.size() > 0 else "").split("\n"):
		var s := line.strip_edges()
		if not s.begins_with("\""):
			continue
		var end := s.find("\"", 1)
		if end < 1:
			continue
		var name := s.substr(1, end - 1)
		if _is_player(name) and not found.has(name):
			found.append(name)
	return found


## A live process with a window still proves nothing if the window is Gecko
## telling us it could not load the page. These are the titles it uses.
const ERROR_TITLES: PackedStringArray = [
	"problem loading page",
	"server not found",
	"unable to connect",
	"page load error",
	"did not connect",
	"connection reset",
	"file not found",
	"404",
]


static func _is_error_page(title: String) -> bool:
	var t := title.to_lower()
	if t.is_empty():
		return false
	for bad in ERROR_TITLES:
		if t.find(bad) >= 0:
			return true
	return false


## Ask the player processes themselves rather than the pid we launched, which
## under throttling is the wrapper and owns no window.
func _player_window_title() -> String:
	if OS.get_name() != "Windows":
		return ""
	var names: PackedStringArray = []
	for n in _running():
		names.append("'%s'" % n.get_basename())
	if names.is_empty():
		return ""
	var out: Array = []
	OS.execute(
		"powershell",
		PackedStringArray([
			"-NoProfile",
			"-Command",
			"Get-Process -Name %s -ErrorAction SilentlyContinue" % ",".join(names)
			+ " | Where-Object { $_.MainWindowTitle }"
			+ " | Select-Object -First 1 -ExpandProperty MainWindowTitle",
		]),
		out,
		false
	)
	return str(out[0] if out.size() > 0 else "").strip_edges()


## Runtimes phone home on startup — Unity to its update and stats hosts, Flash
## to Adobe. Those were never in the archive and their absence is not this
## title's problem, so they do not count against it.
const TELEMETRY_HOSTS: PackedStringArray = [
	"autoupdate-revision.unity3d.com",
	"stats.unity3d.com",
	"webplayer.unity3d.com",
	"fpdownload.macromedia.com",
	"fpdownload2.macromedia.com",
	"geo2.adobe.com",
	"crl.verisign.com",
	"ocsp.verisign.com",
]


static func _real_misses(misses: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for m in misses:
		var host := m.split("/")[0].to_lower()
		if not TELEMETRY_HOSTS.has(host):
			out.append(m)
	return out


static func _first(items: PackedStringArray, n: int) -> PackedStringArray:
	var out := PackedStringArray()
	for s in items:
		if out.size() >= n:
			break
		out.append(s)
	return out


## launch_shown hands back the shell helper's pid when the player's own pid has
## not been written yet, and that helper exits once it has raised the window.
## So ask the player processes themselves.
func _alive(pid: int) -> bool:
	var real := Spr.launch_pid()
	if real > 0 and OS.is_process_running(real):
		return true
	if pid > 0 and OS.is_process_running(pid):
		return true
	return not _running().is_empty()


## A player that outlives its title blocks the next one: Navigator refuses to
## start while another instance holds the profile lock, and the run stalls
## there. So the harness does not move on until the machine is actually clear.
func _reap(pid: int = -1, timeout_ms: int = 20000) -> bool:
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	var spawned := Spr.launch_pid()
	if spawned > 0 and spawned != pid and OS.is_process_running(spawned):
		OS.kill(spawned)
	_kill_launch_helper()
	var start := Time.get_ticks_msec()
	var escalated := false
	while Time.get_ticks_msec() - start < timeout_ms:
		var live := _running()
		if live.is_empty():
			_clear_profile_locks()
			return true
		for name in live:
			## Ask first. Secure Player reverts the registry it changed only on
			## a clean exit, so force-killing it leaves the machine dirty.
			if not escalated:
				OS.execute("taskkill", PackedStringArray(["/IM", name]), [], false)
			else:
				OS.execute("taskkill", PackedStringArray(["/F", "/T", "/IM", name]), [], false)
		if not escalated and Time.get_ticks_msec() - start > timeout_ms / 2:
			escalated = true
			_kill_launch_helper()
			print("        …still closing: ", ", ".join(live))
		for _i in 30:
			await process_frame
	print("        WARNING: could not close ", ", ".join(_running()))
	return false


## The launch helper is a powershell running our own script. Match on its
## command line — this machine runs other powershell processes that are none
## of our business.
func _kill_launch_helper() -> void:
	if OS.get_name() != "Windows":
		return
	OS.execute(
		"powershell",
		PackedStringArray([
			"-NoProfile",
			"-Command",
			"Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\""
			+ " | Where-Object { $_.CommandLine -like '*spr_launch.ps1*' }"
			+ " | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }",
		]),
		[],
		false
	)
	for f in [Spr.PID_RES, Spr.READY_RES]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


## A hard-killed Navigator leaves its profile locked, and the next one then
## refuses to start. Clear the locks once nothing is running.
func _clear_profile_locks() -> void:
	var nav := packs.navigator_exe()
	if nav.is_empty():
		return
	var dirs := Packs.live_profile_dirs(nav.get_base_dir())
	dirs.append(ProjectSettings.globalize_path("user://bin/nav-profile"))
	for d in dirs:
		for name in ["parent.lock", ".parentlock", "lock", ".lock"]:
			var p := d.path_join(name)
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)


func _cleanup(dest: String, zip: String) -> void:
	if _keep:
		return
	_rm_rf(dest)
	if not zip.is_empty() and FileAccess.file_exists(zip):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(zip))


func _rm_rf(path: String) -> void:
	var abs := ProjectSettings.globalize_path(path)
	var d := DirAccess.open(abs)
	if d == null:
		return
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if fname != "." and fname != "..":
			if d.current_is_dir():
				_rm_rf(path.path_join(fname))
			else:
				d.remove(fname)
		fname = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(abs)


func _write_report() -> void:
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("verdict,route,platform,title,detail,served,missing,window,id")
	for entry: Variant in _rows:
		var r: Dictionary = entry
		f.store_line(",".join(PackedStringArray([
			str(r["verdict"]),
			str(r["route"]),
			_csv(str(r["platform"])),
			_csv(str(r["title"])),
			_csv(str(r["detail"])),
			str(r["served"]),
			str(r["missing"]),
			_csv(str(r.get("window", ""))),
			str(r["id"]),
		])))
	f.close()


static func _csv(s: String) -> String:
	if s.find(",") < 0 and s.find("\"") < 0:
		return s
	return "\"%s\"" % s.replace("\"", "\"\"")


func _summary() -> void:
	var by := {}
	for entry: Variant in _rows:
		var v := str((entry as Dictionary)["verdict"])
		by[v] = int(by.get(v, 0)) + 1
	print("\n=== soak summary (%d titles) ===" % _rows.size())
	for k: Variant in by.keys():
		print("  %-9s %d" % [str(k), int(by[k])])
	print("  report: ", ProjectSettings.globalize_path(_out))
	for entry: Variant in _rows:
		var r: Dictionary = entry
		if str(r["verdict"]) != "STARTED":
			print("  %-9s %-9s %s — %s" % [str(r["verdict"]), str(r["route"]), str(r["title"]), str(r["detail"])])
