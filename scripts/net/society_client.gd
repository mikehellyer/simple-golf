class_name SocietyClient
extends Node
## Talks to the online society server (see server/). Remembers the server
## address and the signed-in session in user://society.cfg.
##
## Every call is awaited and returns {ok, status, data, error}, where error is
## a message fit to show the player.

signal signed_in_changed

const CONFIG_PATH := "user://society.cfg"
const TIMEOUT := 15.0

var server_url := ""
var token := ""
## {id, username, display_name} once signed in.
var user := {}


func _ready() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	server_url = cfg.get_value("society", "server", "")
	token = cfg.get_value("society", "token", "")


func is_signed_in() -> bool:
	return token != "" and server_url != ""


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("society", "server", server_url)
	cfg.set_value("society", "token", token)
	cfg.save(CONFIG_PATH)


## "name.duckdns.org" → "https://name.duckdns.org"; local addresses use http.
static func normalise_url(address: String) -> String:
	var a := address.strip_edges().trim_suffix("/")
	if a == "" or a.begins_with("http://") or a.begins_with("https://"):
		return a
	var host := a.get_slice(":", 0)
	var local := host in ["localhost", "127.0.0.1"] or host.begins_with("192.168.") or host.begins_with("10.")
	return ("http://" if local else "https://") + a


func call_api(method: HTTPClient.Method, path: String, body = null) -> Dictionary:
	if server_url == "":
		return {ok = false, status = 0, data = {}, error = "No society server set."}
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	var version := str(ProjectSettings.get_setting("application/config/version", "0"))
	var headers := PackedStringArray(["Content-Type: application/json", "User-Agent: simple-golf/%s" % version])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var err := http.request(server_url + "/api/v1" + path, headers, method,
			"" if body == null else JSON.stringify(body))
	if err != OK:
		http.queue_free()
		return {ok = false, status = 0, data = {}, error = "Couldn't reach the server (%s)." % error_string(err)}
	var res: Array = await http.request_completed
	http.queue_free()
	var result: int = res[0]
	var code: int = res[1]
	var parsed = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	var data: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	if result != HTTPRequest.RESULT_SUCCESS:
		return {ok = false, status = 0, data = {}, error = "Couldn't reach the society server. Check the address and your connection."}
	if code == 401 and token != "":
		# The session has gone (signed out elsewhere or expired).
		token = ""
		_save()
		signed_in_changed.emit()
	if code >= 400:
		return {ok = false, status = code, data = data, error = _error_text(data, code)}
	return {ok = true, status = code, data = data, error = ""}


static func _error_text(data: Dictionary, code: int) -> String:
	var detail = data.get("detail")
	if typeof(detail) == TYPE_STRING:
		return detail
	if typeof(detail) == TYPE_ARRAY and not detail.is_empty() and typeof(detail[0]) == TYPE_DICTIONARY:
		var d: Dictionary = detail[0]
		var where := str(d.get("loc", [""])[-1]).replace("_", " ")
		return "%s: %s" % [where.capitalize(), d.get("msg", "invalid")]
	return "The server said no (error %d)." % code


func sign_in(address: String, username: String, password: String) -> Dictionary:
	server_url = normalise_url(address)
	var r := await call_api(HTTPClient.METHOD_POST, "/auth/login", {username = username, password = password})
	return _after_auth(r)


func register(address: String, username: String, password: String, display_name: String) -> Dictionary:
	server_url = normalise_url(address)
	var r := await call_api(HTTPClient.METHOD_POST, "/auth/register",
			{username = username, password = password, display_name = display_name})
	return _after_auth(r)


func _after_auth(r: Dictionary) -> Dictionary:
	if r.ok:
		token = r.data.token
		user = r.data.user
		_save()
		signed_in_changed.emit()
	return r


func sign_out() -> void:
	if token != "":
		await call_api(HTTPClient.METHOD_POST, "/auth/logout")
	token = ""
	user = {}
	_save()
	signed_in_changed.emit()


## Checks the session and fetches the player's societies.
func me() -> Dictionary:
	var r := await call_api(HTTPClient.METHOD_GET, "/me")
	if r.ok:
		user = r.data.user
	return r


func society(id: int) -> Dictionary:
	return await call_api(HTTPClient.METHOD_GET, "/societies/%d" % id)


func create_society(society_name: String) -> Dictionary:
	return await call_api(HTTPClient.METHOD_POST, "/societies", {name = society_name})


func join_society(code: String) -> Dictionary:
	return await call_api(HTTPClient.METHOD_POST, "/societies/join", {invite_code = code})


func new_invite(society_id: int) -> Dictionary:
	return await call_api(HTTPClient.METHOD_POST, "/societies/%d/invite" % society_id)


func set_role(society_id: int, member_id: int, role: String) -> Dictionary:
	return await call_api(HTTPClient.METHOD_PUT, "/societies/%d/members/%d" % [society_id, member_id], {role = role})


func remove_member(society_id: int, member_id: int) -> Dictionary:
	return await call_api(HTTPClient.METHOD_DELETE, "/societies/%d/members/%d" % [society_id, member_id])


func member_stats(society_id: int, member_id: int) -> Dictionary:
	return await call_api(HTTPClient.METHOD_GET, "/societies/%d/members/%d/stats" % [society_id, member_id])


func create_tournament(society_id: int, details: Dictionary) -> Dictionary:
	return await call_api(HTTPClient.METHOD_POST, "/societies/%d/tournaments" % society_id, details)


func tournament(id: int) -> Dictionary:
	return await call_api(HTTPClient.METHOD_GET, "/tournaments/%d" % id)


func delete_tournament(id: int) -> Dictionary:
	return await call_api(HTTPClient.METHOD_DELETE, "/tournaments/%d" % id)


func rounds(society_id: int, member_id := -1) -> Dictionary:
	var q := "?limit=100" + ("&member=%d" % member_id if member_id >= 0 else "")
	return await call_api(HTTPClient.METHOD_GET, "/societies/%d/rounds%s" % [society_id, q])


func round_card(id: int) -> Dictionary:
	return await call_api(HTTPClient.METHOD_GET, "/rounds/%d" % id)


func submit_round(card: Dictionary) -> Dictionary:
	return await call_api(HTTPClient.METHOD_POST, "/rounds", card)
