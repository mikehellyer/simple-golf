class_name FlatCourse
extends RefCounted
## An endless flat course, used for club carry tables and tests.
## Implements the same duck-typed course interface as Hole.

var surface := Surface.FAIRWAY
var green_speed := Surface.MEDIUM
var pin := Vector3(0.0, 0.0, 10000.0)
var tree_top := 0.0


func height_at(_x: float, _z: float) -> float:
	return 0.0


func normal_at(_x: float, _z: float) -> Vector3:
	return Vector3.UP


func surface_at(_x: float, _z: float) -> int:
	return surface


func roll_decel(surf: int) -> float:
	var d: float = Surface.ROLL_DECEL[surf]
	return d * Surface.GREEN_SPEED_DECEL[green_speed] if surf == Surface.GREEN else d


func is_in_bounds(_x: float, _z: float) -> bool:
	return true


func trees_near(_x: float, _z: float) -> Array[Vector4]:
	return []
