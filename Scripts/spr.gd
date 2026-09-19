## Flashpoint Shockwave projector (SPR.exe + Director runtime). Fetched from
## the same component zip Infinity/Manager use — not a user-installed copy.

class_name Spr
extends Node

const BIN_ROOT := "user://bin/shockwave"
const VERSION_PATH := "user://bin/shockwave/VERSION"
const COMPONENTS_XML := "https://nexus-dev.unstable.life/repository/stable/components.xml"
const ZIP_URL := "https://nexus-dev.unstable.life/repository/stable/supportpack-shockwave.zip"
const UA := "Reliquary/0.1 (GodOnChain; SPR fetch)"
const DEFAULT_PJ := "PJ101"
## Windows create_process starts Director/SPR hidden; shell-launch and raise.
const PID_RES := "user://bin/spr-launch.pid"
const READY_RES := "user://bin/spr-ready.flag"
const LAUNCH_PS1 := r"""
param(
  [Parameter(Mandatory = $true)][string]$Exe,
  [Parameter(Mandatory = $true)][string]$Cwd,
  [Parameter(Mandatory = $true)][string]$PidFile,
  [string]$ArgFile = '',
  [string]$ReadyFile = '',
  [switch]$HideHost,
  [int]$RaiseMs = 8000
)
$ErrorActionPreference = 'Stop'
try {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SprWin {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int pid);
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] public static extern IntPtr GetWindowLongPtr(IntPtr h, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  static int _pid;
  static bool _found;
  static bool IsConsole(IntPtr h) {
    var sb = new System.Text.StringBuilder(256);
    GetClassName(h, sb, 256);
    var n = sb.ToString();
    return n == "ConsoleWindowClass" || n == "CASCADIA_HOSTING_WINDOW_CLASS";
  }
  static bool Cb(IntPtr h, IntPtr l) {
    uint wpid;
    GetWindowThreadProcessId(h, out wpid);
    if (wpid != (uint)_pid) return true;
    if (IsConsole(h)) return true;
    if ((GetWindowLongPtr(h, -20).ToInt64() & 0x80L) != 0) return true;
    if (!IsWindowVisible(h) && !IsIconic(h)) return true;
    if (IsIconic(h)) ShowWindowAsync(h, 9);
    else ShowWindowAsync(h, 5);
    uint fgPid;
    uint fgTid = GetWindowThreadProcessId(GetForegroundWindow(), out fgPid);
    uint thisTid = GetCurrentThreadId();
    bool attached = false;
    if (fgTid != thisTid) attached = AttachThreadInput(fgTid, thisTid, true);
    BringWindowToTop(h);
    SetForegroundWindow(h);
    if (attached) AttachThreadInput(fgTid, thisTid, false);
    return true;
  }
  public static void Raise(int pid) {
    _pid = pid;
    AllowSetForegroundWindow(-1);
    EnumWindows(new EnumProc(Cb), IntPtr.Zero);
  }
  static bool CbFind(IntPtr h, IntPtr l) {
    uint wpid;
    GetWindowThreadProcessId(h, out wpid);
    if (wpid != (uint)_pid) return true;
    if (IsConsole(h)) return true;
    if ((GetWindowLongPtr(h, -20).ToInt64() & 0x80L) != 0) return true;
    if (!IsWindowVisible(h) && !IsIconic(h)) return true;
    _found = true;
    return false;
  }
  public static bool HasVisible(int pid) {
    _pid = pid;
    _found = false;
    EnumWindows(new EnumProc(CbFind), IntPtr.Zero);
    return _found;
  }
}
'@
} catch {}
$SprArgs = @()
if ($ArgFile -and (Test-Path -LiteralPath $ArgFile)) {
  $parsed = Get-Content -LiteralPath $ArgFile -Raw | ConvertFrom-Json
  $SprArgs = @($parsed)
}
try { [SprWin]::AllowSetForegroundWindow(-1) } catch {}
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $Exe
$psi.WorkingDirectory = $Cwd
if ($HideHost) {
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
} else {
  $psi.UseShellExecute = $true
  $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal
}
if ($SprArgs.Count -gt 0) {
  $quoted = foreach ($a in $SprArgs) {
    if ($null -eq $a) { continue }
    $s = [string]$a
    if ($s -match '[\s"]') { '"' + $s.Replace('"','\"') + '"' } else { $s }
  }
  $psi.Arguments = [string]::Join(' ', @($quoted))
}
$p = [System.Diagnostics.Process]::Start($psi)
if (-not $p) { exit 1 }
Set-Content -LiteralPath $PidFile -Value $p.Id -Encoding ASCII
function Get-TreePids([int]$id) {
  $acc = New-Object 'System.Collections.Generic.List[int]'
  $acc.Add($id) | Out-Null
  $q = New-Object System.Collections.Queue
  $q.Enqueue($id)
  while ($q.Count -gt 0) {
    $cur = [int]$q.Dequeue()
    try {
      Get-CimInstance Win32_Process -Filter "ParentProcessId=$cur" -ErrorAction SilentlyContinue | ForEach-Object {
        $cid = [int]$_.ProcessId
        if (-not $acc.Contains($cid)) {
          $acc.Add($cid) | Out-Null
          $q.Enqueue($cid)
        }
      }
    } catch {}
  }
  return $acc
}
$deadline = [datetime]::UtcNow.AddMilliseconds($RaiseMs)
$ready = $false
do {
  foreach ($id in Get-TreePids([int]$p.Id)) {
    try { [SprWin]::Raise($id) } catch {}
    if (-not $ready -and $ReadyFile) {
      try {
        if ([SprWin]::HasVisible($id)) {
          Set-Content -LiteralPath $ReadyFile -Value '1' -Encoding ASCII
          $ready = $true
        }
      } catch {}
    }
  }
  Start-Sleep -Milliseconds 250
  $p.Refresh()
} while (-not $p.HasExited -and [datetime]::UtcNow -lt $deadline)
"""

