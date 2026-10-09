extends "res://tests/car/car_scrape_cars.gd"

# The second half of tests/car/car_scrape_cars.gd's cars (see there).
#
# Run: <godot> --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/car/car_scrape_cars_b.gd

func _initialize() -> void:
	half = 1
	super()
