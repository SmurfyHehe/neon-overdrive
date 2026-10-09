class_name PassingLampLight
extends Node3D

# Street lamps light the player's car as it passes under them (2026-10-09,
# small-ideas G1 and Roy's "car lights up under lamps: yes"):
# - chase view: an orange band of light slides over the bonnet, roof and boot
#   under each lamp
# - cockpit view: the same band sweeps over the dash, the hands and the seats,
#   front to back
#
# The road's light pools are painted on (no real lights), so without this the
# car drove through them unlit. Two spot lights sit on the two nearest lamp
# heads (the real positions, read from the road chunks' lamp MultiMeshes). Each
# aims at the point on the car's centre line level with its lamp, with a
# narrow cone, so the lit band lies across the car where the lamp is and
# slides back along it as the car drives under. They light only the car (chase
# view) or only the cabin and driver (cockpit view), dead lamps give nothing,
# failing ones half.

const LIGHTS := 2
const BAND_HALF := 0.8         # half the band's length along the car, m
const ENERGY := 6.0            # on the car body (chase view)
## In the cockpit the band is the point of it and the light reaches dark trim
## from ~10 m away, so it is brighter and longer there (measured: at 6 and
## 0.8 m it changed the dash by under 10%; 40 at 1.3 m reads clearly on the
## pillar, dash top and cluster hood).
const ENERGY_COCKPIT := 40.0
const BAND_HALF_COCKPIT := 1.3
## Only lamps closer than this, m: one side's lamps are 25 m apart and the far
## side's heads ~14 m across and 7 m up, so 26 always finds one.
const REACH := 26.0
const HEAD_LOCAL := Vector3(-RoadChunkBuilder.LAMP_ARM + 0.2, RoadChunkBuilder.LAMP_POLE_H - 0.25, 0.0)

var player: PlayerCar
var camera: ChaseCamera
var game: Node
var spots: Array[SpotLight3D] = []

func _init(car: PlayerCar, cam: ChaseCamera, world: Node) -> void:
	player = car
	camera = cam
	game = world
	name = "PassingLampLight"

func _ready() -> void:
	top_level = true
	for i in LIGHTS:
		var s := SpotLight3D.new()
		s.light_color = RoadChunkBuilder.SODIUM
		s.shadow_enabled = false
		s.spot_range = REACH + 4.0
		s.spot_attenuation = 0.5
		s.spot_angle_attenuation = 0.15   # a band with soft edges, not a hot spot
		s.visible = false
		add_child(s)
		spots.append(s)

## Lamp heads near the car: [world position, brightness 0..1, distance], nearest first.
func nearby_lamps() -> Array:
	var car := player.global_position
	var out := []
	for c in game.get("chunk_pool"):
		var root: Node3D = c.root
		var mmi := root.get_node_or_null(^"Lamps") as MultiMeshInstance3D
		if mmi == null:
			continue
		var mm := mmi.multimesh
		for i in mm.visible_instance_count:
			var p := root.global_transform * (mm.get_instance_transform(i) * HEAD_LOCAL)
			var d := p.distance_to(car)
			if d > REACH:
				continue
			var st := RoadChunkBuilder.lamp_state(int(c.index), i)
			var level := 0.0 if st.r > 0.75 else (0.5 if st.r > 0.25 else 1.0)
			if level > 0.0:
				out.append([p, level, d])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[2] < b[2])
	return out

func _process(_delta: float) -> void:
	var cockpit := camera != null and camera.view == ChaseCamera.View.COCKPIT
	var mask := (CockpitFrame.INTERIOR_BIT | CockpitFrame.DRIVER_BIT) if cockpit else CockpitFrame.CAR_BIT
	var lamps := nearby_lamps()
	for i in LIGHTS:
		var s := spots[i]
		if i >= lamps.size():
			s.visible = false
			continue
		var head: Vector3 = lamps[i][0]
		# The point on the car's centre line, at roof height, level with the lamp.
		var local := player.to_local(head)
		var target := player.to_global(Vector3(0.0, 1.0, local.z))
		var dist := head.distance_to(target)
		if dist < 0.1:
			s.visible = false
			continue
		s.global_position = head
		var dir := (target - head) / dist
		s.look_at(target, Vector3.FORWARD if absf(dir.y) > 0.99 else Vector3.UP)
		s.spot_angle = rad_to_deg(atan((BAND_HALF_COCKPIT if cockpit else BAND_HALF) / dist))
		s.light_energy = (ENERGY_COCKPIT if cockpit else ENERGY) * float(lamps[i][1])
		s.light_cull_mask = mask
		s.visible = true
