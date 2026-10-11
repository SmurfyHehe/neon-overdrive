class_name TitleKerbside
extends Node3D

# The title screen's scene ("Kerbside", 2026-10-10): the player's own car parked
# at the kerb under one sodium street lamp, at night, seen from the road.
#
# It is a small set of its own, built far below the road (SITE), so while the
# title is up the camera sees only this: a strip of asphalt, the kerb, the
# sidewalk, a wall, one lamp and one car. The loaded world is out of the
# camera's range and is not drawn, which is what keeps the title cheap. The car
# is a copy of the player's car body and wheels with no physics and no script.
# One real light (the lamp, no shadows); the shadow under the car is a dark
# quad. The title screen frees the whole set when the drive starts.
#
# Lamp life (menu litter M2, 2026-10-11): the lamp post's own small life from
# the road chunks (lamp_life.gd) is switched on here too: newspaper and leaves
# gusting across the road in front of the car, steam from a manhole, moths
# round the lamp head and a bat now and then. All of it is shader-driven, so it
# runs while the title pauses the tree. The wind is one number
# (set_title_wind); the turbo on the title raises it. NEON_LAMP_LIFE=0 turns it
# off here as in the world.
#
# Roaches (menu roaches M7, 2026-10-11): the manhole lid sits ajar, a dark
# crescent of the hole showing on the camera's side, and ten roaches
# (title_roaches.gd) take turns coming out of it, dashing about the lamp pool
# and going back in, into the gutter or under the car. Shader-driven off one
# `clock` uniform this set writes each frame (started when the menu shows, held
# for screenshots). The turbo scares them (set_scare, from menu_boost): above
# 0.5 every roach out runs for cover, and none come out until the scare has
# been under 0.2 for 3 s. A very quiet skitter plays when two or more flee at
# once. Hidden with the rest of lamp life.
#
# Street life (menu street life M8 + rats M9, 2026-10-11): on the same clock,
# wind and scare, title_street_life.gd adds the neighbour's window above the
# shop front, four pigeons on the lamp arm, a cat on the shutter box, bin
# bags with a cloud of flies and a pair of sneakers on a wire, and
# title_rats.gd three rats along the foot of the wall. The events the turbo
# can set off (the neighbour waking, the pigeons lifting, the cat leaving)
# are scheduled here, one at a time, none in the first FIRST_EVENT_AT
# seconds, and the pigeons never with the bat's pass (a tiny time probe reads
# the shaders' TIME once, so the bat's schedule is known; without a renderer
# the rule is skipped). Settings > Game > "Roaches and rats" (GameSettings.
# critters) hides the roaches, the rats and the flies; the moths stay.
# Graffiti (M10, 2026-10-11): the wall wears the graffiti set (graffiti.gd):
# one big block piece high on the wall left of the car, part of it buffed by a
# roller patch, tags around the shutter, a NO PARKING stencil on the shutter
# with a tag sprayed over it, and a torn poster that flaps in the same wind
# as the litter. Nothing bright sits behind the car's roof line (the camera
# sees the car against wall x 0.5..7 m, y below about 2.2 m). One MultiMesh,
# one draw call. NEON_GRAFFITI=0 turns it off.

const SITE := Vector3(0.0, -600.0, 0.0)
const SODIUM_LIGHT := Color(1.0, 0.62, 0.3)
const STREET_LEN := 90.0
const ROAD_W := 30.0
const WALL_H := 7.0
const CAM_FAR := 110.0
const CAM_FOV := 48.0
## The camera breathes a little so the picture is not a still.
const SWAY_M := 0.18
const SWAY_SECS := 17.0

const LampLife := preload("res://scripts/world/lamp_life.gd")
const Graffiti := preload("res://scripts/world/graffiti.gd")
## Paint sits this far off a face, past z-fighting.
const PAINT_LIFT := 0.012
## The shutter's front face is this far in front of the wall face.
const SHUTTER_FACE := 0.08
## The district and chunk index lamp life is asked for. Chunk 1 is not a
## banner chunk (every third lamp wears one); the lamp has no banner here.
const LIFE_DISTRICT := "downtown"
const LIFE_CHUNK := 1
## Litter lane, title space. Lamp life blows litter along chunk +X; the root
## frame is turned a quarter turn so that is world -Z: from the road, past the
## camera side of the car, toward the kerb. The lane centre is LITTER_Z and the
## pieces cross LITTER_HALF either side of it, and LITTER_SQUASH pulls the
## along-the-road spread (22 m in a chunk) in so the lane fits the picture.
const LITTER_AT := Vector3(-4.0, 0.0, 0.0)
const LITTER_Z := 4.8
const LITTER_HALF := 2.3
const LITTER_SQUASH := 0.45
## Gust phases of the two litter sets (0..1 of the 24.5 s gust period): one
## every ~12 s. The world's chunks use 17-32 s.
const GUST_PERIOD_SEED := 0.5
const GUST_PHASES := [0.10, 0.60]
## The manhole: round, on the road between the camera and the car, in the
## lamp's pool.
const VENT_AT := Vector3(-6.6, 0.0, 4.4)
## The bat: custom-data period seed 0.05 is a flight every 15 s (the world's
## lamps are 14-34 s).
const BAT_PERIOD_SEED := 0.05
## Wind: still-air rest value is lamp life's own default; a gale on a held
## turbo. Wind rises with the turbo at once and falls back over WIND_FALL_SECS.
const WIND_REST := 0.6
const WIND_MAX := 2.0
const WIND_FALL_SECS := 3.0
## Street-life events (M8): one at a time, none before FIRST_EVENT_AT.
const FIRST_EVENT_AT := 10.0
const NEIGHBOUR_BOOST := 0.85
const NEIGHBOUR_HOLD := 4.0
const NEIGHBOUR_COOLDOWN := 60.0
const BIG_BLOW := 0.7
const DOUBLE_BLOW_SECS := 20.0
const PIGEON_BOOST := 0.6
const CAT_BOOST := 0.7
## The bat's flight at the title lamp (lamp_life.gd's swarm shader with
## BAT_PERIOD_SEED and the 0.2 phase seed below): period and length at rest.
const BAT_PERIOD := 14.0 + 20.0 * BAT_PERIOD_SEED
const BAT_PHASE := 0.2 * BAT_PERIOD
const BAT_LEN := 2.6
const BAT_MARGIN := 0.3
const SNAP := "res://assets/ui/sfx/blind_snap.wav"
const CLAP := "res://assets/ui/sfx/wing_clap.wav"
const SQUEAK := "res://assets/ui/sfx/rat_squeak.wav"
const SNAP_DB := -22.0
const CLAP_DB := -14.0
const SQUEAK_DB := -20.0

