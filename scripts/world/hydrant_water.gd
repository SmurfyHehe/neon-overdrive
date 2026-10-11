## A burst hydrant's water (breakable world I3 + MA7a).
##
## PropBreak calls burst() when the player knocks a hydrant off. From then on,
## for the rest of the night, that hydrant has an entry here:
##
##  - It sprays for 20-25 game minutes (from the hydrant's place, so always
##    the same), the last TRICKLE_MIN of them sinking to a trickle, then runs
##    dry. No fire crew. One in four (also from its place) is a hisser: a low
##    sideways spray instead of the tall gusher.
##  - While it sprays it has a water card (one quad, a scrolling shader, lit
##    amber like everything under the lamps), a little mist and a roar made
##    in code that falls off with distance. At most MAX_SPRAYS spray at once:
##    a third one turns the oldest into a plain wet patch.
##  - A wet patch grows down the gutter (downhill, GROW_M over GROW_SECS) and
##    stays after the water stops, drying over DRY_MIN game minutes. A wheel
##    on it gets shallow-water grip (WetGrip.patch, 0.90) on any night, wet
##    or dry.
##  - Driving through a gusher: a little drag (once per pass), drumming on
##    the roof, and in the cockpit view a sheet of water on the screen with
##    the wipers going fast for 3 s; 2 s in it takes one step off the dirt.
##  - A wheel over a gusher's base is pushed up gently (a small bounce).
##  - After its tyres touch the water the car leaves fading dark tracks for
##    TRACK_M metres, laid through the skid-mark pool.
##
## Everything the player feels is worked out on the straight road (x across,
## s along), so it holds on a bend and across the floating origin. The spray
## and the patch are children of the hydrant's chunk and are put back by
## dress_chunk() when that chunk returns.
##
## No class_name on purpose: preload it, so no class cache refresh is needed.
extends Node3D

const Props := preload("res://scripts/world/roadside_props.gd")
const RoadWetScript := preload("res://scripts/world/road_wet.gd")

const MAX_SPRAYS := 2
const SPRAY_MIN := 20.0        # game minutes a hydrant sprays, at least
const SPRAY_EXTRA := 6         # ...plus 0..5 more, from its place
const TRICKLE_MIN := 5.0       # the last game minutes, sinking (20 s on the default clock)
const DRY_MIN := 45.0          # game minutes for the patch to dry once the water stops
const HISSER_IN := 4           # one in this many is a hisser
const GROW_M := 30.0
const GROW_SECS := 20.0
const PATCH_BACK := 2.5        # metres the patch reaches uphill of the hydrant
const PATCH_IN := 2.95         # how far it reaches from the hydrant toward the lanes
const PATCH_OUT := 1.2         # ...and behind it, across the pavement
const PATCH_ROAD_W := 2.2      # width of the drawn patch on the road
const HYDRANT_TO_KERB := 0.75  # hydrant to the kerb's road-side edge
const COLUMN_H := 7.0
const RISE_SECS := 0.6         # the jet takes this long to stand up after the hit
const COLUMN_R := 0.45         # a wheel this close to the base is over the jet
const DRAG_KMH := 1.5
const SHEET_SECS := 1.6
const WIPER_SECS := 3.0
const DIRT_AFTER := 2.0
const DIRT_STEP := 0.25
const LIFT_ACCEL := 2.6        # m/s^2 up, spread through the springs: a couple of cm
const TRACK_M := 100.0
const TRACK_STEP := 1.5
const REAL_SECONDS_PER_MIN := 4.0

var game: Node
var lift_enabled := true
## One per hydrant broken tonight (see _entry()).
var wet: Array = []
## Readouts for tests.
var drag_passes := 0
var dirt_steps := 0
var lift_ticks := 0
var tracks_laid := 0
var sheet := 0.0
var in_column := false

var _roots := {}               # chunk index -> root (PropBreak's own table)
var _own_minutes := 0.0        # the clock when the game has none (tools)
var _nodes: Array[Node3D] = []
var _node_of := PackedInt32Array()   # entry using each spray node, -1 = free
var _column_t := 0.0
var _out_t := 99.0
var _track_left := 0.0
var _track_gap := 0.0
var _track_last := [Vector3.ZERO, Vector3.ZERO]
var _track_has := false
var _patch_set := false
var _drum: AudioStreamPlayer
var _sheet_rect: ColorRect
var _tick := 0

