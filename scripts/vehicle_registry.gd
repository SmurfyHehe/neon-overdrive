extends RefCounted
class_name VehicleRegistry

# The vehicle list: every car the game can build, one entry each. Adding a
# car means dropping its model files under assets/vehicles/ and adding one
# entry here -- VehicleModel does the rest (finds the wheels, measures them,
# places the physics wheels). CREDITS.md must name every credit below;
# tests/vehicle_registry.gd checks that.
#
# Entry keys:
#   name     shown on the HUD
#   role     "player" for now; "traffic" and "police" come in later batches
#   credit, licence, source   who made it and where it came from
#   looks    look name -> model file, in upgrade order ("stock" first). The
#            upgrade tree (#62) will pick the look; for now the L key cycles.
#   scale    model units -> metres
#   forward  "+z" or "-z": which way the model's nose points. The game's
#            forward is -Z, so "+z" models are turned around.
#   wheel_nodes  FL/FR/RL/RR -> node name of that wheel in the model. Left
#            and right are the car's own, seen from the driver's seat.
#   physics  optional. Without it the physics wheels go exactly where the
#            model's wheels are, at the model's wheel radius. With it, these
#            numbers win and the wheel visuals are moved and resized to match
#            -- for models whose wheels aren't real-car proportions.
#   builder  "test": the code-built test car from #63 instead of a model file.

## The test car's hardpoints (#63). The Kenney stand-in reuses them so it
## drives exactly like the test car: only the looks change.
const TEST_CAR_PHYSICS := {
	"front_z": -1.05, "rear_z": 1.05, "wheel_x": 0.88, "wheel_r": 0.34,
	"collision": Vector3(1.6, 0.6, 3.4),
}

const VEHICLES := {
	# Stand-in until the Sketchfab cars (Tiara GT '83 and co.) can be
	# downloaded. Kenney's cars are toy-proportioned -- wheels about half a
	# metre across at real size and a narrow track that would roll over at
	# our grip -- hence the physics override.
	"standin_sedan": {
		"name": "Stand-in sedan",
		"role": "player",
		"credit": "Kenney (www.kenney.nl), Car Kit",
		"licence": "CC0",
		"source": "https://kenney.nl/assets/car-kit",
		"looks": {
			"stock": "res://assets/vehicles/kenney-car-kit/sedan.glb",
			"tuned": "res://assets/vehicles/kenney-car-kit/sedan-sports.glb",
		},
		"scale": 1.35,
		"forward": "+z",
		"wheel_nodes": {
			"FL": "wheel-front-left", "FR": "wheel-front-right",
			"RL": "wheel-back-left", "RR": "wheel-back-right",
		},
		"physics": TEST_CAR_PHYSICS,
	},
	"test": {
		"name": "Test car",
		"role": "player",
		"credit": "",
		"builder": "test",
		"looks": {"stock": ""},
		"physics": TEST_CAR_PHYSICS,
	},
}

## Player cars in the order the V key steps through them. The first one is
## what the game starts in.
const PLAYER_CARS := ["standin_sedan", "test"]

static func entry(id: String) -> Dictionary:
	return VEHICLES[id]

static func look_names(id: String) -> Array:
	return VEHICLES[id].looks.keys()

static func next_player_car(id: String) -> String:
	return PLAYER_CARS[(PLAYER_CARS.find(id) + 1) % PLAYER_CARS.size()]

static func next_look(id: String, look: String) -> String:
	var names := look_names(id)
	return names[(names.find(look) + 1) % names.size()]
