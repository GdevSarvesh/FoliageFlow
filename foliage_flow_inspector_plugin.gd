@tool
extends EditorInspectorPlugin

const FoliageFlowScript := preload("res://addons/FoliageFlow/FoliageFlow.gd")
const InspectorPanel := preload("res://addons/FoliageFlow/foliage_flow_inspector_panel.tscn")

func _can_handle(object: Object) -> bool:
	return object.get_script() == FoliageFlowScript

func _parse_begin(object: Object) -> void:
	var panel := InspectorPanel.instantiate()
	panel.setup(object)
	add_custom_control(panel)
