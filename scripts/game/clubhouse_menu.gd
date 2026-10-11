class_name ClubhouseMenu
extends Control
## The clubhouse screen: a top bar, plus either the "New round" panel or
## "Members & stats", docked on the right so the room stays in view.

signal view_changed(which: String)
signal members_changed
signal quit_requested

var setup: SetupMenu
var members_panel: MembersPanel
var _profiles: PlayerProfiles
var _tab_play: Button
var _tab_members: Button


static func panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.1, 0.06, 0.88)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(20)
	return sb


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bar := PanelContainer.new()
	var sb := panel_style()
	sb.set_corner_radius_all(0)
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	bar.add_theme_stylebox_override("panel", sb)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	var title := Label.new()
	title.text = "Simple-Golf Clubhouse"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
	row.add_child(title)
	var version := Label.new()
	version.text = "v%s" % Updater.current_version()
	version.modulate = Color(1, 1, 1, 0.5)
	row.add_child(version)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_tab_play = _tab("New round", "play")
	row.add_child(_tab_play)
	_tab_members = _tab("Members & stats", "members")
	row.add_child(_tab_members)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func() -> void: quit_requested.emit())
	row.add_child(quit)

	var dock := MarginContainer.new()
	dock.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	dock.offset_left = -600
	dock.offset_top = 70
	dock.offset_right = -20
	dock.offset_bottom = -20
	add_child(dock)
	setup = SetupMenu.new()
	setup.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	dock.add_child(setup)
	members_panel = MembersPanel.new()
	dock.add_child(members_panel)
	members_panel.members_changed.connect(func() -> void:
		setup.refresh_players()
		members_changed.emit())


func _tab(text: String, which: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.pressed.connect(func() -> void: show_tab(which))
	return b


## New members start on "Members & stats" so they can join the club first.
func open(profiles: PlayerProfiles, status := "") -> void:
	_profiles = profiles
	visible = true
	setup.open(profiles, status)
	members_panel.open(profiles)
	show_tab("members" if profiles.members.is_empty() else "play")


func show_tab(which: String) -> void:
	setup.visible = which == "play"
	members_panel.visible = which == "members"
	_tab_play.button_pressed = which == "play"
	_tab_members.button_pressed = which == "members"
	if which == "members":
		members_panel.refresh()
	view_changed.emit(which)
