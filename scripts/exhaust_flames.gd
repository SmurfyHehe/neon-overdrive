extends Node3D
class_name ExhaustFlames

# Exhaust flames (effects pack v1, 2026-10-06): the flame events EngineSynth
# already produces (take_flames(): overrun pops and limiter bangs, sized by the
# exhaust tune's `flame` knob, docs/design/exhaust.md) finally draw something.
#
# One additive billboard quad per exhaust tip, hidden until a burst: a
# procedural 64x64 blob, amber-white core out to a sodium fringe (palette
# #FFC066 -> #FF8A1F, no neon), that flares up for LIFE seconds with a little
# random jitter in size. Pushed past 1.0 so the existing tight glow pass picks
# it up for free. No light, no particles: two draw calls while a flame shows,
# none while idle. Lives on the car's render layer so the blob shadow decal
# does not darken it.
#
# Tips come from the chassis visual's "exhaust_tips" meta (TestCarBuilder); a
# car without the meta gets one centre pipe.

const LIFE := 0.14        # s one burst lasts
const SIZE_MIN := 0.32    # m, the smallest flame's quad (P1's flame knob is 0.2: it must still read)
const SIZE_MAX := 0.75    # m, at flame size 1
const ENERGY := 3.2       # colour multiplier at full brightness (HDR, feeds glow)
const CORE := Color(1.0, 0.84, 0.52)   # amber #FFC066 lifted toward white
const FRINGE := Color(1.0, 0.54, 0.12) # sodium #FF8A1F

var enabled := true:
	set(v):
		enabled = v
		set_process(v)
		if not v:
			_left = 0.0
			_show(false)

## Bursts shown so far and the biggest (tests, tuning).
var bursts := 0
var max_size := 0.0

var _player: PlayerCar
var _audio: EngineAudio
var _quads: Array[MeshInstance3D] = []
var _mat: StandardMaterial3D
var _left := 0.0
var _peak := 0.0
var _rng := RandomNumberGenerator.new()
# Per instance, not static: a static texture would hold its RID past the
# renderer's teardown at quit.
var _tex: ImageTexture

func _init(player: PlayerCar) -> void:
	_player = player
	name = "ExhaustFlames"

func _ready() -> void:
	_rng.seed = 2206
	for c in _player.get_children():
		if c is EngineAudio:
			_audio = c
	var tips: Array = [Vector3(0.0, 0.3, 2.3)]
	if _player.chassis_visual != null and _player.chassis_visual.has_meta("exhaust_tips"):
		tips = _player.chassis_visual.get_meta("exhaust_tips")
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.no_depth_test = false
	_mat.disable_receive_shadows = true
	_mat.albedo_texture = _get_tex()
	_mat.albedo_color = Color(0, 0, 0, 0)
	for tip in tips:
		var mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, 1.0)
		mi.mesh = quad
		mi.material_override = _mat
		mi.position = tip + Vector3(0.0, 0.0, 0.16)  # just past the pipe end (+Z is the tail)
		mi.layers = 1 << (CarFx.CAR_LAYER - 1)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_quads.append(mi)
	enabled = enabled

## Show a burst of this size (0..1). The synth path calls this every frame it
## has one; a test or a future garage preview can call it directly.
func flash(size: float) -> void:
	size = clampf(size, 0.0, 1.0)
	if size <= 0.0:
		return
	_peak = maxf(_peak if _left > 0.0 else 0.0, size)
	_left = LIFE
	bursts += 1
	max_size = maxf(max_size, size)

func is_showing() -> bool:
	return _left > 0.0

func _process(delta: float) -> void:
	if _audio != null:
		var f: float = _audio.synth.take_flames()
		if f > 0.0:
			flash(f)
	if _left <= 0.0:
		return
	_left -= delta
	if _left <= 0.0:
		_show(false)
		return
	var k := _left / LIFE                       # 1 -> 0 over the burst
	var bright := (0.25 + 0.75 * _peak) * (0.35 + 0.65 * k)  # a floor, so small presets still flash
	var size := lerpf(SIZE_MIN, SIZE_MAX, _peak) * (0.55 + 0.45 * k)
	var e := ENERGY * bright
	_mat.albedo_color = Color(CORE.r * e, CORE.g * e, CORE.b * e, clampf(0.4 + 0.6 * k, 0.0, 1.0))
	for q in _quads:
		var s := size * _rng.randf_range(0.8, 1.2)
		q.scale = Vector3(s, s, s)
		q.visible = true

func _show(on: bool) -> void:
	for q in _quads:
		q.visible = on

## 64x64 blob: amber-white core, sodium fringe, soft alpha falloff.
func _get_tex() -> ImageTexture:
	if _tex == null:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var d := Vector2(x + 0.5 - n / 2.0, y + 0.5 - n / 2.0).length() / (n / 2.0)
				var a := clampf(1.0 - d, 0.0, 1.0)
				a = a * a
				var core := clampf(1.0 - d / 0.45, 0.0, 1.0)
				var c := FRINGE.lerp(CORE, core * core)
				img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
		_tex = ImageTexture.create_from_image(img)
	return _tex
