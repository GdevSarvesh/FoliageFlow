@tool
extends EditorPlugin

const FoliageFlowScript := preload("res://addons/FoliageFlow/FoliageFlow.gd")
const FoliageFlowInspectorPluginScript := preload("res://addons/FoliageFlow/foliage_flow_inspector_plugin.gd")
const FoliageFlowNodeIcon := preload("res://addons/FoliageFlow/Node.png")

var _paint_button: Button
var _erase_button: Button
var _foliage_flow
var _inspector_plugin
var _stroke_before := PackedFloat32Array()
var _stroke_active := false

func _enter_tree() -> void:
	add_custom_type("FoliageFlow", "Node3D", FoliageFlowScript, FoliageFlowNodeIcon)
	_inspector_plugin = FoliageFlowInspectorPluginScript.new()
	add_inspector_plugin(_inspector_plugin)
	_paint_button = _make_button("Paint", _on_paint_toggled)
	_erase_button = _make_button("Erase", _on_erase_toggled)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _paint_button)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _erase_button)
	get_editor_interface().get_selection().selection_changed.connect(_on_selection_changed)
	_on_selection_changed()

func _exit_tree() -> void:
	if _inspector_plugin:
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null
	remove_custom_type("FoliageFlow")
	var selection := get_editor_interface().get_selection()
	if selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.disconnect(_on_selection_changed)
	for button in [_paint_button, _erase_button]:
		if is_instance_valid(button):
			remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, button)
			button.queue_free()

func _make_button(label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = "%s: OFF" % label
	button.toggle_mode = true
	button.visible = false
	button.toggled.connect(callback)
	return button

func _on_selection_changed() -> void:
	_foliage_flow = null
	for node in get_editor_interface().get_selection().get_selected_nodes():
		if node.get_script() == FoliageFlowScript:
			_foliage_flow = node
			break
	var found := _foliage_flow != null
	_paint_button.visible = found
	_erase_button.visible = found
	if found:
		_foliage_flow.set_undo_redo(get_undo_redo())
	else:
		_paint_button.button_pressed = false
		_erase_button.button_pressed = false
		_stroke_active = false

func _on_paint_toggled(enabled: bool) -> void:
	_paint_button.text = "Paint: %s" % ("ON" if enabled else "OFF")
	if enabled and _erase_button.button_pressed:
		_erase_button.button_pressed = false
	if _foliage_flow:
		_foliage_flow.erase_mode = false
	if not enabled:
		_finish_stroke()

func _on_erase_toggled(enabled: bool) -> void:
	_erase_button.text = "Erase: %s" % ("ON" if enabled else "OFF")
	if enabled and _paint_button.button_pressed:
		_paint_button.button_pressed = false
	if _foliage_flow:
		_foliage_flow.erase_mode = enabled

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if _foliage_flow == null or not (_paint_button.button_pressed or _erase_button.button_pressed):
		return AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				_stroke_before = _foliage_flow.get_transform_data()
				_stroke_active = true
				if _foliage_flow.paint(camera, mouse.position):
					return AFTER_GUI_INPUT_STOP
			else:
				_finish_stroke()
				return AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _stroke_active and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if _foliage_flow.paint(camera, motion.position):
				return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS

func _finish_stroke() -> void:
	if _stroke_active and _foliage_flow:
		_foliage_flow.commit_edit("Paint Foliage", _stroke_before)
	_stroke_active = false

func _handles(object: Object) -> bool:
	return object.get_script() == FoliageFlowScript
