extends MultiMeshInstance3D
class_name ScrapeSparks

# Sparks (driving-feel pass, 2026-10-08; Roy's pick: "sparks yes"). Metal on
# a wall or another car throws a stream of short amber streaks from where the
# body touches; a hit throws a burst. Same contact test as the scrape sound
# (CrashAudio), so you never see sparks without hearing the scrape.
#
# Cheap on the Iris Xe: one MultiMesh draw of at most MAX sparks, simulated
# here in world space (gravity, drag), each drawn as a camera-facing streak
# along its own motion (the shader below). FxSettings "sparks" is the off
# switch. Floating origin: FxPack.shift_world moves the live sparks.
# live_count / spawned are for tests (headless drops MultiMesh data, so tests
# read the simulation, not the mesh).

const MAX := 96
const MIN_SLIDE := 3.0        # m/s of sliding along the contact before it sparks
const RATE_LO := 40.0         # sparks per second at MIN_SLIDE
const RATE_HI := 260.0        # sparks per second at FULL_SLIDE and over
const FULL_SLIDE := 30.0
const BURST_DV := 3.0         # m/s: hits at least a thud also throw a burst
const LIFE := Vector2(0.18, 0.45)
const DRAG := 3.0             # 1/s
const GRAVITY := 9.8
const HOT := Color("#FFE2A8")  # white-hot amber at birth (Amber vs. Dusk palette)
const AMBER := Color("#FFC066")
const SODIUM := Color("#FF8A1F")

var enabled := true
var live_count := 0
var spawned := 0

var _player: PlayerCar
var _crash: CrashAudio
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _life := PackedFloat32Array()
var _age := PackedFloat32Array()
var _carry := 0.0
var _rng := RandomNumberGenerator.new()

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;
uniform float width = 0.022;   // m
uniform float streak = 0.035;  // s of travel one streak spans
varying vec4 tint;
void vertex() {
	vec3 c = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 v = (VIEW_MATRIX * vec4(INSTANCE_CUSTOM.xyz, 0.0)).xyz;
	float l = length(v.xy);
	vec2 dir = l > 0.0001 ? v.xy / l : vec2(0.0, 1.0);
	vec2 perp = vec2(-dir.y, dir.x);
	float len = max(l * streak, width * 2.0);
	// the quad runs from the spark back along where it came from
	VERTEX = c + vec3(perp * VERTEX.x * width + dir * (VERTEX.y - 0.5) * len, 0.0);
	tint = COLOR;
}
void fragment() {
	ALBEDO = tint.rgb * tint.a * 2.5;
}
"""

func _init(player: PlayerCar) -> void:
	_player = player
	name = "ScrapeSparks"

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in _player.get_children():
		if c is CrashAudio:
			_crash = c
	if _crash == null:
		push_warning("ScrapeSparks: no CrashAudio on the car, so no sparks")
		set_physics_process(false)
		return
	_crash.hit_building.connect(_on_hit_building)
	_rng.seed = 2208
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = SHADER
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	multimesh = mm
	# Sparks are placed in world space; skip culling the whole set.
	custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	for i in MAX:
		_pos.append(Vector3.ZERO)
		_vel.append(Vector3.ZERO)
		_life.append(0.0)
		_age.append(0.0)

func _physics_process(delta: float) -> void:
	_simulate(delta)
	if not enabled or not FxSettings.is_on("sparks") or not _crash.scraping_contact():
		_carry = 0.0
		return
	var contact := _contact()
	if contact.is_empty():
		return
	var slide: float = contact.slide
	if slide < MIN_SLIDE:
		_carry = 0.0
		return
	var rate := lerpf(RATE_LO, RATE_HI, clampf((slide - MIN_SLIDE) / (FULL_SLIDE - MIN_SLIDE), 0.0, 1.0))
	_carry += rate * delta
	while _carry >= 1.0:
		_carry -= 1.0
		_spawn(contact.pos, contact.normal, contact.along, slide)

func _on_hit_building(dv: float, first: bool) -> void:
	if not first or not enabled or not FxSettings.is_on("sparks"):
		return
	# The window's first tick is a fraction of the hit; size the burst on a
	# hit that is already at least a thud in one tick.
	if dv < BURST_DV:
		return
	var contact := _contact()
	if contact.is_empty():
		return
	for k in int(clampf(8.0 + dv * 2.0, 8.0, 40.0)):
		_spawn(contact.pos, contact.normal, contact.along, maxf(contact.slide, dv))

## The deepest-sliding body contact this tick: world position, normal (out of
## the other surface), sliding direction and speed. Empty when none.
func _contact() -> Dictionary:
	var state := PhysicsServer3D.body_get_direct_state(_player.get_rid())
	if state == null:
		return {}
	var best := {}
	var origin := _player.global_position
	for i in state.get_contact_count():
		# Godot 4: the "local" position is in global space, relative to nothing.
		var p := state.get_contact_local_position(i)
		var n := state.get_contact_local_normal(i)
		var v := state.get_velocity_at_local_position(p - origin) - state.get_contact_collider_velocity_at_position(i)
		var t := v - n * v.dot(n)
		var s := t.length()
		if best.is_empty() or s > float(best.slide):
			best = {"pos": p, "normal": n, "along": t / s if s > 0.001 else Vector3.ZERO, "slide": s}
	return best

func _spawn(at: Vector3, normal: Vector3, along: Vector3, slide: float) -> void:
	var i := -1
	var oldest := -1.0
	for k in MAX:
		if _life[k] <= 0.0:
			i = k
			break
		if _age[k] / _life[k] > oldest:
			oldest = _age[k] / _life[k]
			i = k
	var spread := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.2, 1), _rng.randf_range(-1, 1))
	_pos[i] = at
	_vel[i] = along * slide * _rng.randf_range(0.25, 0.7) + normal * _rng.randf_range(0.5, 2.5) + spread * 1.8 + Vector3.UP * 1.0
	_life[i] = _rng.randf_range(LIFE.x, LIFE.y)
	_age[i] = 0.0
	spawned += 1

func _simulate(delta: float) -> void:
	var drag := exp(-DRAG * delta)
	var n := 0
	for i in MAX:
		if _life[i] <= 0.0:
			continue
		_age[i] += delta
		if _age[i] >= _life[i]:
			_life[i] = 0.0
			continue
		_vel[i] = _vel[i] * drag + Vector3.DOWN * GRAVITY * delta
		_pos[i] += _vel[i] * delta
		var k := _age[i] / _life[i]
		var col := HOT.lerp(AMBER, minf(k * 2.0, 1.0)).lerp(SODIUM, maxf(k * 2.0 - 1.0, 0.0))
		col.a = 1.0 - k * k
		multimesh.set_instance_transform(n, Transform3D(Basis.IDENTITY, _pos[i]))
		multimesh.set_instance_color(n, col)
		multimesh.set_instance_custom_data(n, Color(_vel[i].x, _vel[i].y, _vel[i].z, 0.0))
		n += 1
	live_count = n
	multimesh.visible_instance_count = n
	visible = n > 0

## Floating-origin recentre (FxPack.shift_world).
func shift_world(offset: Vector3) -> void:
	for i in MAX:
		if _life[i] > 0.0:
			_pos[i] += offset
