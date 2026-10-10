extends RefCounted

# Special vehicle (S0 shared plumbing, Roy 2026-10-10): monster truck, crab steer on Ctrl.
# The data file is the vehicle's own record, shaped like p1_coupe_data.gd's
# header (ID, LABEL). It carries no mesh yet: until its body step lands the
# car wears the P1 coupe body and the coupe's CarSpec (PlayerCars falls back
# to them for any kind PlayerCar.wheel_config / CarSpec.player_spec do not know).
#
# SPECIAL marks a story-end vehicle: PlayerCars.is_special() reads it. Sprint
# races leave specials out (PlayerCars.sprint_ids), and the garage and free
# roam list them only once GameState.is_special_unlocked(ID).

const ID := "m1_monster"
const LABEL := "Monster truck"
const SPECIAL := true
