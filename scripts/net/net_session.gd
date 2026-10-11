class_name NetSession
extends Node
## Online sessions over ENet: hosting, joining, and the pre-game lobby.
##
## The host is authoritative. Clients tell the host their name and game
## version; the host keeps the lobby (members, format, computer players) and
## broadcasts it. In-game messages live on the game node itself.

signal lobby_changed
signal join_finished(ok: bool, reason: String)
signal session_closed(reason: String)
signal member_left(peer_id: int)

const DEFAULT_PORT := 24680
const MAX_CLIENTS := 3

## peer id -> player name, host included (peer 1).
var members := {}
## Format chosen by the host: {mode, cpus: [kind...], holes}.
var settings := {mode = Competition.Mode.STROKE, cpus = [], holes = 18}
var is_host := false
## This machine's club member id, attached to its player in the line-up.
var my_profile := ""
var _peer: ENetMultiplayerPeer


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_online() -> bool:
	return _peer != null


func host(port: int, my_name: String) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return err
	_peer = peer
	multiplayer.multiplayer_peer = peer
	is_host = true
	members = {1: my_name}
	lobby_changed.emit()
	return OK


## address may be "host" or "host:port".
func join(address: String, my_name: String) -> Error:
	leave()
	var host_name := address.strip_edges()
	var port := DEFAULT_PORT
	if ":" in host_name:
		port = host_name.get_slice(":", 1).to_int()
		host_name = host_name.get_slice(":", 0)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host_name, port)
	if err != OK:
		return err
	_peer = peer
	multiplayer.multiplayer_peer = peer
	is_host = false
	members = {}
	set_meta("my_name", my_name)
	return OK


func leave() -> void:
	if _peer:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_host = false
	members = {}


func set_settings(new_settings: Dictionary) -> void:
	settings = new_settings
	_broadcast_lobby()


## The full line-up in playing order: host, then clients by join order, then
## computer players (owned and run by the host).
func line_up() -> Array[Competition.Player]:
	var out: Array[Competition.Player] = []
	var ids := members.keys()
	ids.sort()
	for id in ids:
		var p := Competition.Player.new(members[id], Competition.Kind.HUMAN,
				Competition.COLOURS[out.size() % Competition.COLOURS.size()])
		p.owner = id
		if id == 1:
			p.profile = my_profile
		out.append(p)
	var cpu_names := ["Ace", "Birdie", "Chip"]
	for i in settings.cpus.size():
		var p := Competition.Player.new(cpu_names[i % cpu_names.size()],
				settings.cpus[i], Competition.COLOURS[out.size() % Competition.COLOURS.size()])
		out.append(p)
	return out


# --- Lobby messages --------------------------------------------------------

@rpc("any_peer", "reliable")
func _register(player_name: String, version: String) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if version != Updater.current_version():
		_rejected.rpc_id(sender, "The host is running Simple-Golf %s; you have %s."
				% [Updater.current_version(), version])
		_kick_later(sender)
		return
	if members.size() + settings.cpus.size() >= 4:
		_rejected.rpc_id(sender, "The game is full.")
		_kick_later(sender)
		return
	members[sender] = player_name.left(12)
	_broadcast_lobby()


@rpc("authority", "reliable")
func _rejected(reason: String) -> void:
	leave()
	join_finished.emit(false, reason)


@rpc("authority", "reliable")
func _lobby(new_members: Dictionary, new_settings: Dictionary) -> void:
	var first := members.is_empty()
	members = new_members
	settings = new_settings
	if first:
		join_finished.emit(true, "")
	lobby_changed.emit()


func _broadcast_lobby() -> void:
	if is_host and is_online():
		_lobby.rpc(members, settings)
	lobby_changed.emit()


func _kick_later(peer_id: int) -> void:
	await get_tree().create_timer(0.5).timeout
	if _peer and is_host:
		_peer.disconnect_peer(peer_id)


# --- Connection events -----------------------------------------------------

func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	if is_host and members.has(id):
		members.erase(id)
		_broadcast_lobby()
		member_left.emit(id)


func _on_connected() -> void:
	_register.rpc_id(1, str(get_meta("my_name", "Player")), Updater.current_version())


func _on_connection_failed() -> void:
	leave()
	join_finished.emit(false, "Could not reach the host.")


func _on_server_disconnected() -> void:
	leave()
	session_closed.emit("The host left the game.")
