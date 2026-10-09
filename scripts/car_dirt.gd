class_name CarDirt
extends Node

# Road grime on the player car (2026-10-09, car feel proposal section 4: "dirt
# builds on the lower body through the night, cleared by a cleaning mini-game
# at the garage"). One number, 0 clean .. 1 a full night's dirt, pushed into the
# body material's "dirt" uniform (P1CoupeBuilder.BODY_SHADER), which draws it
# as blotchy grime on the sills. No texture, no extra draw call: a few shader
# ops per body pixel, nothing when the level is 0.
#
# It grows with distance driven (speed x time, so a floating-origin shift does
# not matter), faster off the tarmac, and is saved so it survives a restart and
# a quit; only the wash (wash_screen.gd) takes it back down. The FxSettings
# "dirt" flag (pause menu) turns both the build-up and the drawing off; the
# saved level is kept, so turning it back on shows the car as it was.

const FULL_NIGHT_METRES := 24000.0   # a 20-minute night at about 70 km/h covers 24 km: that is a fully dirty car
const OFF_ROAD_RATE := 4.0           # kerbs, verges and dirt shoulders coat it four times as fast
const SAVE_EVERY_SECS := 5.0
const DEFAULT_PATH := "user://car_dirt.cfg"
const TestMode := preload("res://scripts/test_mode.gd")
static var path := TestMode.path(DEFAULT_PATH)

## 0..1, the stored amount of grime.
var level := 0.0
## From FxSettings "dirt" (FxPack.apply_settings). Off: nothing drawn, nothing added.
var enabled := true:
	set(v):
		enabled = v
		apply()

var _player: Node
var _mat: ShaderMaterial
var _shown := -1.0
var _save_left := SAVE_EVERY_SECS
var _saved_level := 0.0

func _init(player: Node) -> void:
	_player = player
	name = "CarDirt"

func _ready() -> void:
	load_state()
	var visual: Variant = _player.get("chassis_visual") if _player != null else null
	if visual is Node and visual.has_meta("body_mat"):
		var m: Variant = visual.get_meta("body_mat")
		if m is ShaderMaterial:
			_mat = m
	apply()

func _physics_process(delta: float) -> void:
	if not enabled or _player == null:
		return
	var speed: float = absf(_player.current_speed()) if _player.has_method("current_speed") else 0.0
	var off_road: bool = _player.is_off_road() if _player.has_method("is_off_road") else false
	add_distance(speed * delta, off_road)
	_save_left -= delta
	if _save_left <= 0.0:
		_save_left = SAVE_EVERY_SECS
		save_state()

func _exit_tree() -> void:
	save_state()

## Metres driven since the last call; off-road metres count OFF_ROAD_RATE times.
func add_distance(metres: float, off_road: bool) -> void:
	if not is_finite(metres) or metres <= 0.0:
		return
	set_level(level + metres * (OFF_ROAD_RATE if off_road else 1.0) / FULL_NIGHT_METRES)

func set_level(v: float) -> void:
	level = clampf(v, 0.0, 1.0) if is_finite(v) else 0.0
	apply()

## What the body is drawn with: the level, or 0 when the effect is off.
func shown_level() -> float:
	return level if enabled else 0.0

## Push the level into the body material (skipped when it has not changed, so a
## parked car costs nothing).
func apply() -> void:
	var v := shown_level()
	if _mat != null and absf(v - _shown) > 0.002:
		_mat.set_shader_parameter("dirt", v)
		_shown = v

func load_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	var v: Variant = cfg.get_value("dirt", "level", 0.0)
	var f: float = float(v) if (v is float or v is int) else 0.0
	level = clampf(f, 0.0, 1.0) if is_finite(f) else 0.0
	_saved_level = level

func save_state() -> bool:
	if is_equal_approx(level, _saved_level):
		return true
	var cfg := ConfigFile.new()
	cfg.load(path)  # a missing file is fine
	cfg.set_value("dirt", "level", level)
	if cfg.save(path) != OK:
		return false
	_saved_level = level
	return true