static var _card_mat: ShaderMaterial
static var _patch_mat: ShaderMaterial
static var _roar: AudioStreamWAV
static var _drum_wav: AudioStreamWAV

const CARD_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

// One quad per burst hydrant. Gusher: turned to the camera about the
// vertical, stretched up from the base. Hisser: a low fan along the node's
// own +x (toward the lanes). power 1 = full spray, 0 = dry.
instance uniform float power = 1.0;
instance uniform float hisser = 0.0;
uniform float height = 7.0;
varying float fade;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	float u = VERTEX.y + 0.5;            // 0 at the base, 1 at the far end
	vec3 wp;
	if (hisser < 0.5) {
		vec3 to_cam = CAMERA_POSITION_WORLD - base;
		to_cam.y = 0.0;
		vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), normalize(to_cam + vec3(0.0001, 0.0, 0.0))));
		float w = mix(0.35, 1.5, u);     // a plume: wider at the top
		wp = base + side * VERTEX.x * w + vec3(0.0, 1.0, 0.0) * (0.15 + u * height * power);
	} else {
		vec3 along = normalize(MODEL_MATRIX[0].xyz);
		float reach = 3.2 * power;
		wp = base + along * (u * reach) + vec3(0.0, 1.0, 0.0) * (0.3 + VERTEX.x * (0.25 + 0.9 * u) + 0.5 * u * (1.0 - u));
	}
	vec4 vp = VIEW_MATRIX * vec4(wp, 1.0);
	fade = smoothstep(1.5, 5.0, -vp.z);  // never a big card in the lens
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	float u = 1.0 - UV.y;                // quad UV runs top to bottom
	float across = 1.0 - abs(UV.x - 0.5) * 2.0;
	float n = noise(vec2(UV.x * 7.0, u * 5.0 - TIME * 4.5)) * 0.6 + noise(vec2(UV.x * 17.0, u * 11.0 - TIME * 7.0)) * 0.4;
	float body = pow(across, 1.4) * smoothstep(1.0, 0.55, u) * smoothstep(0.0, 0.06, u);
	// water under sodium lamps: grey-white with an amber cast, never blue
	ALBEDO = mix(vec3(0.46, 0.42, 0.36), vec3(1.0, 0.84, 0.60), n * n);
	ALPHA = clamp(body * (0.35 + 0.65 * n) * 0.8, 0.0, 1.0) * smoothstep(0.0, 0.15, power) * fade;
}
"""

const PATCH_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

// A dark, glossy wet stain on the asphalt with soft edges. COLOR.a (the
// instance colour) is how wet it still is.
void fragment() {
	vec2 d = abs(UV - vec2(0.5)) * 2.0;
	float edge = smoothstep(1.0, 0.7, d.x) * smoothstep(1.0, 0.9, d.y);
	ALBEDO = vec3(0.012, 0.013, 0.017);
	ROUGHNESS = 0.07;
	SPECULAR = 0.9;
	ALPHA = edge * 0.6 * COLOR.a;
}
"""

const SHEET_SHADER := """
shader_type canvas_item;

// Water running down the windscreen (cockpit view only): the picture behind
// is pushed about and dulled for a moment. amount 1 = just hit, 0 = clear.
uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float amount = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	// the glass is the upper part of the view; the dash stays dry
	float glass = smoothstep(0.74, 0.56, uv.y) * amount;
	float n = noise(vec2(uv.x * 10.0, uv.y * 4.0 - TIME * 2.6));
	float m = noise(vec2(uv.x * 23.0 + 4.0, uv.y * 7.0 - TIME * 3.4));
	vec2 off = vec2(n - 0.5, m - 0.5) * 0.04 * glass;
	vec3 c = texture(screen, uv + off).rgb;
	c = mix(c, c * 0.8 + vec3(0.05, 0.043, 0.032), glass * 0.6);
	COLOR = vec4(c, step(0.002, glass));
}
"""

