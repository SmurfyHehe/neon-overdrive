class_name WarningLights
extends CanvasLayer

# The warning-light strip for PowertrainHealth (Phase B). A minimal stand-in until
# the stage B step 4 instrument cluster exists: it only shows lights that are on
# (ENG, BRK, TYRE, CLT, DMG), amber for a warning and blinking red once the car is derating
# (engine) or fading (brakes). Reads the car's health; owns no state.

const AMBER := Color(1.0, 0.54, 0.12)
const RED := Color(0.95, 0.15, 0.15)

var player: PlayerCar
var row: HBoxContainer

## The row hangs this far in from the right edge. 330 clears the 480-wide rear
## strip (Hud.STRIP_SIZE) at the smallest window, 1280x720, where the strip's
## frame ends 882 px in; at the old 400 the row started on top of it.
const ROW_INSET := 330.0
const ROW_TOP := 12.0
var eng_label: Label
var brk_label: Label
var tyre_label: Label
var clt_label: Label
var dmg_label: Label

func _init(car: PlayerCar) -> void:
	player = car

func _ready() -> void:
	layer = 9
	row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	row.position = Vector2(-ROW_INSET, ROW_TOP)
	add_child(row)
	eng_label = _light(row, "ENG")
	brk_label = _light(row, "BRK")
	tyre_label = _light(row, "TYRE")
	clt_label = _light(row, "CLT")
	dmg_label = _light(row, "DMG")

func _light(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.visible = false
	UiTheme.apply(l, "dial", 20)
	parent.add_child(l)
	return l

func _process(_delta: float) -> void:
	var h := player.health
	# the engine lamp is also the limp-home lamp (brief LM): red while the engine limps
	var eng_limp := player.limp.is_engine_limp()
	_apply_light(eng_label, h.is_warning(PowertrainHealth.Warn.ENG) or eng_limp, h.is_warning(PowertrainHealth.Warn.ENG_DERATE) or eng_limp)
	_apply_light(brk_label, h.is_warning(PowertrainHealth.Warn.BRK), h.is_warning(PowertrainHealth.Warn.BRK_FADE))
	var flat := player.damage.any_tyre_flat()
	_apply_light(tyre_label, h.is_warning(PowertrainHealth.Warn.TYRE) or player.damage.any_tyre_low(), flat)
	_apply_light(clt_label, h.is_warning(PowertrainHealth.Warn.CLUTCH), false)
	# Damage (Stage C): a part past the free band, a lamp out or a flat tyre;
	# red once the damage itself limps the engine (nothing does since the heat
	# window, DP4a: a wrecked radiator shows as the ENG lamp when it runs hot).
	var d := player.damage
	_apply_light(dmg_label, d.warning(), d.engine_limp())

func _apply_light(l: Label, on: bool, severe: bool) -> void:
	l.visible = on and (not severe or int(Time.get_ticks_msec() / 350) % 2 == 0)
	Hud.set_font_color(l, RED if severe else AMBER)  # only on a change
