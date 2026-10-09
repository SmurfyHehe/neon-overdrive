extends "res://tests/car/car_scrape.gd"

# Cars must not scrape themselves at any Tuner setting (Roy 2026-10-09): the
# player's manoeuvres from tests/car/car_scrape.gd on coupes tuned to the corners
# of the Tuner's safe range and to Roy's own saved tune (car_scrape.gd SWEEP).
# Its own file so each half fits the test runner's time limit.
#
# Run: <godot> --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/car/car_scrape_tunes.gd

func _initialize() -> void:
	sweep = true
	super()