func _ready() -> void:
	_node_of.resize(MAX_SPRAYS)
	for j in MAX_SPRAYS:
		_node_of[j] = -1
		_nodes.append(_new_spray_node())
	_drum = AudioStreamPlayer.new()
	_drum.stream = _get_drum()
	_drum.bus = &"Tires"
	_drum.volume_db = -9.0
	add_child(_drum)
	var layer := CanvasLayer.new()
	layer.layer = -1   # over the 3D view, under every HUD and menu layer
	_sheet_rect = ColorRect.new()
	_sheet_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sheet_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHEET_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_sheet_rect.material = mat
	_sheet_rect.visible = false
	layer.add_child(_sheet_rect)
	add_child(layer)

static func _get_card_mat() -> ShaderMaterial:
	if _card_mat == null:
		var sh := Shader.new()
		sh.code = CARD_SHADER
		_card_mat = ShaderMaterial.new()
		_card_mat.shader = sh
	return _card_mat

static func _get_patch_mat() -> ShaderMaterial:
	if _patch_mat == null:
		var sh := Shader.new()
		sh.code = PATCH_SHADER
		_patch_mat = ShaderMaterial.new()
		_patch_mat.shader = sh
	return _patch_mat

## Filtered noise, looped: `hz` is the low-pass corner (a hiss of water high,
## drumming on a roof low), `beat` an amplitude wobble in Hz (0 = none).
static func _noise_loop(hz: float, beat: float, seed_value: int) -> AudioStreamWAV:
	var rate := 22050
	var n := rate
	var fade := rate / 10
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var lp := AudioDsp.lp(float(rate), hz)
	var hp := AudioDsp.hp(float(rate), 90.0)
	var s := PackedFloat32Array()
	s.resize(n + fade)
	for i in n + fade:
		var x := hp.step(lp.step(rng.randf_range(-1.0, 1.0)))
		if beat > 0.0:
			x *= 0.55 + 0.45 * absf(sin(float(i) / float(rate) * PI * beat))
		s[i] = x
	return AudioDsp.to_wav(AudioDsp.normalise(AudioDsp.seamless(s, n, fade), 0.7), rate, true)

static func _get_roar() -> AudioStreamWAV:
	if _roar == null:
		_roar = _noise_loop(2600.0, 0.0, 7)
	return _roar

static func _get_drum() -> AudioStreamWAV:
	if _drum_wav == null:
		_drum_wav = _noise_loop(420.0, 23.0, 11)
	return _drum_wav

func _new_spray_node() -> Node3D:
	var n := Node3D.new()
	n.visible = false
	var card := MeshInstance3D.new()
	card.name = "Card"
	card.mesh = QuadMesh.new()
	card.material_override = _get_card_mat()
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the shader moves the quad far from where its box says it is
	card.custom_aabb = AABB(Vector3(-4.0, 0.0, -4.0), Vector3(8.0, COLUMN_H + 1.0, 8.0))
	card.set_instance_shader_parameter("power", 1.0)
	n.add_child(card)
	var mist := CPUParticles3D.new()
	mist.name = "Mist"
	mist.amount = 14
	mist.lifetime = 1.3
	mist.emitting = false
	mist.mesh = QuadMesh.new()
	(mist.mesh as QuadMesh).size = Vector2(0.9, 0.9)
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.albedo_color = Color(0.85, 0.74, 0.58, 0.10)
	mm.vertex_color_use_as_albedo = false
	mist.material_override = mm
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	mist.emission_sphere_radius = 0.5
	mist.direction = Vector3.UP
	mist.spread = 60.0
	mist.initial_velocity_min = 0.6
	mist.initial_velocity_max = 2.2
	mist.gravity = Vector3(0.0, -2.5, 0.0)
	mist.scale_amount_min = 0.7
	mist.scale_amount_max = 1.8
	n.add_child(mist)
	var roar := AudioStreamPlayer3D.new()
	roar.name = "Roar"
	roar.stream = _get_roar()
	roar.bus = &"Tires"
	roar.unit_size = 7.0
	roar.max_distance = 90.0
	roar.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	n.add_child(roar)
	add_child(n)
	return n

# ---------- clock ----------