var last_error: String = ""
var tag: String = ""
var pack_dir: String = ""
var _pid: int = -1


func has_runtime() -> bool:
	return not _find_exe(_pack_root(), DEFAULT_PJ).is_empty()


func current_tag() -> String:
	if not FileAccess.file_exists(VERSION_PATH):
		return ""
	var file := FileAccess.open(VERSION_PATH, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text().strip_edges()
	file.close()
	return text


## applicationPath like FPSoftware\Shockwave\PJ1159\SPR.exe → PJ1159.
static func projector_folder(application_path: String) -> String:
	var p := application_path.replace("\\", "/")
	for part in p.split("/"):
		var up := part.to_upper()
		if up.begins_with("PJ") and up.length() >= 3:
			return part
	return DEFAULT_PJ


static func projector_for(entry: Dictionary) -> String:
	var from_app := projector_folder(str(entry.get("applicationPath", "")))
	if from_app != DEFAULT_PJ:
		return from_app
	var from_launch := projector_folder(str(entry.get("launch", entry.get("launchCommand", ""))))
	if from_launch != DEFAULT_PJ:
		return from_launch
	return from_app


func exe_for(pj: String = DEFAULT_PJ) -> String:
	return _find_exe(_pack_root(), pj)


func ensure(progress: Callable = Callable(), recover: Callable = Callable()) -> bool:
	last_error = ""
	if OS.get_name() != "Windows":
		last_error = "Shockwave projector is Windows-only."
		return false

	var installed := current_tag()
	if not installed.is_empty():
		pack_dir = "%s/%s" % [BIN_ROOT, installed]
		var have := _find_exe(ProjectSettings.globalize_path(pack_dir), DEFAULT_PJ)
		if FileAccess.file_exists(have):
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
	var archive := "user://bin/shockwave-download.zip"
	if not await _download(ZIP_URL, archive, progress):
		if has_runtime():
			return true
		if recover.is_valid() and await recover.call("Shockwave projector", archive):
			pass
		else:
			return false
	if not FileAccess.file_exists(archive):
		return has_runtime()

	var dest := "%s/%s" % [BIN_ROOT, latest]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest))
	if not _extract(archive, dest):
		return has_runtime()

	var found := _find_exe(ProjectSettings.globalize_path(dest), DEFAULT_PJ)
	if found.is_empty() or not FileAccess.file_exists(found):
		last_error = "Extracted Shockwave pack but could not find SPR.exe."
		return has_runtime()

	_write_version(latest)
	if not installed.is_empty() and installed != latest:
		_remove_dir("%s/%s" % [BIN_ROOT, installed])
	tag = latest
	pack_dir = dest
	if progress.is_valid():
		progress.call(100.0)
	return true


