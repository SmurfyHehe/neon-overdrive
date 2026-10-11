extends SceneTree

# Renders the breakable roadside world for judging by eye (I1/I3, 2026-10-11).
# Needs the real renderer (no --headless). Writes PNGs to
# user://prop_break_shots/, or to the folder given after --.
#
#   hydrant_chase    a gusher on the kerb, from the chase camera, at night
#   hydrant_cockpit  driving through it in the cockpit view (the water sheet)
#   hydrant_patch    the wet patch down the gutter, from the kerb
#   lamp_down        a felled lamp, dark, with its stump
#   debris           knocked cones, a rolled bin and bent posts at rest
#
#   <godot> --path . --audio-driver Dummy -s res://tools/prop_break_shots.gd [-- C:/some/folder]

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const Districts := preload("res://scripts/world/districts.gd")
const Props := preload("res://scripts/world/roadside_props.gd")

var game: Node
var p: PlayerCar
var breaker: Node3D
var dir := "user://prop_break_shots"
var brake := true
var cam: Camera3D

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	OS.set_environment("NEON_POLICE", "0")
	Districts.force = "downtown"
	game = Harness.boot(self, 0, 300.0, 3)
	_run.call_deferred()

func _drive(c: PlayerCar) -> void:
	c.throttle_input = 0.0
	c.brake_input = 1.0 if brake else 0.0
	c.handbrake_input = 1.0 if brake else 0.0
	c.steering_input = 0.0

func _wait(seconds: float) -> void:
	var n := int(seconds * 60.0)
	for i in n:
		await process_frame

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("saved %s/%s.png" % [dir, name])

func _root_of(chunk: int) -> Node3D:
	for e in game.chunk_pool:
		if int(e.index) == chunk:
			return e.root
	return null

## The first real prop of `kind` on the own side in the chunks ahead: [root, chunk, index].
func _find(kind: int) -> Array:
	var here := floori(RoadFrame.s_at(RoadFrame.unroll(p.global_position).z) / Props.CHUNK_LEN)
	for c in [here + 1, here + 2, here + 3]:
		var r := _root_of(c)
		if r == null:
			continue
		var rec: Dictionary = Props.of(r)
		var gone: PackedByteArray = r.get_meta("props_gone", PackedByteArray())
		for i in rec.kind.size():
			if rec.kind[i] == kind and rec.side[i] == 1 and rec.slot[i] >= 0 and gone[i] == 0:
				return [r, c, i]
	return []

func _knock(ref: Array, corner: float) -> Vector3:
	var r: Node3D = ref[0]
	var rec: Dictionary = Props.of(r)
	var gone: PackedByteArray = r.get_meta("props_gone")
	gone[int(ref[2])] = 1
	r.set_meta("props_gone", gone)
	# as if the car had just driven through it at 60 km/h
	var keep := p.linear_velocity
	p.linear_velocity = -p.global_transform.basis.z * 16.7
	breaker._hit(p, false, r, int(ref[1]), rec, int(ref[2]), corner)
	p.linear_velocity = keep
	return r.global_transform * (rec.pos[int(ref[2])] as Vector3)

func _look(from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at)
	cam.make_current()

func _run() -> void:
	for i in 60:
		await process_frame
	for a in OS.get_cmdline_user_args():
		dir = a
	DirAccess.make_dir_recursive_absolute(dir)
	p = game.get("player")
	breaker = game.get("breaker")
	p.driver = _drive
	for n in game.get_children():
		if n is CanvasLayer and n.get("layer") != null and int(n.layer) >= 0:
			n.visible = false
	cam = Camera3D.new()
	cam.fov = 60.0
	root.add_child(cam)

	# a real kerb hydrant, burst, with the car parked short of it
	var h := _find(Props.HYDRANT)
	if h.is_empty():
		print("no hydrant ahead")
		quit(1)
		return
	var hrec: Dictionary = Props.of(h[0])
	var hx: float = hrec.road[int(h[2])].x
	var hs: float = float(int(h[1])) * Props.CHUNK_LEN - hrec.road[int(h[2])].y
	var s := RoadFrame.s_at(RoadFrame.unroll(p.global_position).z)
	TestDriver.place(p, hx - 3.4, hs - s - 16.0, 0.0, 0.0)
	var base := _knock(h, 0.5)
	breaker.water.wet[breaker.water.wet.size() - 1].hisser = false
	await _wait(3.0)
	game.camera.make_current()
	await _shot("hydrant_chase")
	await _wait(20.0)   # the patch runs down the gutter
	var u := RoadFrame.unroll(base)
	_look(RoadFrame.roll(Vector3(u.x + 1.5, 1.7, u.z + 7.0)), RoadFrame.roll(Vector3(u.x - 2.0, 0.0, u.z - 14.0)))
	await _shot("hydrant_patch")

	# through the jet in the cockpit view
	game.camera.set_view(1)
	game.camera.make_current()
	brake = false
	TestDriver.place(p, hx, -9.0 + 16.0 - 16.0, 0.0, 9.0, RoadFrame.unroll(p.global_position).y + 0.2)
	for i in 240:
		await physics_frame
		if breaker.water.sheet >= 0.99:
			break
	await _shot("hydrant_cockpit")
	game.camera.set_view(0)
	brake = true

	# a felled lamp
	var l := _find(Props.LAMP)
	if not l.is_empty():
		var foot := _knock(l, 0.5)
		await _wait(1.5)
		var lu := RoadFrame.unroll(foot)
		_look(RoadFrame.roll(Vector3(lu.x - 5.0, 1.8, lu.z + 8.0)), RoadFrame.roll(Vector3(lu.x, 0.5, lu.z - 4.0)))
		await _shot("lamp_down")

	# cones, a bin and posts at rest
	var mid := Vector3.ZERO
	var n := 0
	for kind in [Props.POST, Props.POST, Props.BIN, Props.CONE]:
		var ref := _find(kind)
		if ref.is_empty():
			continue
		mid += _knock(ref, 0.4)
		n += 1
	var s2 := RoadFrame.unroll(p.global_position)
	for k in 4:
		var t: Array = breaker.add_test_prop(Props.CONE, s2.x + 3.0 + float(k) * 0.2, p.global_position, 60.0 + float(k) * 2.5)
		if not t.is_empty():
			mid += _knock([_root_of(int(t[0])), int(t[0]), int(t[1])], 0.3 - 0.2 * float(k))
			n += 1
	await _wait(4.0)
	if n > 0:
		var mu := RoadFrame.unroll(mid / float(n))
		_look(RoadFrame.roll(Vector3(mu.x - 6.0, 2.2, mu.z + 14.0)), RoadFrame.roll(Vector3(mu.x, 0.2, mu.z - 6.0)))
		await _shot("debris")
	quit(0)
