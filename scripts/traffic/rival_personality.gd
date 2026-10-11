class_name RivalPersonality
extends RefCounted

# How each crew's drivers race (rival driver build spec, step 1). One row per
# crew; RivalDriver reads it once when the race starts. Only the Docks crew is
# filled in and used so far, and of its row only `commit` and `brake_late`
# drive anything yet: the rest belongs to later steps (traffic overtakes,
# mistakes, defending) and is kept here so the numbers live in one place.
#
#   commit        share of the car's sideways grip it plans every bend on
#   brake_late    share of the car's full braking it plans its stops on
#   margin        m of air it wants beside another car (overtakes, later)
#   lc_gap_t      s of gap it accepts when it changes lane (overtakes, later)
#   shoulder      whether it will use the shoulder to pass (later)
#   block         whether it moves over to defend (later)
#   mistake_rate  chance of a mistake per bend under pressure (later)

const DOCKS := "docks"

const CREWS := {
	"docks": {"commit": 0.84, "brake_late": 0.85, "margin": 0.15, "lc_gap_t": 0.35,
		"shoulder": false, "block": false, "mistake_rate": 0.05},
}

## A copy of the crew's row (the Docks crew for a name it does not know).
static func row(crew: String) -> Dictionary:
	return (CREWS.get(crew, CREWS[DOCKS]) as Dictionary).duplicate()