## SPR.dir Lingo: if proxy.txt is 1, proxyServer(#http, "127.0.0.1", port.txt).
func configure_proxy(proxy_port: int, pj: String = DEFAULT_PJ) -> bool:
	var exe := exe_for(pj)
	if exe.is_empty() or not FileAccess.file_exists(exe):
		last_error = "SPR.exe is not installed yet."
		return false
	var dir := exe.get_base_dir()
	if not _write_text(dir.path_join("port.txt"), str(proxy_port)):
		last_error = "Could not write SPR port.txt."
		return false
	if not _write_text(dir.path_join("proxy.txt"), "1"):
		last_error = "Could not write SPR proxy.txt."
		return false
	return true


func play(
	movie: String,
	extra: PackedStringArray = PackedStringArray(),
	pj: String = DEFAULT_PJ,
	throttle_mhz: int = 0,
	throttle_exe: String = ""
) -> int:
	var exe := exe_for(pj)
	if exe.is_empty() or not FileAccess.file_exists(exe):
		last_error = "SPR.exe is not installed yet."
		return -1
	var args := PackedStringArray([movie])
	args.append_array(extra)
	if OS.get_name() == "Windows":
		_pid = launch_shown(exe, args, "", throttle_mhz, throttle_exe)
	else:
		_pid = OS.create_process(exe, args, false)
	if _pid == -1:
		last_error = "Failed to launch SPR.exe."
	return _pid


## OldCPUSimulator: `-t N -sw player.exe` then the player's own args.
static func oldcpu_args(mhz: int, exe: String, args: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray([
		"-t",
		str(maxi(mhz, 1)),
		"-r",
		"60",
		"-a1",
		"-sw",
		exe,
	])
	out.append_array(args)
	return out


## Godot create_process uses CREATE_NO_WINDOW; raise a normal player window.
static func launch_shown(
	exe: String,
	args: PackedStringArray,
	work_dir: String = "",
	throttle_mhz: int = 0,
	throttle_exe: String = ""
) -> int:
	var run_exe := exe
	var run_args := args
	if (
		throttle_mhz > 0
		and not throttle_exe.is_empty()
		and FileAccess.file_exists(throttle_exe)
	):
		run_args = oldcpu_args(throttle_mhz, exe, args)
		run_exe = throttle_exe
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bin"))
	var script_res := "user://bin/spr_launch.ps1"
	var args_res := "user://bin/spr-args.json"
	var pid_res := PID_RES
	var ready_res := READY_RES
	if not _write_text(script_res, LAUNCH_PS1.strip_edges() + "\n"):
		return OS.create_process(run_exe, run_args, false)
	var payload: Array = []
	for a in run_args:
		payload.append(a)
	if not _write_text(args_res, JSON.stringify(payload)):
		return OS.create_process(run_exe, run_args, false)
	if FileAccess.file_exists(pid_res):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pid_res))
	if FileAccess.file_exists(ready_res):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ready_res))
	var script_abs := ProjectSettings.globalize_path(script_res).replace("/", "\\")
	var exe_abs := run_exe.replace("/", "\\")
	var cwd := (work_dir if not work_dir.is_empty() else exe.get_base_dir()).replace("/", "\\")
	var pid_abs := ProjectSettings.globalize_path(pid_res).replace("/", "\\")
	var args_abs := ProjectSettings.globalize_path(args_res).replace("/", "\\")
	var ready_abs := ProjectSettings.globalize_path(ready_res).replace("/", "\\")
	var hide := run_exe.get_file().to_lower().find("oldcpusimulator") >= 0
	var ps := PackedStringArray([
		"-NoProfile",
		"-STA",
		"-ExecutionPolicy",
		"Bypass",
		"-File",
		script_abs,
		"-Exe",
		exe_abs,
		"-Cwd",
		cwd,
		"-PidFile",
		pid_abs,
		"-ArgFile",
		args_abs,
		"-ReadyFile",
		ready_abs,
		"-RaiseMs",
		"12000",
	])
	if hide:
		ps.append("-HideHost")
	var helper := OS.create_process("powershell.exe", ps, false)
	if helper == -1:
		return OS.create_process(run_exe, run_args, false)
	for _i in 12:
		OS.delay_msec(25)
		var pid := _read_pid_file(pid_res)
		if pid > 0:
			return pid
	return helper if helper > 0 else OS.create_process(run_exe, run_args, false)


