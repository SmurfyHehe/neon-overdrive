extends SceneTree

# Out-of-bounds walls (#28): every road chunk carries an invisible wall behind
# each sidewalk, so the gaps between buildings do not open onto a drivable slab.
#
# Asserts (exit code 1 on failure):
# - Game.tscn has BoundaryOwn and BoundaryOnc bodies, each with a tall box shape
# - they are not drivable surfaces (no surface group a wheel would read)
# - rays cast across the right-hand side every metre all hit something solid
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/boundary_walls.gd

var game: Node
var ticks := 0
var fails := 0

func _initialize() -> void:
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _find(n: Node, name: String, out: Array) -> void:
	if n.name == name:
		out.append(n)
	for c in n.get_children():
		_find(c, name, out)

func _physics_process(_delta: float) -> bool:
	var p: PlayerCar = game.get("player")
	ticks += 1
	if ticks == 5:
		for name in ["BoundaryOwn", "BoundaryOnc"]:
			var found := []
			_find(game, name, found)
			print("%s: %d bodies" % [name, found.size()])
			if found.is_empty():
				_fail("no %s bodies in the world" % name)
			for b in found:
				var box := ((b as Node).get_node(^"Shape") as CollisionShape3D).shape as BoxShape3D
				if box == null or box.size.y < 4.0:
					_fail("%s is not a tall box" % name)
				if (b as Node).get_groups().size() > 0:
					_fail("%s is in a group (%s), it must not be a drivable surface" % [name, (b as Node).get_groups()])
		# Rays across the right-hand side every metre ahead of the car: each must
		# hit something solid before x=25, i.e. no building gap leads onto open slab.
		var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
		var z0 := p.global_position.z
		var open := 0
		for i in 120:
			var q := PhysicsRayQueryParameters3D.create(Vector3(0.0, 1.5, z0 - i), Vector3(25.0, 1.5, z0 - i))
			if space.intersect_ray(q).is_empty():
				open += 1
		print("rays that escape past x=25: %d of 120" % open)
		if open > 0:
			_fail("%d of 120 rays escape through a gap in the right-hand side" % open)
		print("boundary_walls: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
		quit(0 if fails == 0 else 1)
	return false
