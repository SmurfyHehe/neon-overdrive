class_name TunerColours
extends RefCounted

# Colour roles for the Tuner's graphics (Tuner UI overhaul PR 2; proposal
# "Tuner & Mechanic UI overhaul", decided by Roy 2026-10-08):
#   stock  : light steel blue, drawn as an outline or a dashed line
#   yours  : solid sodium
#   better : green, always with an up arrow and a + or - sign
#   worse  : red, always with a down arrow and a sign
# No colour-blind setting: the arrow and the sign carry the meaning without the
# colour. Contrast on the panel navy (#0E1424) and the plate (#1A2130): steel
# blue 7.0 / 6.1, green 9.1 / 8.0, text red 5.6 / 4.9, sodium 7.8 / 6.8 (all
# over the 4.5:1 text minimum). Police blue stays police-only.

const STOCK := Color("#7FA3CC")
const YOURS := Color("#FF8A1F")
const BETTER := Color("#3FD060")
const WORSE := Color("#FF4D4D")
const VALUE := Color("#FFC066")
const LABEL := Color("#C9CED6")
const DIM := Color("#7C8598")
const PLOT := Color("#1B2A4A")
const PANEL := Color("#0E1424")

const UP := "▲"
const DOWN := "▼"

## A change against stock as {text, colour}: "▲ +12" in green when it helps,
## "▼ -0.3" in red when it hurts, "stock" in steel blue when it is below `step`.
## `higher_is_better` says which way helps; `fmt` formats the signed number.
static func delta(diff: float, higher_is_better: bool, fmt := "%+.1f", step := 0.0) -> Dictionary:
	if absf(diff) < step or (fmt % diff).substr(1).to_float() == 0.0:
		return {"text": "stock", "colour": STOCK, "better": false, "level": true}
	var better := (diff > 0.0) == higher_is_better
	return {"text": "%s %s" % [UP if better else DOWN, fmt % diff],
		"colour": BETTER if better else WORSE, "better": better, "level": false}