static func launch_pid() -> int:
	return _read_pid_file(PID_RES)


static func player_ready() -> bool:
	return FileAccess.file_exists(READY_RES)


static func _read_pid_file(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var text := file.get_as_text().strip_edges()
	file.close()
	if text.is_valid_int():
		return int(text)
	return -1


static func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


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
		last_error = "Could not start Shockwave component list request."
		http.queue_free()
		return ""
	var result: Array = await http.request_completed
	http.queue_free()
	if int(result[1]) != 200:
		last_error = "Shockwave component list returned HTTP %s." % str(result[1])
		return ""
	var body: PackedByteArray = result[3]
	var parser := XMLParser.new()
	if parser.open_buffer(body) != OK:
		last_error = "Could not parse Shockwave component list."
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
		if id == "shockwave" and title == "Shockwave" and download_size > 1_000_000 and hash.length() >= 8:
			return hash
	last_error = "Component list had no Shockwave support pack."
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
		last_error = "Could not start Shockwave pack download."
		ticker.queue_free()
		http.queue_free()
		return false
	ticker.start()
	var result: Array = await http.request_completed
	ticker.stop()
	ticker.queue_free()
	http.queue_free()
	if int(result[1]) != 200:
		last_error = "Shockwave pack download returned HTTP %s." % str(result[1])
		return false
	return FileAccess.file_exists(dest)


func _extract(archive: String, dest: String) -> bool:
	var abs_archive := ProjectSettings.globalize_path(archive)
	var abs_dest := ProjectSettings.globalize_path(dest)
	if _extract_zip(abs_archive, abs_dest):
		if not _find_exe(abs_dest, DEFAULT_PJ).is_empty():
			return true
	if OS.get_name() == "Windows":
		var ps := PackedStringArray([
			"-NoProfile",
			"-Command",
			"Expand-Archive -Force -Path '%s' -DestinationPath '%s'" % [abs_archive.replace("'", "''"), abs_dest.replace("'", "''")],
		])
		var code := OS.execute("powershell", ps, [], false, true)
		if code == 0 and not _find_exe(abs_dest, DEFAULT_PJ).is_empty():
			return true
	if last_error.is_empty():
		last_error = "Could not extract the Shockwave pack."
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


func _find_exe(dir: String, pj: String) -> String:
	if dir.is_empty():
		return ""
	var want := pj if not pj.is_empty() else DEFAULT_PJ
	var names: PackedStringArray = [
		dir.path_join("Shockwave").path_join(want).path_join("SPR.exe"),
		dir.path_join("FPSoftware").path_join("Shockwave").path_join(want).path_join("SPR.exe"),
		dir.path_join(want).path_join("SPR.exe"),
	]
	for p in names:
		if FileAccess.file_exists(p):
			return p
	if want != DEFAULT_PJ:
		var fallback := _find_exe(dir, DEFAULT_PJ)
		if not fallback.is_empty():
			return fallback
	return _walk_spr(dir)


func _walk_spr(dir: String) -> String:
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
		elif fname.to_lower() == "spr.exe":
			d.list_dir_end()
			return full
		fname = d.get_next()
	d.list_dir_end()
	for sub in nested:
		var hit := _walk_spr(sub)
		if not hit.is_empty():
			return hit
	return ""


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