## Game minutes since the run began (the night's 600 minutes, night after night).
func now() -> float:
	var clock = game.get("night_clock") if game != null else null
	if clock != null:
		return float(int(clock.night) - 1) * 600.0 + float(clock.minutes)
	return _own_minutes

# ---------- entries ----------

func entry_for(key: String) -> Dictionary:
	for e in wet:
		if e.key == key:
			return e
	return {}

func spraying() -> int:
	var n := 0
	for e in wet:
		if e.spraying:
			n += 1
	return n

## The player has just knocked this hydrant off. `pos` is its foot in the
## chunk's own space, `road` its straight-road spot (x across signed, z along
## the chunk 0 .. -50), `kit` whether it is a roadside-kit hydrant (those
## stand at road height, the kerb ones on the pavement).
func burst(key: String, chunk: int, pos: Vector3, road: Vector2, kit: bool, roots: Dictionary) -> void:
	_roots = roots
	if not entry_for(key).is_empty():
		return
	# at most MAX_SPRAYS at once: the oldest falls back to its wet patch
	while spraying() >= MAX_SPRAYS:
		var oldest := {}
		for e in wet:
			if e.spraying and (oldest.is_empty() or float(e.start) < float(oldest.start)):
				oldest = e
		_stop(oldest)
	var h := hash(key)
	var s := float(chunk) * Props.CHUNK_LEN - road.y
	var e := {
		"key": key, "chunk": chunk, "pos": pos, "kit": kit,
		"side": 1 if road.x >= 0.0 else -1, "xa": absf(road.x), "s": s,
		"hisser": posmod(h, HISSER_IN) == 0,
		"start": now(), "life": SPRAY_MIN + float(posmod(hash([key, "life"]), SPRAY_EXTRA)),
		"spraying": true, "stopped_at": 0.0, "age": 0.0, "power": 0.0, "wetness": 1.0,
		"down": _downhill(chunk, road),
	}
	wet.append(e)
	_attach(e)
	_draw_patches(chunk)

## +1 when the road falls (or is level) in the direction of travel at the
## hydrant, -1 when it falls back the way you came: the way the water runs.
func _downhill(chunk: int, road: Vector2) -> int:
	var z := -(float(chunk - RoadFrame.origin_index) * Props.CHUNK_LEN - road.y)
	var ahead := RoadFrame.roll(Vector3(0.0, 0.0, z - 15.0)).y
	var behind := RoadFrame.roll(Vector3(0.0, 0.0, z + 15.0)).y
	return -1 if ahead > behind + 0.05 else 1

func _stop(e: Dictionary) -> void:
	if e.is_empty() or not e.spraying:
		return
	e.spraying = false
	e.power = 0.0
	e.stopped_at = now()
	_detach(e)

func new_night() -> void:
	for e in wet:
		_detach(e)
	var chunks := {}
	for e in wet:
		chunks[e.chunk] = true
	wet.clear()
	for c in chunks:
		_draw_patches(c)
	_clear_player()

# ---------- what is drawn ----------

func _attach(e: Dictionary) -> void:
	var root: Node3D = _roots.get(e.chunk)
	if root == null or not is_instance_valid(root) or not e.spraying:
		return
	var idx := wet.find(e)
	var j := -1
	for k in MAX_SPRAYS:
		if _node_of[k] == idx:
			j = k
			break
	if j < 0:
		for k in MAX_SPRAYS:
			if _node_of[k] < 0:
				j = k
				break
	if j < 0:
		return
	_node_of[j] = idx
	var n := _nodes[j]
	if n.get_parent() != root:
		n.get_parent().remove_child(n)
		root.add_child(n)
	# its own +x points at the lanes (the hisser sprays that way)
	n.transform = Transform3D(Basis(Vector3.UP, 0.0 if e.side < 0 else PI), e.pos)
	n.reset_physics_interpolation()
	n.visible = true
	var card := n.get_node(^"Card") as MeshInstance3D
	card.set_instance_shader_parameter("hisser", 1.0 if e.hisser else 0.0)
	card.set_instance_shader_parameter("power", float(e.power))
	var mist := n.get_node(^"Mist") as CPUParticles3D
	mist.position = Vector3(1.2, 0.5, 0.0) if e.hisser else Vector3(0.0, COLUMN_H * 0.75, 0.0)
	mist.emitting = true
	var roar := n.get_node(^"Roar") as AudioStreamPlayer3D
	roar.pitch_scale = 1.25 if e.hisser else 1.0
	if not roar.playing:
		roar.play()

