extends Node
## Checks GitHub once at startup for a newer Simple-Golf release.

signal update_available(version: String, url: String)

const REPO := "mikehellyer/simple-golf"


func _ready() -> void:
	if OS.has_feature("editor") or DisplayServer.get_name() == "headless":
		return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_request_completed.bind(http))
	http.request("https://api.github.com/repos/%s/releases/latest" % REPO,
			["Accept: application/vnd.github+json", "User-Agent: simple-golf"])


static func current_version() -> String:
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


func _on_request_completed(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		return
	var tag := str(data.get("tag_name", ""))
	if is_newer(tag, current_version()):
		update_available.emit(tag.trim_prefix("v"), str(data.get("html_url", "")))