var kind := ""
var camera: Camera3D
var car: Node3D
var lamp_light: SpotLight3D
var _t := 0.0
var _cam_home := Vector3.ZERO
var _look := Vector3.ZERO
## The lamp's transform (the pole's origin and which way its arm reaches),
## set by _build_lamp; lamp life reads the head and the pool from it.
var _lamp_xf := Transform3D.IDENTITY
var life_root: Node3D
var wall_art: Node3D
## The graffiti items placed on the wall (what tests and shots read).
var graffiti_items: Array = []
## What _build_lamp_life wrote (a MultiMesh does not hand its data back on the
## headless renderer, so tests and shots read it from here): litter_xf, the
## two litter custom colours, vent_xf (the manhole cover), vent_round, moth_xf
## and moth_custom.
var life := {}
var _wind_target := WIND_REST
var _wind_now := WIND_REST
## Roaches (title_roaches.gd): the clock the shader runs on, where the slot
## cycles count from, when the scare began (-1: not scared), the schedule and
## the environment the runs are laid in (set_car writes them).
const SKITTER := "res://assets/ui/sfx/roach_skitter.wav"
const SKITTER_DB := -24.0
var roach_clock := 0.0
var roach_origin := 0.0
var roach_scare_t := -1.0
var roach_running := false
var roach_frozen := false
var roach_sched: Array[Color] = []
var roach_env := {}
var _scare := 0.0
var _calm_since := 0.0
var _skitter: AudioStreamPlayer
## Rats (title_rats.gd): their own origin and scare, on the roach clock.
var rat_origin := 0.0
var rat_scare_t := -1.0
var rat_sched: Array[Color] = []
var _rat_calm_since := 0.0
## Street life (title_street_life.gd): the event clocks the shaders read.
var neighbour_wake_t := -1.0
var pigeon_lift_t := -1.0
var pigeon_ret: Array[float] = []
var cat_leave_t := -1.0
var cat_back_t := -1.0
var shoes_wrap_t := -1.0
var _event_until := 0.0
var _neighbour_last := -1000.0
var _boost_hi_secs := 0.0
var _blows: Array[float] = []
var _snap_at := -1.0
var _lift_count := 0
var _critters := true
var _snap: AudioStreamPlayer
var _clap: AudioStreamPlayer
var _squeak: AudioStreamPlayer
## The time probe: what the shaders' TIME was (mod 60 s) at roach clock
## _probe_clock, or -1 while unknown (headless, or not read yet).
var _probe_vp: SubViewport
var _probe_frames := 0
var _probe_time := -1.0
var _probe_clock := 0.0
var _probe_pending := 0.0

func _init(car_kind: String) -> void:
	name = "TitleKerbside"
	kind = car_kind
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = SITE
	_build_street()
	_build_graffiti()
	_build_lamp()
	_build_lamp_life()
	_skitter = AudioStreamPlayer.new()
	_skitter.name = "Skitter"
	_skitter.bus = &"UI"
	_skitter.volume_db = SKITTER_DB
	if ResourceLoader.exists(SKITTER):
		_skitter.stream = load(SKITTER)
	add_child(_skitter)
	_snap = _player("BlindSnap", SNAP, SNAP_DB)
	_clap = _player("WingClap", CLAP, CLAP_DB)
	_squeak = _player("RatSqueak", SQUEAK, SQUEAK_DB)
	_build_time_probe()
	set_car(car_kind)
	camera = Camera3D.new()
	camera.fov = CAM_FOV
	camera.near = 0.2
	camera.far = CAM_FAR
	add_child(camera)

func _ready() -> void:
	_place_camera()

