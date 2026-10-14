class_name Sound3D
extends Node3D

# A positional sound without AudioStreamPlayer3D (issue #567).
#
# AudioStreamPlayer3D recomputes its panning on every audio mix while it plays
# and hands it to AudioServer.set_playback_bus_volumes_linear(), which swaps
# the playback's bus details and frees the old copy a frame later while the mix
# thread may still read it: Godot 4.7.2 crashes now and then. This node does
# the same sums here and puts them on a spatial PlayerGain bus (an amplifier,
# an AudioEffectPanner and a high-shelf filter, plain numbers the mix thread
# reads), so its plain AudioStreamPlayer never has its level or bus written
# while it plays.
#
# The sums are AudioStreamPlayer3D's own (scene/3d/audio_stream_player_3d.cpp,
# 4.7.2) for a stereo output, one listener and no Area3D:
#   dist      listener (the viewport's current camera) to this node
#   gain dB   min(volume_db + 20 log10(1 / (dist / unit_size + 1e-5)), max_db),
#             as linear, times (1 - dist / max_distance) when max_distance > 0;
#             silent beyond max_distance
#   panning   left sqrt((1 - f cos x) / 2), right sqrt((1 + f cos x) / 2), x the
#             listener-space bearing in the horizontal plane, f from the
#             panning strength (project 3d_panning_strength x panning_strength)
#   filter    high shelf at attenuation_filter_cutoff_hz, gain
#             db_to_linear((1 - min(1, multiplier)) * attenuation_filter_db)
# A mono stream through the panner comes out left (1 - pan), right (1 + pan),
# so gain g and pan (r - l) / (l + r) with g = m (l + r) / 2 give exactly
# left m l, right m r. The streams played here are all mono. Doppler is off on
# every one of them in the game, as it is by default, so there is none here.
# Updated every physics tick while playing, as the 3D player updates once per
# mix. The panner's pan steps at a mix block edge where the 3D player ramped
# it; level still ramps (the amplifier).

signal finished

const CMP_EPSILON := 0.00001
const SILENT_DB := -200.0

@export var stream: AudioStream:
	set(v):
		stream = v
		if _player != null:
			_player.stream = v
@export var volume_db := 0.0
@export var pitch_scale := 1.0:
	set(v):
		pitch_scale = v
		if _player != null:
			_player.pitch_scale = v
@export var unit_size := 10.0
@export var max_db := 3.0
@export var max_distance := 0.0
@export var panning_strength := 1.0
@export var attenuation_filter_cutoff_hz := 5000.0
@export var attenuation_filter_db := -24.0
## The bus the sound ends up on (AudioStreamPlayer3D.bus).
@export var bus: StringName = &"Master":
	set(v):
		bus = v
		if _player != null:
			PlayerGain.retarget(_player, v)   # under the audio lock (#580)

var playing: bool:
	get:
		return _player != null and _player.playing

## Last values sent to the bus (tests and the listen numbers).
var out_left := 0.0
var out_right := 0.0

var _player: AudioStreamPlayer
var _global_strength := float(ProjectSettings.get_setting("audio/general/3d_panning_strength", 0.5))

func _init() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "Out"
	PlayerGain.route(_player, bus, SILENT_DB, true)
	_player.finished.connect(func() -> void:
		set_physics_process(false)
		finished.emit())
	add_child(_player, false, Node.INTERNAL_MODE_FRONT)
	set_physics_process(false)

func play(from := 0.0) -> void:
	_player.stream = stream
	_player.pitch_scale = pitch_scale
	update_mix()   # the level is in place before the first block, as the 3D player's is
	_player.play(from)
	set_physics_process(true)

func stop() -> void:
	_player.stop()
	set_physics_process(false)

func get_playback_position() -> float:
	return _player.get_playback_position()

func _physics_process(_delta: float) -> void:
	if not _player.playing:
		set_physics_process(false)
		return
	update_mix()

## Recomputes level, balance and filter from where the listener is now.
func update_mix() -> void:
	var cam: Camera3D = null
	if is_inside_tree():
		var vp := get_viewport()
		if vp != null and vp.is_audio_listener_3d():
			cam = vp.get_camera_3d()
	if cam == null:
		_send(0.0, 0.0, 1.0)
		return
	var lr := mix_for(cam.global_transform, global_position)
	_send(lr.x, lr.y, lr.z)

## Left and right gain (linear) and the high-shelf gain for a listener at
## `listener` hearing this node's settings from `pos`.
func mix_for(listener: Transform3D, pos: Vector3) -> Vector3:
	var local := listener.orthonormalized().affine_inverse() * pos
	var dist := local.length()
	if max_distance > 0.0 and dist > max_distance:
		return Vector3(0.0, 0.0, 1.0)
	var att := linear_to_db(1.0 / ((dist / unit_size) + CMP_EPSILON)) + volume_db
	att = minf(att, max_db)
	var m := db_to_linear(att)
	if max_distance > 0.0:
		m *= maxf(0.0, 1.0 - dist / max_distance)
	var shelf := db_to_linear((1.0 - minf(1.0, m)) * attenuation_filter_db)
	var p := stereo_pan(local, _global_strength * panning_strength)
	return Vector3(m * p.x, m * p.y, shelf)

## AudioStreamPlayer3D._calc_output_vol_stereo.
static func stereo_pan(dir: Vector3, strength: float) -> Vector2:
	var flatrad := sqrt(dir.x * dir.x + dir.z * dir.z)
	var g := clampf((1.0 - strength) * (1.0 - strength), 0.0, 1.0)
	var f := (1.0 - g) / (1.0 + g)
	var cosx := clampf(dir.x / (1.0 if flatrad == 0.0 else flatrad), -1.0, 1.0)
	var fcosx := cosx * f
	return Vector2(sqrt((-fcosx + 1.0) / 2.0), sqrt((fcosx + 1.0) / 2.0))

func _send(left: float, right: float, shelf: float) -> void:
	out_left = left
	out_right = right
	var sum := left + right
	if sum <= 0.0:
		PlayerGain.set_db(_player, SILENT_DB)
		PlayerGain.pan(_player, 0.0, shelf, attenuation_filter_cutoff_hz)
		return
	PlayerGain.set_db(_player, linear_to_db(sum * 0.5))
	PlayerGain.pan(_player, (right - left) / sum, shelf, attenuation_filter_cutoff_hz)
