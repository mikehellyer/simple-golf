class_name PadMap
extends RefCounted
## Gamepad / joystick layout (Xbox naming; PlayStation and other pads map to
## the same positions). Menus use the standard navigation: D-pad or stick to
## move, A to choose, B to go back.

## Button → command, during play.
const BUTTONS := {
	JOY_BUTTON_A: "swing",
	JOY_BUTTON_B: "cancel",
	JOY_BUTTON_X: "tee",
	JOY_BUTTON_Y: "stance",
	JOY_BUTTON_LEFT_SHOULDER: "ball",
	JOY_BUTTON_RIGHT_SHOULDER: "view",
	JOY_BUTTON_DPAD_UP: "club_up",
	JOY_BUTTON_DPAD_DOWN: "club_down",
	JOY_BUTTON_DPAD_LEFT: "tee_left",
	JOY_BUTTON_DPAD_RIGHT: "tee_right",
	JOY_BUTTON_START: "map",
	JOY_BUTTON_BACK: "card",
	JOY_BUTTON_LEFT_STICK: "view180",
	JOY_BUTTON_RIGHT_STICK: "grid",
}

## On the hole map the shoulder buttons turn the map instead.
const MAP_BUTTONS := {
	JOY_BUTTON_LEFT_SHOULDER: "rotate_left",
	JOY_BUTTON_RIGHT_SHOULDER: "rotate_right",
}

## Stick dead zone, and how much slower the right stick aims (fine aim).
const DEAD_ZONE := 0.2
const FINE_AIM := 0.25

## What each control does, for the Settings screen.
const LEGEND := [
	["A", "Swing (power, then snap) · on the map: proceed"],
	["B", "Cancel a swing"],
	["Left stick", "Aim · right stick: fine aim"],
	["D-pad ↑ / ↓", "Change club"],
	["D-pad ← / →", "Move the ball along the tee"],
	["X", "Tee height"],
	["Y", "Stance"],
	["LB", "Ball position · on the map: rotate"],
	["RB", "Flight view · on the map: rotate"],
	["Start", "Hole map"],
	["Back / Select", "Scorecard"],
	["Left stick click", "View from behind the hole"],
	["Right stick click", "Gridlines on the green"],
]


static func command(button: JoyButton, on_map: bool) -> String:
	if on_map and MAP_BUTTONS.has(button):
		return MAP_BUTTONS[button]
	return BUTTONS.get(button, "")


## A stick axis with the dead zone removed, rescaled to -1..1.
static func axis(value: float) -> float:
	if absf(value) < DEAD_ZONE:
		return 0.0
	return signf(value) * (absf(value) - DEAD_ZONE) / (1.0 - DEAD_ZONE)
