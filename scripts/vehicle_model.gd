extends RefCounted
class_name VehicleModel

# Builds one look of one VehicleRegistry car: the body visual, four wheel
# visuals, and the hardpoints the physics wheels go at.
#
# Each wheel is pulled out of the model and re-parented under a fresh pivot
# centred on its own axle, because the physics Wheel spins its wheel_node
# about X and steers it about Y (gevp_wheel.gd) -- a wheel mesh left at the
# model's origin would orbit the car instead of turning in place.
#
# Conventions match the rest of the game: forward is -Z, up is +Y, and the
# model sits with its wheel bottoms on y = 0 (the chassis origin, springs
# fully extended), the same as TestCarBuilder.

const WHEELS := ["FL", "FR", "RL", "RR"]

## Returns {body: Node3D, wheels: {FL, FR, RL, RR: Node3D},
## hardpoints: {front_z, rear_z, wheel_x, wheel_r, collision}, and for model
## cars model_wheels/model_wheel_r: the model's own wheel centres and radius}.
static func build(id: String, look: String) -> Dictionary:
	var e := VehicleRegistry.entry(id)
	if e.get("builder", "") == "test":
		return _build_test_car(e)

	var model: Node3D = (load(e.looks[look]) as PackedScene).instantiate()
	var turn := Basis(Vector3.UP, PI) if e.forward == "+z" else Basis()
	var root_xf := Transform3D(turn.scaled(Vector3.ONE * float(e.scale)), Vector3.ZERO)

	# Measure every wheel in car space (turned and scaled, not yet lifted).
	var nodes := {}
	var xfs := {}
	var centres := {}
	var model_r := 0.0
	for key in WHEELS:
		var node := model.find_child(e.wheel_nodes[key], true, false) as Node3D
		if node == null:
			push_error("VehicleModel: %s/%s has no wheel node '%s'" % [id, look, e.wheel_nodes[key]])
			model.free()
			return {}
		var xf := root_xf * _relative_xf(node, model)
		var box := _aabb(node, xf)
		nodes[key] = node
		xfs[key] = xf
		centres[key] = box.get_center()
		model_r = maxf(model_r, box.size.y * 0.5)

	# Physics hardpoints: the model's own wheels unless the entry overrides.
	var p: Dictionary = e.get("physics", {})
	var hard := {
		"front_z": p.get("front_z", (centres.FL.z + centres.FR.z) * 0.5),
		"rear_z": p.get("rear_z", (centres.RL.z + centres.RR.z) * 0.5),
		"wheel_x": p.get("wheel_x", (absf(centres.FL.x) + absf(centres.FR.x) + absf(centres.RL.x) + absf(centres.RR.x)) * 0.25),
		"wheel_r": p.get("wheel_r", model_r),
	}

	# Wheel visuals: each centred on its pivot, resized if the physics radius
	# differs from the model's.
	var wheels := {}
	for key in WHEELS:
		var node: Node3D = nodes[key]
		var xf: Transform3D = xfs[key]
		node.get_parent().remove_child(node)
		node.owner = null  # it no longer belongs to the model's scene
		node.transform = Transform3D(xf.basis, xf.origin - centres[key])
		var pivot := Node3D.new()
		pivot.name = "Wheel" + key
		pivot.scale = Vector3.ONE * (float(hard.wheel_r) / model_r)
		pivot.add_child(node)
		wheels[key] = pivot

	# Body: lifted so the model's wheel bottoms sit on the ground.
	root_xf.origin.y = model_r - (centres.FL.y + centres.FR.y + centres.RL.y + centres.RR.y) * 0.25
	model.transform = root_xf
	var body := Node3D.new()
	body.name = "Body"
	body.set_meta("vehicle_id", id)
	body.set_meta("look", look)
	body.add_child(model)

	var size := _aabb(model, root_xf).size
	hard.collision = p.get("collision", Vector3(maxf(size.x - 0.2, 0.5), 0.6, maxf(size.z - 1.0, 1.0)))
	# model_wheels: where the model's own wheel centres ended up (car space),
	# for tests and for spotting a wrong "forward" or wheel_nodes entry.
	var lift := Vector3(0.0, root_xf.origin.y, 0.0)
	var model_wheels := {}
	for key in WHEELS:
		model_wheels[key] = centres[key] + lift
	return {"body": body, "wheels": wheels, "hardpoints": hard, "model_wheels": model_wheels, "model_wheel_r": model_r}

static func _build_test_car(e: Dictionary) -> Dictionary:
	var hard: Dictionary = e.physics.duplicate()
	var wheels := {}
	for key in WHEELS:
		wheels[key] = TestCarBuilder.build_wheel_visual(hard.wheel_r)
	return {"body": TestCarBuilder.build_chassis_visual(), "wheels": wheels, "hardpoints": hard}

## node's transform relative to ancestor (the scene isn't in the tree yet, so
## global_transform isn't available).
static func _relative_xf(node: Node, ancestor: Node) -> Transform3D:
	var xf := Transform3D()
	var n := node
	while n != ancestor:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf

## Bounding box of every mesh under node (node included), with node placed at xf.
static func _aabb(node: Node, xf: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var b := xf * _relative_xf(mi, node) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
