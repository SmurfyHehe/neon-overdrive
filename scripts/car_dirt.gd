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
# a quit; only the wash (wash_screen.gd) takes it back down. In the game it is
# saved with the car in the save slot (save core S1, 2026-10-11: the night's
# car_live.dirt, folded into the career's cars[car id].dirt; SaveDirector reads
# `level`), so each slot's car has its own dirt. The old shared
# user://car_dirt.cfg is upgraded into the slot and not read again; test mode
# and tests that set `path` still use a .cfg file. The FxSettings
# "dirt" flag (pause menu) turns both the build-up and the drawing off; the
# saved level is kept, so turning it back on shows the car as it was.
#
# The engine bay has its own level (engine bays 2e, Roy 1509): `bay_level`
# grows at half the body's rate (the hood keeps most of it out) and is drawn
# as the `grime` instance uniform on the Bay mesh (CarPaint's trim shader:
# dust on the flat tops, an oily film down the sides) while a lid is up. The
# wash takes it off on its second page, after the body. Saved as `bay_dirt`
# next to `dirt`.

const FULL_NIGHT_METRES := 24000.0   # a 20-minute night at about 70 km/h covers 24 km: that is a fully dirty car
const OFF_ROAD_RATE := 4.0           # kerbs, verges and dirt shoulders coat it four times as fast
const BAY_RATE := 0.5                # the bay dirties at half the body's rate
const SAVE_EVERY_SECS := 5.0
const DEFAULT_PATH := "user://car_dirt.cfg"
const TestMode := preload("res://scripts/core/test_mode.gd")
const SaveCore := preload("res://scripts/save/save_core.gd")
## DEFAULT_PATH means "in the save slot"; any other path is a .cfg file (tests).
static var path := TestMode.path(DEFAULT_PATH)

## 0..1, the stored amount of grime.
var level := 0.0
## 0..1, the engine bay's grime (engine bays 2e).
var bay_level := 0.0
## From FxSettings "dirt" (FxPack.apply_settings). Off: nothing drawn, nothing added.
var enabled := true:
	set(v):
		enabled = v
		apply()

var _player: Node
var _mat: ShaderMaterial
var _shown := -1.0
var _bay: MeshInstance3D
var _bay_shown := -1.0
var _save_left := SAVE_EVERY_SECS
var _saved_level := 0.0
var _saved_bay := 0.0

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
	var detail := CarDetail.of(_player as Vehicle) if _player is Vehicle else null
	if detail != null:
		detail.changed.connect(func(_on: bool) -> void:
			_bay_shown = -1.0   # the bay mesh is built when a lid first opens: push the grime again
			apply())
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
	var step := metres * (OFF_ROAD_RATE if off_road else 1.0) / FULL_NIGHT_METRES
	bay_level = clampf(bay_level + step * BAY_RATE, 0.0, 1.0)
	set_level(level + step)

func set_level(v: float) -> void:
	level = clampf(v, 0.0, 1.0) if is_finite(v) else 0.0
	apply()

func set_bay_level(v: float) -> void:
	bay_level = clampf(v, 0.0, 1.0) if is_finite(v) else 0.0
	apply()

## What the body is drawn with: the level, or 0 when the effect is off.
func shown_level() -> float:
	return level if enabled else 0.0

func shown_bay_level() -> float:
	return bay_level if enabled else 0.0

## Push the level into the body material (skipped when it has not changed, so a
## parked car costs nothing), and the bay's into the Bay mesh when the car has
## one built (CarDetail builds it the first time a lid is up).
func apply() -> void:
	var v := shown_level()
	if _mat != null and absf(v - _shown) > 0.002:
		_mat.set_shader_parameter("dirt", v)
		_shown = v
	var b := shown_bay_level()
	if absf(b - _bay_shown) > 0.002:
		if _bay == null or not is_instance_valid(_bay):
			var detail := CarDetail.of(_player as Vehicle) if _player is Vehicle else null
			_bay = detail.node_of("bay") as MeshInstance3D if detail != null else null
		if _bay != null:
			_bay.set_instance_shader_parameter("grime", b)
			_bay_shown = b

func load_state() -> void:
	var v: Variant
	var bv: Variant
	if path == DEFAULT_PATH:
		if not SaveCore.persist:
			return
		var st := SaveCore.car_state(PlayerCar.chassis_kind())
		v = st.get("dirt", 0.0)
		bv = st.get("bay_dirt", 0.0)
	else:
		var cfg := ConfigFile.new()
		if cfg.load(path) != OK:
			return
		v = cfg.get_value("dirt", "level", 0.0)
		bv = cfg.get_value("dirt", "bay", 0.0)
	level = _clean(v)
	bay_level = _clean(bv)
	_saved_level = level
	_saved_bay = bay_level

static func _clean(v: Variant) -> float:
	var f: float = float(v) if (v is float or v is int) else 0.0
	return clampf(f, 0.0, 1.0) if is_finite(f) else 0.0

func save_state() -> bool:
	if (is_equal_approx(level, _saved_level) and is_equal_approx(bay_level, _saved_bay)) or path == DEFAULT_PATH:
		return true   # in the slot the level goes with the night save (SaveDirector)
	var cfg := ConfigFile.new()
	cfg.load(path)  # a missing file is fine
	cfg.set_value("dirt", "level", level)
	cfg.set_value("dirt", "bay", bay_level)
	if cfg.save(path) != OK:
		return false
	_saved_level = level
	_saved_bay = bay_level
	return true
