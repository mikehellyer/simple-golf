class_name Lie
extends RefCounted
## How the ball is sitting, as in MicroProse Golf's lie icon: on top of the
## grass, in a divot, down in the rough, or in the sand (even plugged).
##
## The lie is judged where the ball comes to rest. It's decided by the
## shot (how it landed) and a hash of where it stopped, never by a random
## roll, so every machine in an online game agrees on it.

enum { GOOD, FLUFFY, POOR, VERY_POOR, DIVOT, SAND_GOOD, SAND_POOR, PLUGGED }

const NAMES := ["Good", "Fluffy", "Poor", "Very poor", "Divot", "Good (sand)", "Poor (sand)", "Plugged"]
const HINTS := [
	"A clean strike.",
	"Sitting up on the grass: it flies, with little spin, and runs on landing.",
	"In the rough: some power and most of the spin lost.",
	"Down in deep rough: much shorter, and hard to control.",
	"In an old divot: a little shorter, less spin, easier to mis-hit.",
	"Sitting nicely in the sand.",
	"A poor lie in the sand: it comes out short.",
	"Plugged in the sand: explode it out and settle for getting it on the green.",
]
## Landing faster than this (m/s, into the sand) buries the ball.
const PLUG_SPEED := 13.0


## The usual lie on each surface, before anything is judged.
static func default_for(surface: int) -> int:
	match surface:
		Surface.ROUGH:
			return POOR
		Surface.BUNKER:
			return SAND_GOOD
	return GOOD


## Judges the lie where a shot finished on this surface.
static func judge(surface: int, rest: Vector3, result: BallPhysics.Result) -> int:
	var roll := float(absi(hash(Vector2i(roundi(rest.x * 100.0), roundi(rest.z * 100.0)))) % 1000) / 1000.0
	match surface:
		Surface.FAIRWAY:
			return DIVOT if roll < 0.08 else GOOD
		Surface.ROUGH:
			if roll < 0.25:
				return FLUFFY
			return VERY_POOR if roll > 0.72 else POOR
		Surface.BUNKER:
			# A ball that dropped steeply into the sand and stopped there plugs.
			if result != null:
				for i in range(result.events.size() - 1, -1, -1):
					var e: Dictionary = result.events[i]
					if e.kind == BallPhysics.Event.BOUNCE:
						if e.surface == Surface.BUNKER and e.strength > PLUG_SPEED:
							return PLUGGED
						break
			return SAND_POOR if roll < 0.3 else SAND_GOOD
	return GOOD


## Changes a full shot for the lie, on top of the usual effect of the surface.
static func apply(l: BallPhysics.Launch, quality: int) -> void:
	match quality:
		FLUFFY:
			# Sitting up in the rough: nearly a full strike, but a "flier".
			l.speed *= 1.14
			l.sidespin *= 1.1
		VERY_POOR:
			l.speed *= 0.82
			l.backspin *= 0.8
			l.sidespin *= 1.4
		DIVOT:
			l.speed *= 0.92
			l.backspin *= 0.8
			l.sidespin *= 1.3
		SAND_POOR:
			l.speed *= 0.85
		PLUGGED:
			l.speed *= 0.65
			l.backspin *= 0.3
			l.elevation += deg_to_rad(4.0)
			l.sidespin *= 1.3