## A copy of a player car to look at: body and four wheels, origin on the
## ground, nose toward -Z. No physics and no script.
static func build_car(car_kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "TitleCar"
	var hubs: Array[Vector3] = []
	if NpcCarBuilder.is_npc(car_kind):
		var k: Dictionary = NpcCarBuilder.KINDS[car_kind]
		var vis := NpcCarBuilder.chassis_visual(car_kind, "stock", NpcCarBuilder.sheet_paint(car_kind))
		vis.position.y = float(k.rest_y)
		root.add_child(vis)
		for sx: float in [1.0, -1.0]:
			for sz: float in [-1.0, 1.0]:
				var hub := Vector3(float(k.wheel_x) * sx, float(k.wheel_r), float(k.axle_z) * sz)
				var wheel := NpcCarBuilder.wheel_visual(car_kind, "stock", hub)
				wheel.position = hub
				root.add_child(wheel)
				hubs.append(hub)
	else:
		# The coupe, and anything that wears the coupe's body.
		var vis := P1CoupeBuilder.build_chassis_visual()
		vis.position.y = -P1CoupeBuilder.BODY_LIFT
		root.add_child(vis)
		for sx: float in [1.0, -1.0]:
			for sz: float in [-1.0, 1.0]:
				var hub := Vector3(P1CoupeBuilder.DESIGN_WHEEL_X * sx, P1CoupeBuilder.DESIGN_WHEEL_R, 1.25 * sz)
				var wheel := P1CoupeBuilder.build_wheel_visual(P1CoupeBuilder.DESIGN_WHEEL_R, hub)
				wheel.position = hub
				root.add_child(wheel)
				hubs.append(hub)
	var half_w := 0.9
	var half_l := 2.2
	for h in hubs:
		half_w = maxf(half_w, absf(h.x) + 0.14)
		half_l = maxf(half_l, absf(h.z) + 0.9)
	root.set_meta("half_w", half_w)
	root.set_meta("half_l", half_l)
	return root

## Parks a copy of this car at the kerb (again, when the player picks another).
func set_car(car_kind: String) -> void:
	if car != null:
		car.queue_free()
	kind = car_kind
	car = build_car(car_kind)
	var half_w: float = car.get_meta("half_w")
	var half_l: float = car.get_meta("half_l")
	car.rotation.y = PI * 0.5                  # along the street, nose toward -X
	car.position = Vector3(0.0, 0.0, half_w + 0.3)
	add_child(car)
	car.add_child(_ground_shadow(half_w, half_l))
	_place_roaches()
	if is_inside_tree():
		_place_camera()

## Where the camera rests: from the road, low, three-quarter front. The car
## sits right of centre so the name and the menu have the left of the picture.
## Low and looking up a little, so the lamp head is in the picture too.
func _camera_home() -> Vector3:
	var half_l: float = car.get_meta("half_l")
	var half_w: float = car.get_meta("half_w")
	return Vector3(-(half_l + 6.0), 0.55, car.position.z + half_w + 7.0)

func _place_camera() -> void:
	var half_l: float = car.get_meta("half_l")
	_cam_home = _camera_home()
	_look = Vector3(-half_l - 1.5, 3.0, car.position.z - 2.2)
	_aim()

## The lid ajar and the roaches' runs, laid out for this car: the lid slides
## away from the camera so the hole shows on the camera's side, the car-shadow
## exit is the shadow's corner nearest the hole. Writes the schedule and the
## shader's environment; the clock is untouched (a car swap mid-run is fine).
func _place_roaches() -> void:
	if not LampLife.enabled or life_root == null:
		return
	var home := _camera_home()
	var near := Vector2(home.x - VENT_AT.x, home.z - VENT_AT.z).normalized()
	var cover := (life_root.get_node(^"VentCovers") as MultiMeshInstance3D).multimesh
	var lid := TitleRoaches.lid_transform(VENT_AT, near)
	cover.set_instance_transform(0, lid)
	life["cover_xf"] = lid
	# steam from the crescent, not from under the lid
	var steam := (life_root.get_node(^"SteamVents") as MultiMeshInstance3D).multimesh
	var crescent := VENT_AT + Vector3(near.x, 0.0, near.y) * 0.3
	steam.set_instance_transform(0, Transform3D(Basis(Vector3.UP, PI * 0.5), crescent))
	life["steam_at"] = crescent
	var half_l: float = car.get_meta("half_l")
	var half_w: float = car.get_meta("half_w")
	var car_exit := Vector2(-half_l - 0.3, car.position.z + half_w + 0.3)
	roach_env = TitleRoaches.env(VENT_AT, near, car_exit)
	var mm := (life_root.get_node(^"Roaches") as MultiMeshInstance3D).multimesh
	roach_sched = TitleRoaches.fill(mm, roach_env)
	life["roach_near"] = near
	life["roach_car_exit"] = car_exit

## The menu is up: the roach clock starts (once), so the first one is out
## about six seconds in.
func start_roaches() -> void:
	roach_running = true

## Screenshots: hold the roaches where they are (true) or let them run.
func freeze_roaches(hold: bool) -> void:
	roach_frozen = hold
	if not hold:
		_probe_frames = 0   # the clock stood still while TIME ran: read it again

## Moves the roach clock to t and writes it (screenshots, tests).
func set_roach_clock(t: float) -> void:
	roach_clock = t
	TitleRoaches.set_uniform("clock", roach_clock)
	TitleRats.set_uniform("clock", roach_clock)
	TitleStreetLife.set_clock(roach_clock)

## The street clock every shader here runs on (the roaches', M7).
func street_clock() -> float:
	return roach_clock

## The scare, 0..1 (the turbo's menu_boost; a passing car later). Crossing
## 0.5 upward sends every roach out running for cover; once it has been under
## 0.2 for CALM_SECS the runs start again. Uniforms are written only on those
## transitions.
func set_scare(v: float) -> void:
	v = clampf(v, 0.0, 1.0)
	var was := _scare
	_scare = v
	_scare_rats(v, was)
	if roach_sched.is_empty():
		return
	if v > TitleRoaches.SCARE_ON and roach_scare_t < 0.0:
		var fleeing := TitleRoaches.out_count(roach_sched, roach_env, roach_clock, roach_origin, -1.0)
		roach_scare_t = roach_clock
		TitleRoaches.set_uniform("scare_t", roach_scare_t)
		if fleeing >= 2 and _skitter != null and _skitter.stream != null:
			_skitter.play()
	elif v < TitleRoaches.SCARE_OFF and roach_scare_t >= 0.0:
		if was >= TitleRoaches.SCARE_OFF:
			_calm_since = roach_clock
		if roach_clock - _calm_since >= TitleRoaches.CALM_SECS:
			roach_scare_t = -1.0
			roach_origin = roach_clock
			TitleRoaches.set_uniform("scare_t", -1.0)
			TitleRoaches.set_uniform("origin", roach_origin)

## Where every roach is now (or at clock t): a list of {out, pos}, through the
## same run function the shader uses.
func roach_positions(t := -1.0) -> Array:
	if roach_sched.is_empty():
		return []
	return TitleRoaches.positions(roach_sched, roach_env, roach_clock if t < 0.0 else t, roach_origin, roach_scare_t)

func _run_roaches(delta: float) -> void:
	if not roach_running or roach_frozen or roach_sched.is_empty():
		return
	set_roach_clock(roach_clock + delta)
	# the calm-down after a scare counts on the clock, whether or not the
	# scare value is still being written
	if (roach_scare_t >= 0.0 or rat_scare_t >= 0.0) and _scare < TitleRoaches.SCARE_OFF:
		set_scare(_scare)

func _aim() -> void:
	var sway := sin(_t * TAU / SWAY_SECS)
	camera.position = _cam_home + Vector3(sway * SWAY_M, 0.03 * sin(_t * TAU / (SWAY_SECS * 0.61)), 0.0)
	camera.look_at(to_global(_look), Vector3.UP)

func _exit_tree() -> void:
	# the wind is lamp life's one global number: hand it back at rest
	if LampLife.enabled:
		LampLife.set_wind(LampLife.DEFAULT_WIND)
	Graffiti.set_wind(LampLife.DEFAULT_WIND)

## The wind the title wants (0 still, 1 breeze, 2 gale). The turbo calls this
## each frame with lerpf(WIND_REST, WIND_MAX, boost); a higher wind is taken at
## once, a lower one is eased down over WIND_FALL_SECS.
func set_title_wind(w: float) -> void:
	_wind_target = clampf(w, 0.0, WIND_MAX)

func wind_now() -> float:
	return _wind_now

func _process(delta: float) -> void:
	if not visible or camera == null or not camera.current:
		return
	_t += delta
	_aim()
	_ease_wind(delta)
	_run_roaches(delta)
	_run_street(delta)
	_run_time_probe()
	if _critters != GameSettings.critters:
		set_critters(GameSettings.critters)

func _ease_wind(delta: float) -> void:
	var w := _wind_now
	if _wind_target >= w:
		w = _wind_target
	else:
		w = maxf(_wind_target, w - (WIND_MAX - WIND_REST) / WIND_FALL_SECS * delta)
	if not is_equal_approx(w, _wind_now):
		_wind_now = w
		if LampLife.enabled:
			LampLife.set_wind(w)
			TitleStreetLife.set_wind(w)
		Graffiti.set_wind(w)

func _build_street() -> void:
	# Asphalt: the road, from the kerb out past the camera.
	_slab(Vector3(STREET_LEN, 0.2, ROAD_W), Vector3(0.0, -0.1, ROAD_W * 0.5),
		_flat(Color(0.075, 0.075, 0.08), 0.82))
	# Kerb and sidewalk, at the heights the road chunks use.
	var kerb_h := RoadChunkBuilder.KERB_H
	var kerb_w := RoadChunkBuilder.CURB_W
	var walk_w := RoadChunkBuilder.SIDEWALK_W
	_slab(Vector3(STREET_LEN, kerb_h, kerb_w), Vector3(0.0, kerb_h * 0.5, -kerb_w * 0.5),
		_flat(RoadChunkBuilder.KERB_COLOR, 0.9))
	_slab(Vector3(STREET_LEN, kerb_h, walk_w), Vector3(0.0, kerb_h * 0.5, -kerb_w - walk_w * 0.5),
		_flat(Color(0.2, 0.19, 0.18), 0.95))
	# A blank wall closes the picture behind the sidewalk, with one shutter.
	var wall_z := -kerb_w - walk_w
	_slab(Vector3(STREET_LEN, WALL_H, 0.4), Vector3(0.0, WALL_H * 0.5, wall_z - 0.2),
		_flat(Color(0.16, 0.13, 0.115), 0.95))
	_slab(Vector3(3.6, 2.7, 0.1), Vector3(1.9, kerb_h + 1.35, wall_z + 0.03),
		_flat(Color(0.2, 0.21, 0.22), 0.55, 0.6))
	_slab(Vector3(STREET_LEN, 0.25, 0.5), Vector3(0.0, 3.6, wall_z + 0.05),
		_flat(Color(0.11, 0.09, 0.08), 0.95))

## The wall's graffiti (see the header). Items are in title space: the wall
## face is at wall_z and faces +Z (toward the road and the camera), so a quad
## with the identity basis lies flat on it. Order matters where pieces
## overlap: later items are lifted a little further off the wall.
func _build_graffiti() -> void:
	wall_art = Node3D.new()
	wall_art.name = "WallArt"
	add_child(wall_art)
	var wall_z := -RoadChunkBuilder.CURB_W - RoadChunkBuilder.SIDEWALK_W
	var on_wall := wall_z + PAINT_LIFT
	var on_shutter := wall_z + SHUTTER_FACE + PAINT_LIFT
	graffiti_items = [
		# the big piece, high on the wall left of the car, above the ledge
		{"xf": Transform3D(Basis(Vector3.BACK, 0.025), Vector3(-4.2, 4.7, on_wall)),
			"cell": "piece_pike_speed", "fade": 0.85, "tint": "white"},
		# the roller patch that buffed its right end
		{"xf": Transform3D(Basis(), Vector3(-2.0, 4.55, on_wall + 0.006)),
			"cell": "roller_1", "fade": 1.0, "tint": "white"},
		# tags round the shutter: a throw-up left of the lamp post, a
		# handstyle between the post and the shutter, an older one low and
		# far left
		{"xf": Transform3D(Basis(Vector3.BACK, -0.04), Vector3(-3.6, 2.0, on_wall)),
			"cell": "tag_kemr", "fade": 0.9, "tint": "white"},
		{"xf": Transform3D(Basis(Vector3.BACK, 0.06), Vector3(-0.6, 2.3, on_wall)),
			"cell": "tag_dusk", "fade": 0.8, "tint": "white"},
		{"xf": Transform3D(Basis(Vector3.BACK, -0.08), Vector3(-6.3, 1.5, on_wall)),
			"cell": "tag_ironbridge", "fade": 0.65, "tint": "white", "scale": 1.15},
		# the NO PARKING stencil on the shutter, with a tag sprayed over it
		{"xf": Transform3D(Basis(), Vector3(1.9, 1.95, on_shutter)),
			"cell": "stencil_no_parking", "fade": 0.75, "tint": "white", "scale": 1.3},
		{"xf": Transform3D(Basis(Vector3.BACK, -0.1), Vector3(2.2, 1.65, on_shutter + 0.008)),
			"cell": "tag_meks", "fade": 0.95, "tint": "white"},
		# a torn poster, far left, flapping in the litter's wind
		{"xf": Transform3D(Basis(Vector3.BACK, 0.03), Vector3(-7.6, 1.8, on_wall)),
			"cell": "poster_2", "fade": 0.9, "tint": "white", "flap": true},
	]
	Graffiti.create(wall_art, graffiti_items.size())
	Graffiti.place(wall_art, graffiti_items)

func _build_lamp() -> void:
	var post := MeshInstance3D.new()
	post.mesh = RoadChunkBuilder.lamp_mesh()
	# The mesh's arm reaches toward -X; turn it to reach over the road (+Z).
	post.rotation.y = PI * 0.5
	post.position = Vector3(-1.1, RoadChunkBuilder.KERB_H, -RoadChunkBuilder.LAMP_SETBACK - RoadChunkBuilder.CURB_W)
	add_child(post)
	lamp_light = SpotLight3D.new()
	lamp_light.light_color = SODIUM_LIGHT
	lamp_light.light_energy = 14.0
	lamp_light.spot_range = 16.0
	lamp_light.spot_angle = 58.0
	lamp_light.spot_angle_attenuation = 0.7
	lamp_light.spot_attenuation = 0.8
	lamp_light.shadow_enabled = false
	lamp_light.position = post.position + Vector3(0.0, RoadChunkBuilder.LAMP_POLE_H - 0.3, 1.7)
	lamp_light.rotation.x = -PI * 0.5   # straight down
	add_child(lamp_light)
	_lamp_xf = Transform3D(Basis(Vector3.UP, PI * 0.5), post.position)

## Lamp life for this one lamp (see the header). Lamp life wants chunk space,
## with the road along Z and the wind across it (+X); here the street runs along
## X, so the litter and the steam are given a quarter-turned frame. The vent and
## the bat are forced rather than left to the world's dice.
func _build_lamp_life() -> void:
	life_root = Node3D.new()
	life_root.name = "LampLife"
	add_child(life_root)
	LampLife.create_nodes(life_root, 1)
	life_root.add_child(TitleRoaches.create_node())
	life_root.add_child(TitleRats.create_node())
	for n in TitleStreetLife.create_all():
		n.visible = LampLife.enabled
		life_root.add_child(n)
	var litter := (life_root.get_node(^"WindLitter") as MultiMeshInstance3D).multimesh
	litter.instance_count = 2   # two gust phases (data is written below)
	var turn := Basis(Vector3.UP, PI * 0.5)
	var litter_xf := Transform3D(turn * Basis.from_scale(Vector3(1.0, 1.0, LITTER_SQUASH)), LITTER_AT)
	LampLife.apply(life_root, LIFE_CHUNK, LIFE_DISTRICT, [_lamp_xf], litter_xf,
		-LITTER_Z - LITTER_HALF, -LITTER_Z + LITTER_HALF)
	if not LampLife.enabled:
		return
	# 2. two litter sets, half a gust period apart
	litter.visible_instance_count = 2
	var litter_custom: Array[Color] = []
	for i in 2:
		var c := Color(-LITTER_Z, LITTER_HALF, GUST_PERIOD_SEED, GUST_PHASES[i])
		litter.set_instance_transform(i, litter_xf)
		litter.set_instance_custom_data(i, c)
		litter_custom.append(c)
	life["litter_xf"] = litter_xf
	life["litter_custom"] = litter_custom
	# 3. the manhole, round, with its steam leaning the way the litter blows
	var steam := (life_root.get_node(^"SteamVents") as MultiMeshInstance3D).multimesh
	var cover := (life_root.get_node(^"VentCovers") as MultiMeshInstance3D).multimesh
	steam.visible_instance_count = 1
	cover.visible_instance_count = 1
	steam.set_instance_transform(0, Transform3D(turn, VENT_AT))
	steam.set_instance_custom_data(0, Color(0.31, 0.0, 0.0, 0.0))   # seed, 0 = round
	cover.set_instance_transform(0, Transform3D(Basis(), VENT_AT))   # ajar once the car is parked (_place_roaches)
	life["vent_xf"] = Transform3D(Basis(), VENT_AT)
	life["vent_round"] = true
	# the hole itself: a black disc under the lid, showing where the lid is not
	life_root.add_child(TitleRoaches.hole_disc(VENT_AT))
	# 4. moths at the lamp head, and the bat on its flight every 15 s
	var moths := (life_root.get_node(^"LampMoths") as MultiMeshInstance3D).multimesh
	moths.visible_instance_count = 1
	moths.set_instance_transform(0, _lamp_xf)
	moths.set_instance_custom_data(0, Color(0.37, BAT_PERIOD_SEED, 0.2, 1.0))
	life["moth_xf"] = _lamp_xf
	life["moth_custom"] = Color(0.37, BAT_PERIOD_SEED, 0.2, 1.0)
	# 5. the rats' schedule (M9) and the street's event uniforms at rest (M8)
	rat_sched = TitleRats.fill((life_root.get_node(^"Rats") as MultiMeshInstance3D).multimesh)
	TitleRats.set_uniform("origin", 0.0)
	TitleRats.set_uniform("scare_t", -1.0)
	TitleStreetLife.set_uniform("neighbour", "wake_t", -1.0)
	TitleStreetLife.set_uniform("pigeon", "lift_t", -1.0)
	TitleStreetLife.set_uniform("cat", "leave_t", -1.0)
	TitleStreetLife.set_uniform("cat", "back_t", -1.0)
	TitleStreetLife.set_uniform("wire", "wrap_t", -1.0)
	TitleStreetLife.set_wind(_wind_now)
	set_critters(GameSettings.critters)

# ---------------------------------------------------------------- rats (M9)

func _player(node_name: String, path: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.bus = &"UI"
	p.volume_db = db
	if ResourceLoader.exists(path):
		p.stream = load(path)
	add_child(p)
	return p

static func _play(p: AudioStreamPlayer) -> void:
	if p != null and p.stream != null:
		p.play()

## The rats' side of set_scare: above SCARE_ON a rat that is out bolts (a
## faint scratch and squeak); once the scare has been under SCARE_OFF for
## CALM_SECS the cycles start over from now, so none come in before then.
func _scare_rats(v: float, was: float) -> void:
	if rat_sched.is_empty():
		return
	if v > TitleRats.SCARE_ON and rat_scare_t < 0.0:
		var bolting := TitleRats.out_count(rat_sched, roach_clock, rat_origin, -1.0)
		rat_scare_t = roach_clock
		TitleRats.set_uniform("scare_t", rat_scare_t)
		if bolting >= 1:
			_play(_squeak)
	elif v < TitleRats.SCARE_OFF and rat_scare_t >= 0.0:
		if was >= TitleRats.SCARE_OFF:
			_rat_calm_since = roach_clock
		if roach_clock - _rat_calm_since >= TitleRats.CALM_SECS:
			rat_scare_t = -1.0
			rat_origin = roach_clock
			TitleRats.set_uniform("scare_t", -1.0)
			TitleRats.set_uniform("origin", rat_origin)

## Where every rat is now (or at clock t): a list of {out, pos, sit}.
func rat_positions(t := -1.0) -> Array:
	if rat_sched.is_empty():
		return []
	return TitleRats.positions(rat_sched, roach_clock if t < 0.0 else t, rat_origin, rat_scare_t)

## Settings > Game > "Roaches and rats": off hides the roaches, the rats and
## the flies over the bin bags. The moths and the rest stay.
func set_critters(on: bool) -> void:
	_critters = on
	if life_root == null:
		return
	for n in ["Roaches", "Rats", "Flies"]:
		var node := life_root.get_node_or_null(NodePath(n)) as Node3D
		if node != null:
			node.visible = on and LampLife.enabled

func critters_on() -> bool:
	return _critters

# ---------------------------------------------------------------- street (M8)

## The turbo blew off at this boost (title_screen.gd): a second big one
## inside DOUBLE_BLOW_SECS wakes the neighbour.
func blow_off(boost: float) -> void:
	if boost >= BIG_BLOW:
		_blows.append(roach_clock)
		while _blows.size() > 4:
			_blows.pop_front()

## A car passing within a few metres (nothing on the title yet; the hook for
## later): the pigeons lift as on a boost.
func startle_pigeons() -> void:
	_try_lift_pigeons(true)

func event_free(t: float) -> bool:
	return t >= FIRST_EVENT_AT and t >= _event_until

func _double_blow(t: float) -> bool:
	if _blows.size() < 2:
		return false
	return t - _blows[_blows.size() - 2] <= DOUBLE_BLOW_SECS

func pigeons_settled(t: float) -> bool:
	if pigeon_lift_t < 0.0:
		return true
	for i in TitleStreetLife.PIGEON_COUNT:
		if TitleStreetLife.pigeon_state(i, t, pigeon_lift_t, pigeon_ret[i]) != "rest":
			return false
	return true

func cat_home(t: float) -> bool:
	return TitleStreetLife.cat_state(t, cat_leave_t, cat_back_t) == "sit"

func _run_street(delta: float) -> void:
	if not roach_running or roach_frozen or life_root == null or not LampLife.enabled:
		return
	var t := roach_clock
	# the neighbour: 4 s of hard boost, or the second big blow-off in 20 s
	_boost_hi_secs = _boost_hi_secs + delta if _scare > NEIGHBOUR_BOOST else 0.0
	if (_boost_hi_secs >= NEIGHBOUR_HOLD or _double_blow(t)) and t - _neighbour_last >= NEIGHBOUR_COOLDOWN and event_free(t):
		wake_neighbour()
	if _snap_at >= 0.0 and t >= _snap_at:
		_snap_at = -1.0
		_play(_snap)
	# the pigeons: boost over 0.6, all of them back on the arm, no bat
	if _scare > PIGEON_BOOST:
		_try_lift_pigeons(false)
	# the cat: boost over 0.7 while it sits there; it is back 45-90 s later
	if _scare > CAT_BOOST and cat_leave_t < 0.0 and event_free(t):
		leave_cat()
	if cat_leave_t >= 0.0 and cat_back_t >= 0.0 and t >= cat_back_t + TitleStreetLife.CAT_RUN_IN + TitleStreetLife.CAT_JUMP:
		cat_leave_t = -1.0
		cat_back_t = -1.0
		TitleStreetLife.set_uniform("cat", "leave_t", -1.0)
		TitleStreetLife.set_uniform("cat", "back_t", -1.0)
	# the shoes: a gale wraps them round the wire once
	if _wind_now >= TitleStreetLife.WRAP_WIND and (shoes_wrap_t < 0.0 or t > shoes_wrap_t + TitleStreetLife.WRAP_LEN + 2.0):
		wrap_shoes()

## The window lights, the blind snaps up, the shape stands there, the blind
## drops, the light goes off (TitleStreetLife.WAKE_LEN seconds).
func wake_neighbour() -> void:
	var t := roach_clock
	neighbour_wake_t = t
	_neighbour_last = t
	_boost_hi_secs = 0.0
	_blows.clear()
	_event_until = t + TitleStreetLife.WAKE_LEN
	_snap_at = t + TitleStreetLife.WAKE_BLIND_UP
	TitleStreetLife.set_uniform("neighbour", "wake_t", t)

func _try_lift_pigeons(force: bool) -> void:
	var t := roach_clock
	if not pigeons_settled(t) or not (force or event_free(t)):
		return
	var lift_len := TitleStreetLife.LIFT_FLY + TitleStreetLife.LIFT_STAGGER * float(TitleStreetLife.PIGEON_COUNT)
	if not bat_clear(t, t + lift_len):
		return
	lift_pigeons()

## The flock lifts off together; each bird's return clock is written to its
## custom data (20-40 s on, one by one, clear of the bat).
func lift_pigeons() -> void:
	var t := roach_clock
	pigeon_lift_t = t
	_lift_count += 1
	_event_until = t + TitleStreetLife.LIFT_FLY + TitleStreetLife.LIFT_STAGGER * float(TitleStreetLife.PIGEON_COUNT)
	pigeon_ret.clear()
	var mm := (life_root.get_node(^"Pigeons") as MultiMeshInstance3D).multimesh
	var prev := t
	for i in TitleStreetLife.PIGEON_COUNT:
		var h := TitleRoaches.hs(0.41 + 0.137 * float(_lift_count), i)
		var ret := t + TitleStreetLife.LIFT_STAGGER * float(i) + TitleStreetLife.LIFT_FLY \
			+ TitleStreetLife.RETURN_MIN + (TitleStreetLife.RETURN_MAX - TitleStreetLife.RETURN_MIN) * h
		ret = maxf(ret, prev + 3.0)
		while not bat_clear(ret, ret + TitleStreetLife.RETURN_FLY):
			ret += 0.5
		pigeon_ret.append(ret)
		prev = ret
		mm.set_instance_custom_data(i, TitleStreetLife.pigeon_custom(i, ret))
	TitleStreetLife.set_uniform("pigeon", "lift_t", t)
	_play(_clap)

## The cat drops off the box and runs off right; back_t is when it comes
## running back along the sidewalk.
func leave_cat() -> void:
	var t := roach_clock
	cat_leave_t = t
	_event_until = t + TitleStreetLife.CAT_DROP + TitleStreetLife.CAT_RUN
	var h := TitleRoaches.hs(0.77 + 0.3 * float(_lift_count), 3 + int(t) % 7)
	cat_back_t = t + TitleStreetLife.CAT_DROP + TitleStreetLife.CAT_RUN \
		+ TitleStreetLife.CAT_BACK_MIN + (TitleStreetLife.CAT_BACK_MAX - TitleStreetLife.CAT_BACK_MIN) * h
	TitleStreetLife.set_uniform("cat", "leave_t", cat_leave_t)
	TitleStreetLife.set_uniform("cat", "back_t", cat_back_t)

func wrap_shoes() -> void:
	shoes_wrap_t = roach_clock
	TitleStreetLife.set_uniform("wire", "wrap_t", shoes_wrap_t)

# ---- the bat and the time probe

## The shaders' TIME at street clock t, mod 60 s, or -1 when the probe has
## not read it (headless, or the first frames).
func shader_time(t: float) -> float:
	if _probe_time < 0.0:
		return -1.0
	return fposmod(_probe_time + (t - _probe_clock), 60.0)

## True when the bat is not crossing the pool anywhere in [t0, t1] (street
## clock). Unknown shader time counts as clear.
func bat_clear(t0: float, t1: float) -> bool:
	var st := shader_time(t0)
	if st < 0.0:
		return true
	var m := fposmod(st + BAT_PHASE, BAT_PERIOD)
	return m >= BAT_LEN + BAT_MARGIN and m + (t1 - t0) <= BAT_PERIOD - BAT_MARGIN

const PROBE_SHADER := """
shader_type canvas_item;
void fragment() {
	float f = fract(TIME / 60.0);
	float hi = floor(f * 255.0);
	COLOR = vec4(hi / 255.0, f * 255.0 - hi, 0.0, 1.0);
}
"""

## A 4x4 viewport whose one shader writes TIME into its pixels; read back
## once a few frames in (and again now and then), it tells where the bat is.
func _build_time_probe() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_probe_vp = SubViewport.new()
	_probe_vp.name = "TimeProbe"
	_probe_vp.size = Vector2i(4, 4)
	_probe_vp.disable_3d = true
	_probe_vp.transparent_bg = false
	_probe_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var rect := ColorRect.new()
	rect.size = Vector2(4, 4)
	var sh := Shader.new()
	sh.code = PROBE_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	rect.material = m
	_probe_vp.add_child(rect)
	add_child(_probe_vp)

func _run_time_probe() -> void:
	# the offset only holds while the street clock runs with the frames
	if _probe_vp == null or not roach_running or roach_frozen:
		return
	_probe_frames += 1
	var k := _probe_frames % 1800
	if k == 1:
		# draw it once on this frame; the clock this frame is what it shows
		_probe_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_probe_pending = roach_clock
	elif k == 4:
		var img := _probe_vp.get_texture().get_image()
		if img != null and not img.is_empty():
			var c := img.get_pixel(1, 1)
			_probe_time = (roundf(c.r * 255.0) + c.g) / 255.0 * 60.0
			_probe_clock = _probe_pending

func probe_known() -> bool:
	return _probe_time >= 0.0

func _slab(size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = at
	add_child(mi)

static func _flat(colour: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = rough
	m.metallic = metal
	return m

## The car's shadow under the lamp: a soft dark quad just above the asphalt.
static func _ground_shadow(half_w: float, half_l: float) -> MeshInstance3D:
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.9))
	grad.set_color(1, Color(0, 0, 0, 0.0))
	grad.add_point(0.55, Color(0, 0, 0, 0.8))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.albedo_color = Color(0, 0, 0, 1)
	var plane := PlaneMesh.new()
	plane.size = Vector2(half_w * 2.0 + 0.9, half_l * 2.0 + 0.9)
	var mi := MeshInstance3D.new()
	mi.name = "GroundShadow"
	mi.mesh = plane
	mi.material_override = mat
	mi.position.y = 0.012
	return mi