func _detach(e: Dictionary) -> void:
	var idx := wet.find(e)
	for k in MAX_SPRAYS:
		if _node_of[k] == idx:
			_release(k)

func _release(k: int) -> void:
	_node_of[k] = -1
	var n := _nodes[k]
	n.visible = false
	(n.get_node(^"Mist") as CPUParticles3D).emitting = false
	(n.get_node(^"Roar") as AudioStreamPlayer3D).stop()
	if n.get_parent() != self:
		n.get_parent().remove_child(n)
		add_child(n)

## PropBreak calls this when a chunk has been laid afresh: a spray node left
## on it by whatever stood there before comes off, and this chunk's own burst
## hydrants get their water and patches back.
func dress_chunk(root: Node3D, chunk: int, roots: Dictionary) -> void:
	_roots = roots
	for k in MAX_SPRAYS:
		if _nodes[k].get_parent() == root:
			var idx := _node_of[k]
			if idx < 0 or idx >= wet.size() or int(wet[idx].chunk) != chunk:
				_release(k)
	for e in wet:
		if int(e.chunk) == chunk and e.spraying:
			_attach(e)
	_draw_patches(chunk)

func _patch_len(e: Dictionary) -> float:
	return GROW_M * clampf(float(e.age) / GROW_SECS, 0.05, 1.0)

func _draw_patches(chunk: int) -> void:
	var root: Node3D = _roots.get(chunk)
	if root == null or not is_instance_valid(root):
		return
	var mmi := root.get_node_or_null(^"HydrantWet") as MultiMeshInstance3D
	var mine := []
	for e in wet:
		if int(e.chunk) == chunk:
			mine.append(e)
	if mmi == null:
		if mine.is_empty():
			return
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var plane := PlaneMesh.new()
		plane.size = Vector2(1.0, 1.0)
		mm.mesh = plane
		mm.instance_count = 8
		mm.visible_instance_count = 0
		mmi = MultiMeshInstance3D.new()
		mmi.name = "HydrantWet"
		mmi.multimesh = mm
		mmi.material_override = _get_patch_mat()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 160.0
		root.add_child(mmi)
	var n := mini(mine.size(), mmi.multimesh.instance_count)
	for k in n:
		var e: Dictionary = mine[k]
		var length := _patch_len(e) + PATCH_BACK
		var p: Vector3 = e.pos
		# on the road beside the kerb, from PATCH_BACK uphill to the far end
		var x := p.x - float(e.side) * (HYDRANT_TO_KERB + PATCH_ROAD_W * 0.5)
		var z := p.z - float(e.down) * (length * 0.5 - PATCH_BACK)
		var y := p.y - (0.0 if e.kit else RoadChunkBuilder.KERB_H) + RoadWetScript.PUDDLE_Y + 0.004
		mmi.multimesh.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(PATCH_ROAD_W, 1.0, length)), Vector3(x, y, z)))
		mmi.multimesh.set_instance_color(k, Color(1.0, 1.0, 1.0, float(e.wetness)))
	mmi.multimesh.visible_instance_count = n
	mmi.visible = n > 0

# ---------- the tick ----------

