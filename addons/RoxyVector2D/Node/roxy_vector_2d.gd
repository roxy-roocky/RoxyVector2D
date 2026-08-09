@tool
@icon("res://addons/RoxyVector2D/Node/roxy_vector_2d.svg")
extends Node2D
class_name RoxyVector2D

const roxyvector2d_settings = preload("res://addons/RoxyVector2D/roxyvector2D_settings.gd")

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

@export_category("Debug")
## Set the arrow's width.
## Set to "-1.0" to use project's default width
@export_range(-1.0, 500, 0.1) var width:= -1.0:
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
		
func _validate_property(property: Dictionary) -> void:
	if property.name == "length":
		property.usage &= ~PROPERTY_USAGE_STORAGE # remove 
		
func real_arrow_width() -> float:
	if width > 0:
		return width
	elif ProjectSettings.has_setting(roxyvector2d_settings.PROJECT_SETTINGS_DEFAULT_WIDTH):
		return ProjectSettings.get_setting_with_override(roxyvector2d_settings.PROJECT_SETTINGS_DEFAULT_WIDTH)
	else: 
		return roxyvector2d_settings.PROJECT_SETTINGS_DEFAULT_WIDTH_VALUE
		
## Vector direction in global space
var global_direction: Vector2:
	get: return global_transform.basis_xform(direction)
	set(val): direction = global_transform.affine_inverse().basis_xform(val)
	
func _draw() -> void:
	if Engine.is_editor_hint() or (OS.is_debug_build() and get_tree().debug_paths_hint):
		var realWidth: float = real_arrow_width()
		var dirNormal = direction.normalized()
		var dirScaled = direction - ((realWidth * sqrt(2) / 2) * dirNormal)
		var headDir1 = dirNormal.rotated(3*PI/4)
		var headDir2 = dirNormal.rotated(-3*PI/4)
		
		draw_line(Vector2(0,0), dirScaled, color, realWidth)
		draw_line(dirScaled - headDir1*realWidth/2, dirScaled + headDir1*10*(realWidth/2.0), color, realWidth)
		draw_line(dirScaled - headDir2*realWidth/2, dirScaled + headDir2*10*(realWidth/2.0), color, realWidth)
