extends SceneTree

# Out-of-bounds walls (#28): every road chunk carries an invisible wall behind
# each sidewalk, so the gaps between buildings do not open onto a drivable slab.
#
# Asserts (exit code 1 on failure):
# - Game.tscn has BoundaryOwn and BoundaryOnc bodies, each with a tall box shape
# - they are not drivable surfaces (no surface group a wheel would read)
# - rays cast across the right-hand side every metre all hit something solid
#   by the out-of-bounds wall's own x there
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
		# hit something solid before it is past the out-of-bounds wall at that
		# point, i.e. no building gap leads onto open slab. The wall's x comes
		# from the chunk's own BoundaryOwn shapes (it moves out with a
		# district's setback: since the 8-look loop, 2026-10-13, the freeway's
		# 8 m lots blend into the start of District 1, which put it past the
		# 25 m this test used to assume).
		var walls := []  # [z_min, z_max, x_outer] in world space
		var own := []
		_find(game, "BoundaryOwn", own)
		for b in own:
			for c in (b as Node).get_children():
				var col := c as CollisionShape3D
				if col == null or col.disabled:
					continue
				var sz := (col.shape as BoxShape3D).size
				var o := col.global_position
				walls.append([o.z - sz.z / 2.0, o.z + sz.z / 2.0, o.x + sz.x / 2.0])
		var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
		var z0 := p.global_position.z
		var open := 0
		var far := 0.0
		for i in 120:
			var z := z0 - i
			var wall_x := -1.0
			for w in walls:
				if z >= float(w[0]) and z <= float(w[1]):
					wall_x = maxf(wall_x, float(w[2]))
			if wall_x < 0.0:
				_fail("no out-of-bounds wall at %d m ahead" % i)
				continue
			far = maxf(far, wall_x)
			var q := PhysicsRayQueryParameters3D.create(Vector3(0.0, 1.5, z), Vector3(wall_x + 0.5, 1.5, z))
			if space.intersect_ray(q).is_empty():
				open += 1
		print("rays that escape past the wall: %d of 120 (wall at most %.1f m out)" % [open, far])
		if open > 0:
			_fail("%d of 120 rays escape through a gap in the right-hand side" % open)
		print("boundary_walls: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
		quit(0 if fails == 0 else 1)
	return false