## One physics tick. `player` may be null (no car yet).
func step(delta: float, player: RigidBody3D, half: Vector3, roots: Dictionary) -> void:
	if wet.is_empty():
		if sheet > 0.0:
			_step_sheet(delta, player)
		return
	_roots = roots
	_tick += 1
	_own_minutes += delta / REAL_SECONDS_PER_MIN
	var t := now()
	var redraw := {}
	for i in range(wet.size() - 1, -1, -1):
		var e: Dictionary = wet[i]
		e.age = float(e.age) + delta
		if e.spraying:
			var left := float(e.start) + float(e.life) - t
			if left <= 0.0:
				_stop(e)
				redraw[e.chunk] = true
			else:
				# up in RISE_SECS, full, then sinking over the last TRICKLE_MIN
				var pw := minf(clampf(left / TRICKLE_MIN, 0.0, 1.0), clampf(float(e.age) / RISE_SECS, 0.0, 1.0))
				if absf(pw - float(e.power)) > 0.004:
					e.power = pw
					_set_power(i, pw)
		else:
			var w := clampf(1.0 - (t - float(e.stopped_at)) / DRY_MIN, 0.0, 1.0)
			if w <= 0.0:
				# dry: the entry goes, the node table's indices move down
				redraw[e.chunk] = true
				wet.remove_at(i)
				for k in MAX_SPRAYS:
					if _node_of[k] > i:
						_node_of[k] -= 1
				continue
			if absf(w - float(e.wetness)) > 0.02:
				e.wetness = w
				redraw[e.chunk] = true
		if float(e.age) < GROW_SECS + 0.5 and _tick % 12 == 0:
			redraw[e.chunk] = true
	for c in redraw:
		_draw_patches(c)
	if player != null:
		_step_player(delta, player, half)
	_step_sheet(delta, player)

func _set_power(entry_index: int, pw: float) -> void:
	for k in MAX_SPRAYS:
		if _node_of[k] == entry_index:
			var n := _nodes[k]
			(n.get_node(^"Card") as MeshInstance3D).set_instance_shader_parameter("power", pw)
			(n.get_node(^"Roar") as AudioStreamPlayer3D).volume_db = lerpf(-28.0, 0.0, pw)
			(n.get_node(^"Mist") as CPUParticles3D).emitting = pw > 0.35

## Whether the straight-road spot (x across, s along) is on entry e's water.
func on_patch(e: Dictionary, x: float, s: float) -> bool:
	if signf(x) != float(e.side):
		return false
	var xa := absf(x)
	if xa < float(e.xa) - PATCH_IN or xa > float(e.xa) + PATCH_OUT:
		return false
	var d := (s - float(e.s)) * float(e.down)
	return d >= -PATCH_BACK and d <= _patch_len(e)

func _clear_player() -> void:
	if _patch_set and game != null:
		var p = game.get("player")
		if p != null and p.get("wet") != null:
			p.wet.patch.fill(0.0)
			p.wet.patch_on = false
	_patch_set = false

func _step_player(delta: float, player: RigidBody3D, half: Vector3) -> void:
	var u := RoadFrame.unroll(player.global_position)
	var s := RoadFrame.s_at(u.z)
	var near: Array = []
	for e in wet:
		if absf(s - float(e.s)) < GROW_M + 8.0 and absf(absf(u.x) - float(e.xa)) < PATCH_IN + 3.0:
			near.append(e)
	var wheels: Array = player.get("wheel_array") if player.get("wheel_array") != null else []
	var wetg = player.get("wet")
	var touching := false
	var over_column := false
	if near.is_empty():
		_clear_player()
	else:
		# the wheels' straight-road spots from the car's own (one unroll, not
		# five): each wheel's offset turned into the road's frame
		var to_road := RoadFrame.basis_at(u.z).transposed()
		var centre := player.global_position
		var n := mini(4, wheels.size())
		for i in n:
			var w: Node3D = wheels[i]
			var off := to_road * (w.global_position - centre)
			var wx := u.x + off.x
			var ws := s - off.z
			var fill := 0.0
			for e in near:
				if on_patch(e, wx, ws):
					fill = maxf(fill, float(e.wetness))
			if wetg != null:
				wetg.patch[i] = fill
			if fill > 0.0:
				touching = true
		if wetg != null:
			wetg.patch_on = true
			_patch_set = true
		# the jets themselves: the car's box over a gusher's base
		var car_inv := player.global_transform.affine_inverse()
		for e in near:
			if not e.spraying or e.hisser or float(e.power) < 0.3 or float(e.age) < RISE_SECS:
				continue
			var root: Node3D = _roots.get(e.chunk)
			if root == null or not is_instance_valid(root):
				continue
			var base: Vector3 = root.global_transform * (e.pos as Vector3)
			var local := car_inv * base
			if absf(local.x) < half.x + 0.35 and absf(local.z) < half.z + 0.35:
				over_column = true
				if lift_enabled:
					_lift(player, wheels, base, float(e.power))
	_step_column(delta, player, over_column)
	_step_tracks(delta, player, wheels, touching)

