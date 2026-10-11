class_name UpdateBanner
extends PanelContainer
## The "an update is available" banner under the clubhouse top bar, like the
## other Simple-* apps: Update downloads and runs the installer, then Restart
## opens the new version.

signal shown_changed

var _label: Label
var _update: Button
var _restart: Button


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.75, 0.22, 0.17, 0.92)
	sb.content_margin_left = 16
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	_label = Label.new()
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 16)
	row.add_child(_label)
	_update = Button.new()
	_update.text = "Update"
	_update.pressed.connect(func() -> void: Updater.download_and_install())
	row.add_child(_update)
	_restart = Button.new()
	_restart.text = "Restart"
	_restart.visible = false
	_restart.pressed.connect(func() -> void: Updater.restart())
	row.add_child(_restart)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.pressed.connect(func() -> void:
		visible = false
		shown_changed.emit())
	row.add_child(close)
	visible = false

	Updater.update_available.connect(announce)
	Updater.status_changed.connect(set_status)
	Updater.installed.connect(func(_v: String) -> void:
		_update.visible = false
		_restart.visible = true)
	# The check may have finished before this banner existed.
	if Updater.latest_version != "":
		announce(Updater.latest_version, Updater.release_url)


func announce(version: String, _url: String) -> void:
	_label.text = "Update available: Simple-Golf %s (you have %s)" % [version, Updater.current_version()]
	_update.visible = true
	_update.disabled = false
	_restart.visible = false
	visible = true
	shown_changed.emit()


func set_status(text: String, busy: bool) -> void:
	_label.text = text
	_update.disabled = busy
	visible = true
	shown_changed.emit()
