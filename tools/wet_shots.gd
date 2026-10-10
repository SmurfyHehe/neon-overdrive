extends SceneTree

# Screenshots of the road dry, wet, and wet on the Low preset, for judging
# the wet asphalt and the puddles by eye (S1a, scripts/world/road_wet.gd).
# Boots the real game scene with no traffic, pins the wetness (the rain
# branch rolls nothing in a tool run: Weather.ROLL_ON is false and the
# benchmark/test flags keep it dry), and shoots the chase camera plus a low
# eye-level view down the road where the Fresnel sheen and the far puddles
# show. Needs the real renderer (no --headless). Writes PNGs to
# user://wet_shots/ (%APPDATA%\Godot\app_userdata\Neon Overdrive\wet_shots).
#
#   <godot> --path . -s res://tools/wet_shots.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const RoadWet := preload("res://scripts/world/road_wet.gd")
const WetReflections := preload("res://scripts/world/wet_reflections.gd")

var game: Node

func _initialize() -> void:
	game = Harness.boot(self, 0, 300.0, 7)
	_run.call_deferred()

func _run() -> void:
	for i in 30:
		await process_frame
	game.set("_wet_pinned", true)  # nothing overwrites the wetness we set below
	var p: PlayerCar = game.get("player")
	# Roll a little way in so the car sits between lamps with puddles ahead.
	Harness.launch_player(p, 12.0)
	for i in 90:
		await physics_frame
	p.linear_velocity = Vector3.ZERO
	p.angular_velocity = Vector3.ZERO
	for i in 30:
		await physics_frame
	var dir := ProjectSettings.globalize_path("user://wet_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var chase: Camera3D = root.get_viewport().get_camera_3d()
	var eye := Camera3D.new()
	eye.fov = 60.0
	root.add_child(eye)
	var shots := {
		"dry": [0.0, true],
		"wet": [1.0, true],
		"wet_low": [1.0, false],
	}
	for name in shots:
		WetReflections.set_wetness(shots[name][0])
		RoadWet.set_reflections(shots[name][1])
		chase.make_current()
		await _shoot("%s/%s_chase.png" % [dir, name])
		# eye level, 1.2 m up, looking 60 m down the road: the grazing view
		eye.global_position = p.global_position + Vector3(1.5, 1.2, 0.0)
		eye.look_at(p.global_position + Vector3(0.0, 0.6, -60.0))
		eye.make_current()
		await _shoot("%s/%s_eye.png" % [dir, name])
		# the three nearest puddles ahead, close up and from 70 m back (the
		# grazing view, where a deep one should shine)
		var puds := _puddles_ahead(p.global_position)
		for k in mini(3, puds.size()):
			var pud: Vector3 = puds[k]
			# close (about the chase camera's angle) and far (grazing)
			for v in [Vector3(0.0, 2.2, 8.0), Vector3(0.0, 1.2, 70.0)]:
				eye.global_position = pud + v
				eye.look_at(pud)
				await _shoot("%s/%s_puddle%d_%dm.png" % [dir, name, k, int(v.z)])
	print("wet_shots: wrote PNGs to ", dir)
	quit(0)

## World positions of the visible puddle quads ahead of `from` (-Z), nearest
## first.
func _puddles_ahead(from: Vector3) -> Array:
	var out := []
	for mmi in root.find_children("Puddles", "MultiMeshInstance3D", true, false):
		var mm: MultiMesh = (mmi as MultiMeshInstance3D).multimesh
		for i in mm.visible_instance_count:
			var w: Vector3 = (mmi as Node3D).global_transform * mm.get_instance_transform(i).origin
			if from.z - w.z > 5.0:
				out.append(w)
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z > b.z)
	print("puddles ahead: ", out.size(), " nearest ", out.slice(0, 3))
	return out

func _shoot(path: String) -> void:
	for i in 12:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