func _lift(player: RigidBody3D, wheels: Array, base: Vector3, power: float) -> void:
	if player.linear_velocity.y > 0.25:
		return   # already rising: no pumping it up
	for i in mini(4, wheels.size()):
		var w: Node3D = wheels[i]
		var d := w.global_position - base
		d.y = 0.0
		if d.length() < COLUMN_R:
			# mostly through the centre, a little toward the wheel: a bob, never a flip
			var arm := (w.global_position - player.global_position) * 0.25
			var pulse := 0.7 + 0.3 * sin(float(_tick) * 0.45)
			player.apply_force(Vector3.UP * player.mass * LIFT_ACCEL * power * pulse, arm)
			lift_ticks += 1
			return

func _step_column(delta: float, player: RigidBody3D, over: bool) -> void:
	if over:
		if not in_column:
			in_column = true
			var v := player.linear_velocity
			var speed := v.length()
			if speed > 1.0:
				var loss := minf(DRAG_KMH / 3.6, speed * 0.3)
				player.linear_velocity = v - v / speed * loss
				drag_passes += 1
			sheet = 1.0
			var wipers := player.get_node_or_null(^"CarWipers")
			if wipers != null:
				wipers.set("burst", WIPER_SECS)
			if not _drum.playing:
				_drum.play()
		if _out_t > 5.0:
			_column_t = 0.0
		_out_t = 0.0
		_column_t += delta
		sheet = 1.0
		if _column_t >= DIRT_AFTER:
			_column_t = -1e9   # one step per soaking
			var fx = game.get("fx") if game != null else null
			var dirt = fx.get("dirt") if fx != null else null
			if dirt != null:
				dirt.set_level(float(dirt.level) - DIRT_STEP)
			dirt_steps += 1
	else:
		if in_column:
			in_column = false
		_out_t += delta
		if _out_t > 0.35 and _drum.playing:
			_drum.stop()

func _step_sheet(delta: float, _player: RigidBody3D) -> void:
	if sheet <= 0.0:
		if _sheet_rect.visible:
			_sheet_rect.visible = false
		return
	if not in_column:
		sheet = maxf(sheet - delta / SHEET_SECS, 0.0)
	var cam = game.get("camera") if game != null else null
	var cockpit := cam != null and int(cam.get("view")) == 1   # ChaseCamera.View.COCKPIT
	_sheet_rect.visible = cockpit and sheet > 0.0
	if _sheet_rect.visible:
		(_sheet_rect.material as ShaderMaterial).set_shader_parameter("amount", sheet)

## Wet tyres: after a wheel has been in the water the rear tyres leave dark
## tracks, fading out over TRACK_M metres.
func _step_tracks(delta: float, player: RigidBody3D, wheels: Array, touching: bool) -> void:
	if touching:
		_track_left = TRACK_M
		_track_has = false
		return
	if _track_left <= 0.0 or wheels.size() < 4:
		return
	var moved := player.linear_velocity.length() * delta
	_track_left -= moved
	_track_gap += moved
	var fx = game.get("fx") if game != null else null
	var skids = fx.get("skids") if fx != null else null
	if skids == null:
		return
	if not _track_has:
		for k in 2:
			_track_last[k] = wheels[2 + k].last_collision_point
		_track_has = true
		_track_gap = 0.0
		return
	if _track_gap < TRACK_STEP:
		return
	_track_gap = 0.0
	for k in 2:
		var w = wheels[2 + k]
		if not w.is_colliding():
			_track_has = false
			return
		var p: Vector3 = w.last_collision_point
		skids.lay_track(_track_last[k], p, 0.6 * clampf(_track_left / TRACK_M, 0.0, 1.0))
		_track_last[k] = p
		tracks_laid += 1

## The floating origin moved the world: the track points are in world space.
func shift_world(offset: Vector3) -> void:
	for k in 2:
		_track_last[k] += offset
