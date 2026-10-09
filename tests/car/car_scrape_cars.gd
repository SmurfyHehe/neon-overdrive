extends "res://tests/car/car_scrape.gd"

# Cars must not scrape themselves at any Tuner setting, on any car the player
# can drive (Roy 2026-10-09). The Tuner gives every car the same ride height,
# spring and damper range, so this runs the other PlayerCars.KINDS (the P1 is
# car_scrape_tunes.gd) stock and with the suspension at the Tuner's corners
# (lowest + softest, lowest + stiffest), each built from a saved tune and set
# live from the Tuner mid-run, on the car's own engine, brakes and grip.
#
# Not run here: low_soft (the same suspension plus 900 Nm, maximum grip and
# brakes; add it to sweep_tunes, it is print-only). Measured 2026-10-09: at
# 900 Nm the P0 beater and P4 kei pull 30-40 deg wheelies and drag their tails
# on the road, and the P6 crossover on maximum grip rolls over in the 120 km/h
# lane changes. That is what those numbers do to those cars, not the body
# scraping; whether the Tuner should cap power or grip per car is a design call.
#
# Split in two files (this one: the first half of the other cars,
# car_scrape_cars_b.gd: the rest) so each fits the test runner's time limit.
#
# Run: <godot> --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/car/car_scrape_cars.gd

## 0: the first half of the cars other than the P1, 1: the second half.
var half := 0

func _initialize() -> void:
	sweep = true
	var others: Array = []
	for k in PlayerCars.ids():
		if k != "p1_coupe":
			others.append(k)
	var mid := int(others.size() / 2.0)
	sweep_kinds = others.slice(0, mid) if half == 0 else others.slice(mid)
	sweep_tunes = ["stock", "springs_low_soft", "springs_low_stiff"]
	live_tunes = ["springs_low_soft", "springs_low_stiff"]
	print_only = ["low_soft"]
	super()
