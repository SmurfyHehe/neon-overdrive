extends SceneTree

# The compound station lots of Loop 1 from the driver's seat (2026-10-11):
# for each act-1 station the entry (from the lane before the taper and at the
# driveway), under the canopy at a pump, the store row from the aisle, and
# leaving by the exit. Needs the real renderer (no --headless). Writes PNGs
# to <out dir>/<station>_<view>.png.
#
#   <godot> --path . --audio-driver Dummy -s res://tools/station_lot_shots.gd -- [out dir]
#
# NEON_CURVES=0 NEON_HILLS=0 NEON_TRAFFIC=0 NEON_POLICE=0 keep the road straight and empty.

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")
const GasStation := preload("res://scripts/world/gas_station.gd")

## [name, lot x, lot la, look at lot x, look at lot la]; "pump", "aisle" and
## "overview" are placed from the station's own layout.
const VIEWS := [
	["1_lane_before_taper", -1.6, -105.0, -1.6, -40.0],
	["2_entry", -0.5, -58.0, 6.0, -42.0],
	["3_under_canopy", 0.0, 0.0, 0.0, 0.0],
	["4_aisle_store", 0.0, 0.0, 0.0, 0.0],
	["5_leaving", 12.0, 30.0, 3.0, 46.0],
	["6_overview", 0.0, 0.0, 0.0, 0.0],
]

var game: Node

func _initialize() -> void:
	game = Harness.boot(self, 0, 300.0, 3)
	_run.call_deferred()

func _run() -> void:
	for i in 30:
		await process_frame
	var out := "C:/SmurfyHehe/review-shots/gas-2"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	for n in game.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	var cam := Camera3D.new()
	cam.fov = 70.0
	root.add_child(cam)
	var p: PlayerCar = game.get("player")
	for st in GasStation.RoadMap.STOPS:
		if String(st.kind) != "station":
			continue
		var ss := float(st.s)
		var side := int(st.side)
		var lot := GasStation.lot_of(ss, side)
		var canopy: Rect2 = lot.canopy
		var cc := canopy.get_center().y
		var store_la := 0.0
		for b in lot.solids:
			if is_equal_approx((b.r as Rect2).size.y, GasStation.STORE_HALF * 2.0):
				store_la = (b.r as Rect2).get_center().y
		for v in VIEWS:
			var from := Vector2(float(v[1]), float(v[2]))
			var to := Vector2(float(v[3]), float(v[4]))
			var eye := 1.25
			match String(v[0]):
				"3_under_canopy":
					from = Vector2(GasStation.ISLAND_X0 - 2.0, cc - 22.0)
					to = Vector2(GasStation.ISLAND_X0 - 1.0, cc + 10.0)
				"4_aisle_store":
					from = Vector2(29.0, store_la - 26.0)
					to = Vector2(38.0, store_la)
				"6_overview":
					from = Vector2(-9.0, -70.0)
					to = Vector2(30.0, 5.0)
					eye = 16.0
			# the car goes to the camera's place so the road is built round it
			var rp := GasStation.lot_to_road(Vector2(clampf(from.x, -8.0, -1.6), from.y), ss, side)
			var z := float(RoadFrame.origin_index) * RoadFrame.L - rp.y
			var y := RoadFrame.unroll(p.global_position).y
			var t := RoadFrame.pose(rp.x, y, z, 0.0 if side == 1 else PI)
			game.saver.restore_car(p, {"xform": SaveDirector.xform_to_array(t), "lin_vel": [0.0, 0.0, 0.0], "ang_vel": [0.0, 0.0, 0.0], "gear": 1})
			game.call("_update_chunk_pool", z)
			game.call("flush_rebuilds")
			for i in 12:
				p.set("linear_velocity", Vector3.ZERO)
				await process_frame
			p.visible = String(v[0]) == "6_overview"
			var a := _world(from, ss, side) + Vector3.UP * eye
			var b := _world(to, ss, side) + Vector3.UP * (1.0 if eye < 5.0 else 0.0)
			cam.global_transform = Transform3D(Basis(), a).looking_at(b, Vector3.UP)
			cam.make_current()
			for i in 6:
				await process_frame
			var path := "%s/%s_%s.png" % [out, st.id, v[0]]
			root.get_viewport().get_texture().get_image().save_png(path)
			print("station_lot_shots: ", path)
	quit(0)

func _world(q: Vector2, ss: float, side: int) -> Vector3:
	var rp := GasStation.lot_to_road(q, ss, side)
	var z := float(RoadFrame.origin_index) * RoadFrame.L - rp.y
	return RoadFrame.pose(rp.x, 0.0, z, 0.0).origin
