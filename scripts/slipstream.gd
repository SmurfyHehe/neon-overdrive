extends MultiMeshInstance3D
class_name Slipstream

# Slipstream (driving-feel pass D1, 2026-10-08). Tucked in close behind a car
# at speed, the wind noise drops and faint air lines stream around the car
# ahead and close in behind it, toward you; pull out and it all fades. The
# pull itself (less drag) has been there since 2026-09-13: AeroModel's
# drafting cancels up to 25% of the drag force. This only shows and sounds it,
# from the same number (AeroModel._draft_factor), so the lines never lie.
#
# level: 0 clean air .. 1 the strongest draft, eased in at ATTACK and out at
# RELEASE (the fade when you pull out). Below MIN_SPEED there is no wake to
# feel, so nothing shows. CarAudio.slipstream gets the level for the wind.
# The lines are LINES streaks in one MultiMesh, laid out in the lead car's
# frame each frame (nothing to simulate or shift for the floating origin):
# each runs from ahead of its nose, bulges out around the body and pulls in
# behind it. FxSettings "slipstream" is the off switch for the look and the
# sound; the drag effect is physics and always on.

const MIN_SPEED := 15.0       # m/s
const FULL_SPEED := 30.0      # m/s: the lines are fully there from here
const ATTACK := 4.0           # 1/s
const RELEASE := 2.5          # 1/s
const LINES := 20
const ALPHA := 0.14           # line brightness at level 1 (faint: additive)
const SILVER := Color("#C9CED6")
const FLOW := 0.6             # line speed as a share of the player's speed

var enabled := true
var level := 0.0

var _player: PlayerCar
var _audio: CarAudio
var _leader: Node3D
var _lines: Array[Vector3] = []   # per line: x0 (side offset), y (height), phase 0..1
var _rng := RandomNumberGenerator.new()
var _clock := 0.0

func _init(player: PlayerCar) -> void:
	_player = player
	name = "Slipstream"

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in _player.get_children():
		if c is CarAudio:
			_audio = c
	_rng.seed = 1977
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = ScrapeSparks.SHADER
	mat.set_shader_parameter("width", 0.012)
	mat.set_shader_parameter("streak", 0.06)
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = LINES
	mm.visible_instance_count = 0
	multimesh = mm
	custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	for i in LINES:
		var side := -1.0 if i % 2 == 0 else 1.0
		_lines.append(Vector3(side * _rng.randf_range(0.2, 1.5), _rng.randf_range(0.25, 1.45), _rng.randf()))
	visible = false

func _physics_process(delta: float) -> void:
	var target := 0.0
	var on := enabled and FxSettings.is_on("slipstream")
	if on:
		var f := AeroModel._draft_factor(_player)
		var speed := _player.linear_velocity.length()
		target = f / AeroModel.MAX_DRAFT_REDUCTION * smoothstep(MIN_SPEED, FULL_SPEED, speed)
		var l: Variant = AeroModel.draft_leader.get(_player.get_instance_id())
		if f > 0.0 and l is Node3D and is_instance_valid(l):
			_leader = l
	var rate := ATTACK if target > level else RELEASE
	level = lerpf(level, target, 1.0 - exp(-rate * delta))
	if level < 0.005 and target == 0.0:
		level = 0.0
	if _audio != null:
		_audio.slipstream = level if on else 0.0

func _process(delta: float) -> void:
	_clock += delta
	if level <= 0.01 or _leader == null or not is_instance_valid(_leader) or not _leader.is_inside_tree():
		multimesh.visible_instance_count = 0
		visible = false
		return
	visible = true
	var xf := _leader.global_transform
	var half_l := float(_leader.get("half_l")) if _leader.get("half_l") != null else 2.2
	var half_w := float(_leader.get("half_w")) if _leader.get("half_w") != null else 0.95
	var gap := maxf((_player.global_position - _leader.global_position).length() - half_l, 2.0)
	var start := -half_l - 2.0             # ahead of the nose (car -z is forward)
	var finish := half_l + gap             # back at the player
	var span := finish - start
	var speed := maxf(_player.linear_velocity.length(), 1.0)
	var pace := speed * FLOW / span        # line runs per second
	for i in LINES:
		var ln := _lines[i]
		var s := fposmod(ln.z + _clock * pace, 1.0)
		var z := start + s * span
		var p := _path(ln.x, ln.y, z, half_l, half_w)
		var q := _path(ln.x, ln.y, z - 0.25, half_l, half_w)
		var wp := xf * p
		var vel := (wp - xf * q) / 0.25 * speed * FLOW
		var col := SILVER
		# fade in at the start, out as it reaches the player
		col.a = ALPHA * level * smoothstep(0.0, 0.15, s) * (1.0 - smoothstep(0.75, 1.0, s))
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, wp))
		multimesh.set_instance_color(i, col)
		multimesh.set_instance_custom_data(i, Color(vel.x, vel.y, vel.z, 0.0))
	multimesh.visible_instance_count = LINES

## A point on one line in the lead car's frame: pushed out to clear the body
## alongside it, then drawn in behind it (the wake closing).
static func _path(x0: float, y: float, z: float, half_l: float, half_w: float) -> Vector3:
	var side := signf(x0)
	var clear := half_w + 0.15
	var along := clampf(z / half_l, -1.6, 1.6)
	var bulge := exp(-along * along * 1.5)
	var x := side * maxf(absf(x0), lerpf(absf(x0), clear + absf(x0) * 0.35, bulge))
	var wake := smoothstep(half_l, half_l + 6.0, z)
	x *= 1.0 - 0.45 * wake
	return Vector3(x, y * (1.0 - 0.3 * wake), z)
