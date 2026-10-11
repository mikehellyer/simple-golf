class_name Surface
extends RefCounted
## Ground types and how the ball behaves on each of them.

enum { TEE, FAIRWAY, ROUGH, FRINGE, GREEN, BUNKER, WATER, OUT }

const NAMES := ["Tee", "Fairway", "Rough", "Fringe", "Green", "Bunker", "Water", "Out of bounds"]

## Fraction of the impact speed kept as bounce.
const RESTITUTION := [0.35, 0.35, 0.18, 0.3, 0.28, 0.04, 0.0, 0.0]
## Coulomb-style friction on impact: tangential speed lost per unit of normal impulse.
const FRICTION := [0.45, 0.45, 0.7, 0.45, 0.4, 0.9, 1.0, 1.0]
## How strongly backspin bites when the ball lands.
const SPIN_GRIP := [0.5, 0.5, 0.15, 0.55, 0.6, 0.1, 0.0, 0.0]
## Rolling deceleration in m/s². Green value matches a stimpmeter reading of ~10.
const ROLL_DECEL := [1.2, 1.3, 4.5, 0.9, 0.56, 10.0, 99.0, 99.0]
## Ball speed multiplier for a full shot played from this lie.
const LIE_POWER := [1.0, 1.0, 0.85, 1.0, 1.0, 0.7, 1.0, 1.0]
