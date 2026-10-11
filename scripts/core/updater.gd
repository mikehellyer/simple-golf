extends Node
## Checks GitHub once at startup for a newer Simple-Golf release, and, when
## the player clicks Update, downloads the installer for this platform and
## runs it, the same way the other Simple-* apps do:
##   Linux:   pkexec apt install the .deb (one password prompt, in place)
##   macOS:   open the .dmg (drag the app to Applications)
##   Windows: run the Setup .exe
## Nothing is ever downloaded or installed without that click.

signal update_available(version: String, url: String)
## Progress and errors, for the update banner.
signal status_changed(text: String, busy: bool)
## The new version is installed (Linux): offer a restart.
signal installed(version: String)

const REPO := "mikehellyer/simple-golf"

var latest_version := ""
var release_url := ""
## [{name, url}] of the latest release's downloads.
var _assets: Array[Dictionary] = []
var _install_pid := -1
var _download_path := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var forced := "--update-check" in args or "--update-dry-run" in args
	if (OS.has_feature("editor") or DisplayServer.get_name() == "headless") and not forced:
		return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_check_completed.bind(http))
	http.request("https://api.github.com/repos/%s/releases/latest" % REPO,
			["Accept: application/vnd.github+json", "User-Agent: simple-golf"])


static func current_version() -> String:
	# --pretend-version lets the update flow be tested against a real release.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pretend-version="):
			return a.get_slice("=", 1)
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## True when version string `a` is newer than `b` ("1.2.10" > "1.2.9").
static func is_newer(a: String, b: String) -> bool:
	var pa := a.trim_prefix("v").split(".")
	var pb := b.trim_prefix("v").split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := pa[i].to_int() if i < pa.size() else 0
		var y := pb[i].to_int() if i < pb.size() else 0
		if x != y:
			return x > y
	return false


## The installer that suits this computer, from a release's file names.
static func pick_installer(names: PackedStringArray, os_name: String) -> String:
	var suffix: String = {"Linux": ".deb", "macOS": ".dmg", "Windows": "-Setup.exe"}.get(os_name, "")
	if suffix == "":
		return ""
	for n in names:
		if n.ends_with(suffix):
			return n
	return ""


func _on_check_completed(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		return
	var tag := str(data.get("tag_name", ""))
	if not is_newer(tag, current_version()):
		return
	latest_version = tag.trim_prefix("v")
	release_url = str(data.get("html_url", ""))
	_assets.clear()
	for a in data.get("assets", []):
		if typeof(a) == TYPE_DICTIONARY and a.has("name") and a.has("browser_download_url"):
			_assets.append({name = str(a.name), url = str(a.browser_download_url)})
	update_available.emit(latest_version, release_url)
	if "--update-dry-run" in OS.get_cmdline_user_args():
		print("UPDATE available ", latest_version, " installer ", _installer_asset())
		download_and_install()


func _installer_asset() -> Dictionary:
	var names := PackedStringArray()
	for a in _assets:
		names.append(a.name)
	var chosen := pick_installer(names, OS.get_name())
	for a in _assets:
		if a.name == chosen:
			return a
	return {}


## Called when the player clicks Update.
func download_and_install() -> void:
	var asset := _installer_asset()
	if asset.is_empty():
		status_changed.emit("No installer for this computer — opening the download page.", false)
		OS.shell_open(release_url)
		return
	DirAccess.make_dir_recursive_absolute("user://updates")
	_download_path = ProjectSettings.globalize_path("user://updates/%s" % asset.name)
	var http := HTTPRequest.new()
	http.download_file = _download_path
	add_child(http)
	http.request_completed.connect(_on_download_completed.bind(http))
	var err := http.request(asset.url, ["User-Agent: simple-golf"])
	if err != OK:
		status_changed.emit("Couldn't start the download (%s)." % error_string(err), false)
		return
	status_changed.emit("Downloading Simple-Golf %s…" % latest_version, true)


func _on_download_completed(result: int, code: int, _headers: PackedStringArray,
		_body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status_changed.emit("Download failed — try again, or get it from the releases page.", false)
		return
	if "--update-dry-run" in OS.get_cmdline_user_args():
		print("UPDATE downloaded ", _download_path, " ", FileAccess.get_file_as_bytes(_download_path).size(), " bytes")
		get_tree().quit()
		return
	_launch_installer()


func _launch_installer() -> void:
	match OS.get_name():
		"Linux":
			# Install in place with apt behind a graphical password prompt.
			# Wait for it: quitting now could take the prompt down with us.
			var pkexec := _which("pkexec")
			var apt := _which("apt")
			if pkexec == "" or apt == "":
				OS.shell_open(_download_path)
				status_changed.emit("Opened the installer — finish the update there.", false)
				return
			_install_pid = OS.create_process(pkexec, [apt, "install", "-y", _download_path])
			if _install_pid <= 0:
				status_changed.emit("Couldn't start the installer.", false)
				return
			status_changed.emit("Installing — enter your password in the system prompt…", true)
		"macOS":
			OS.shell_open(_download_path)
			status_changed.emit("Drag Simple-Golf into Applications, then open it again. Closing…", true)
			_quit_soon()
		"Windows":
			OS.create_process(_download_path, [])
			status_changed.emit("The installer is starting. Closing Simple-Golf…", true)
			_quit_soon()


func _process(_delta: float) -> void:
	if _install_pid <= 0 or OS.is_process_running(_install_pid):
		return
	var code := OS.get_process_exit_code(_install_pid)
	_install_pid = -1
	if code == 0:
		status_changed.emit("Simple-Golf %s is installed." % latest_version, false)
		installed.emit(latest_version)
	elif code == 126 or code == 127:
		status_changed.emit("Update cancelled.", false)
	else:
		status_changed.emit("The installer failed (code %d). You can install it from the releases page." % code, false)


## Restarts into the newly installed version.
func restart() -> void:
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	get_tree().quit()


func _quit_soon() -> void:
	await get_tree().create_timer(2.5).timeout
	get_tree().quit()


static func _which(program: String) -> String:
	for dir in OS.get_environment("PATH").split(":"):
		var path := dir.path_join(program)
		if FileAccess.file_exists(path):
			return path
	for dir in ["/usr/bin", "/bin", "/usr/sbin"]:
		if FileAccess.file_exists(dir.path_join(program)):
			return dir.path_join(program)
	return ""
