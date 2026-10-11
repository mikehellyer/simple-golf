class_name GraphicsSettings
extends RefCounted
## Shadows, anti-aliasing and renderer choices, saved in user://settings.cfg.
##
## Shadows and anti-aliasing apply immediately. The renderer can only be
## chosen when the game starts, so changing it restarts the game.

const SETTINGS_PATH := "user://settings.cfg"
const SHADOWS := ["Off", "Low", "High"]
const ANTI_ALIASING := ["Off", "FXAA (fastest)", "MSAA 2×", "MSAA 4×"]
const RENDERERS := ["Standard (Vulkan)", "Faster (Vulkan mobile)", "Compatibility (OpenGL)"]
const RENDER_METHODS := ["forward_plus", "mobile", "gl_compatibility"]

var shadows := 2
var anti_aliasing := 2
var renderer := 0
## Not graphics, but saved alongside: ask GitHub for new versions at start.
var check_updates := true


static func load_saved() -> GraphicsSettings:
	var g := GraphicsSettings.new()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	g.shadows = clampi(cfg.get_value("graphics", "shadows", 2), 0, SHADOWS.size() - 1)
	g.anti_aliasing = clampi(cfg.get_value("graphics", "anti_aliasing", 2), 0, ANTI_ALIASING.size() - 1)
	g.renderer = clampi(cfg.get_value("graphics", "renderer", 0), 0, RENDERERS.size() - 1)
	g.check_updates = cfg.get_value("general", "check_updates", true)
	return g


## Saves into the shared settings file without disturbing other sections.
func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("graphics", "shadows", shadows)
	cfg.set_value("graphics", "anti_aliasing", anti_aliasing)
	cfg.set_value("graphics", "renderer", renderer)
	cfg.set_value("general", "check_updates", check_updates)
	cfg.save(SETTINGS_PATH)


func apply(viewport: Viewport, sun: DirectionalLight3D) -> void:
	sun.shadow_enabled = shadows > 0
	if shadows == 1:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 120.0
		RenderingServer.directional_shadow_atlas_set_size(2048, true)
	elif shadows == 2:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = 300.0
		RenderingServer.directional_shadow_atlas_set_size(4096, true)
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if anti_aliasing == 1 \
			else Viewport.SCREEN_SPACE_AA_DISABLED
	match anti_aliasing:
		2:
			viewport.msaa_3d = Viewport.MSAA_2X
		3:
			viewport.msaa_3d = Viewport.MSAA_4X
		_:
			viewport.msaa_3d = Viewport.MSAA_DISABLED


## True when the running renderer isn't the chosen one.
func needs_restart() -> bool:
	return RenderingServer.get_current_rendering_method() != RENDER_METHODS[renderer]


## Restarts the game with the chosen renderer.
func restart(tree: SceneTree) -> void:
	var args := PackedStringArray()
	var skip := false
	for a in OS.get_cmdline_args():
		if skip:
			skip = false
			continue
		if a in ["--rendering-method", "--rendering-driver"]:
			skip = true
			continue
		args.append(a)
	# Godot doesn't report its own arguments back, so when running from source
	# (not an exported game with its data built in) pass the project path.
	if not OS.has_feature("template") and not "--path" in args:
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--rendering-method", RENDER_METHODS[renderer]])
	if renderer == 2:
		args.append_array(["--rendering-driver", "opengl3"])
	var user_args := OS.get_cmdline_user_args()
	if not user_args.is_empty():
		args.append("--")
		args.append_array(user_args)
	OS.set_restart_on_exit(true, args)
	tree.quit()
