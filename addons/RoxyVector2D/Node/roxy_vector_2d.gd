@tool
@icon("res://addons/RoxyVector2D/Node/roxy_vector_2d.svg")
extends Node2D
class_name RoxyVector2D

signal direction_changed()

## Represent vector's [b]direction[/b]
@export var direction:= Vector2(0, 32):
	get: return direction
	set(val):
		direction = val
		queue_redraw()
		emit_signal("direction_changed")

## Get of set the vector's [b]length[/b] without change its direction
@export var length: float:
	get: return direction.length()
	set(val):
		direction = direction.normalized() * val

## Set the arrow's width
@export_category("Debug")
@export var width:= 2.0:
	get: return width
	set(val):
		width = val
		queue_redraw()
		
## Set the arrow's color
@export var color := Color.RED:
	get: return color
	set(val):
		color = val
		queue_redraw()
	
func _draw() -> void:
	if Engine.is_editor_hint() or (OS.is_debug_build() and get_tree().debug_paths_hint):
		var compensatedDir = direction / global_scale
		var dirNormal = compensatedDir.normalized()
		var dirScaled = compensatedDir - ((width * sqrt(2) / 2) * dirNormal)
		var headDir1 = dirNormal.rotated(3*PI/4)
		var headDir2 = dirNormal.rotated(-3*PI/4)
		
		draw_line(Vector2(0,0), dirScaled, color, width)
		draw_line(dirScaled - headDir1*width/2, dirScaled + headDir1*10*(width/2.0), color, width)
		draw_line(dirScaled - headDir2*width/2, dirScaled + headDir2*10*(width/2.0), color, width)
