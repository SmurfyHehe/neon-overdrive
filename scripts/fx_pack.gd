extends Node
class_name FxPack

# Effects pack v1 (2026-10-06): the one node game.gd adds. Builds the cheap
# effects -- vignette + speed lines (ScreenFx), skid marks (SkidMarks), exhaust
# flames (ExhaustFlames) -- and applies the FxSettings flags, so a pause-menu
# toggle later only has to call set_effect(). Measured on the i5-1235U /
# Iris Xe / Mobile renderer: see the PR for the per-effect frame cost.

var screen: ScreenFx
var skids: SkidMarks
var flames: ExhaustFlames

var _player: PlayerCar
var _camera: ChaseCamera

func _init(player: PlayerCar, camera: ChaseCamera) -> void:
	_player = player
	_camera = camera
	name = "FxPack"

func _ready() -> void:
	FxSettings.load_settings()
	screen = ScreenFx.new(_player, _camera)
	add_child(screen)
	skids = SkidMarks.new(_player)
	add_child(skids)
	# On the car, so it rides along (and is interpolated) with the body.
	flames = ExhaustFlames.new(_player)
	_player.add_child(flames)
	apply_settings()

## Push the FxSettings flags to the nodes.
func apply_settings() -> void:
	screen.vignette_on = FxSettings.is_on("vignette")
	screen.speed_lines_on = FxSettings.is_on("speed_lines")
	skids.enabled = FxSettings.is_on("skid_marks")
	flames.enabled = FxSettings.is_on("exhaust_flames")

## Flip one effect (FxSettings.EFFECTS) live, and remember it.
func set_effect(effect: String, on: bool) -> void:
	FxSettings.set_on(effect, on)
	apply_settings()

## Floating-origin recentre: the world moved by offset (game.gd _shift_origin).
func shift_world(offset: Vector3) -> void:
	skids.shift_world(offset)
