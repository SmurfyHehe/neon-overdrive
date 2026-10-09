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
var sparks: ScrapeSparks      # driving-feel pass (2026-10-08)
var hit_stop: HitStop

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
	# Sparks and the big-crash freeze ride on CrashAudio's hit measure.
	sparks = ScrapeSparks.new(_player)
	add_child(sparks)
	for c in _player.get_children():
		if c is CrashAudio:
			hit_stop = HitStop.new(c)
			add_child(hit_stop)
	apply_settings()

## Push the FxSettings flags to the nodes.
func apply_settings() -> void:
	screen.vignette_on = FxSettings.is_on("vignette")
	screen.speed_lines_on = FxSettings.is_on("speed_lines")
	skids.enabled = FxSettings.is_on("skid_marks")
	flames.enabled = FxSettings.is_on("exhaust_flames")
	sparks.enabled = FxSettings.is_on("sparks")
	if hit_stop != null:
		hit_stop.enabled = FxSettings.is_on("hit_stop")

## Flip one effect (FxSettings.EFFECTS) live, and remember it.
func set_effect(effect: String, on: bool) -> void:
	FxSettings.set_on(effect, on)
	apply_settings()

## Floating-origin recentre: the world moved by offset (game.gd _shift_origin).
func shift_world(offset: Vector3) -> void:
	skids.shift_world(offset)
	flames.shift_world(offset)  # fireballs and smoke left behind in world space
	sparks.shift_world(offset)
