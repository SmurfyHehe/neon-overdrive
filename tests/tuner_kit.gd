extends SceneTree

# The Tuner's graphic kit (Tuner UI overhaul PR 2): every widget loads from its
# own scene (scenes/tuner_kit/, for the Stage E garage), takes data and draws;
# the colour roles put an arrow and a sign on every better / worse; the gearing
# chart's maths; the performance card's radar and its "vs stock" column; values
# against stock in the Tuner's rows.
# Headless by default. With the real renderer NEON_SHOT=<png> saves a sheet of
# every widget:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/tuner_kit.gd

var failures: Array[String] = []

func _initialize() -> void:
	_run()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var bg := ColorRect.new()
	bg.color = Color("#0E1424")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.position = Vector2(20, 20)
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 20)
	root.add_child(grid)

	# colour roles: green ▲ +, red ▼ -, level reads "stock"
	var up := TunerColours.delta(4.0, true, "%+.0f")
	var down := TunerColours.delta(-0.3, true, "%+.1f")
	var faster := TunerColours.delta(-0.2, false, "%+.2f")
	var level := TunerColours.delta(0.01, true, "%+.1f")
	_check(up.text == "▲ +4" and up.colour == TunerColours.BETTER, "better should be green with ▲ and +: %s" % up.text)
	_check(down.text == "▼ -0.3" and down.colour == TunerColours.WORSE, "worse should be red with ▼ and -: %s" % down.text)
	_check(faster.better and faster.text.begins_with("▲ -"), "lower 0-100 is better and keeps its minus sign: %s" % faster.text)
	_check(level.text == "stock" and level.colour == TunerColours.STOCK, "below the shown precision should read stock: %s" % level.text)
	_check(PaletteCheck.ok(TunerColours.STOCK) and PaletteCheck.ok(TunerColours.WORSE), "steel blue and text red should pass the palette rule")

	var dial: RotaryDial = load("res://scenes/tuner_kit/rotary_dial.tscn").instantiate()
	dial.title = "GRIP TO DRIFT"
	dial.lo_word = "Grip"
	dial.hi_word = "Drift"
	dial.custom_minimum_size = Vector2(200, 200)
	dial.set_values(0.7, 0.35, "Loose")
	grid.add_child(dial)
	var gauge: RotaryDial = load("res://scenes/tuner_kit/rotary_dial.tscn").instantiate()
	gauge.title = "BOOST"
	gauge.needle = true
	gauge.red_from = 0.85
	gauge.custom_minimum_size = Vector2(200, 200)
	gauge.set_values(0.55, 0.3, "0.8 bar")
	grid.add_child(gauge)

	var stock := CarSpec.coupe_default()
	var mine := CarSpec.clone_spec(stock)
	mine.final_drive = float(stock.final_drive) * 0.85  # longer gearing
	var gc: GearingChart = load("res://scenes/tuner_kit/gearing_chart.tscn").instantiate()
	gc.title = "GEARING"
	gc.custom_minimum_size = Vector2(280, 200)
	gc.set_gearing(mine, stock, PlayerCar.CFG.wheel_r, TunerModel.estimate(mine).top, TunerModel.estimate(stock).top)
	grid.add_child(gc)
	var lines := GearingChart.gear_lines(stock, PlayerCar.CFG.wheel_r)
	_check(lines.size() == stock.gear_ratios.size(), "one gearing line per gear")
	var rising := true
	for i in range(1, lines.size()):
		rising = rising and lines[i][1].x > lines[i - 1][1].x and is_equal_approx(lines[i][0].x, lines[i - 1][1].x)
	_check(rising, "each gear should start where the last one shifts and reach further")
	var longer := GearingChart.gear_lines(mine, PlayerCar.CFG.wheel_r)
	_check(longer[-1][1].x > lines[-1][1].x, "a lower final drive should reach a higher speed at the redline")
	_check(gc.series.size() == 2 * lines.size() and gc.series[0].dashed and gc.series[0].colour == TunerColours.STOCK, "stock gearing should be steel-blue dashes under yours")

	var plot: CurvePlot = load("res://scenes/tuner_kit/curve_plot.tscn").instantiate()
	plot.title = "CURVE"
	plot.custom_minimum_size = Vector2(280, 200)
	plot.x_max = 8000.0
	plot.y_max = 1.0
	plot.x_step = 2000.0
	plot.y_step = 0.5
	var a := PackedVector2Array()
	var b := PackedVector2Array()
	for i in 21:
		var x := 400.0 * i
		a.append(Vector2(x, sin(PI * i / 20.0) * 0.8))
		b.append(Vector2(x, sin(PI * i / 20.0) * 0.9))
	plot.add_series(a, TunerColours.STOCK, 1.5, true)
	plot.add_series(b, TunerColours.YOURS, 2.0)
	grid.add_child(plot)

	var radar: RadarChart = load("res://scenes/tuner_kit/radar_chart.tscn").instantiate()
	grid.add_child(radar)
	var seesaw: BalanceSeesaw = load("res://scenes/tuner_kit/balance_seesaw.tscn").instantiate()
	seesaw.set_values(0.5, -0.3)
	grid.add_child(seesaw)

	var card: PerformanceCard = load("res://scenes/tuner_kit/performance_card.tscn").instantiate()
	card.custom_minimum_size = Vector2(250, 0)
	grid.add_child(card)
	await process_frame
	var e_stock := TunerModel.estimate(stock)
	var grip := CarSpec.clone_spec(stock)
	var model := TunerModel.new(null, grip, stock)
	model.apply_preset("Grip")
	var e_grip := TunerModel.estimate(grip)
	card.stock = e_stock
	card.set_values(e_stock, e_stock)
	for k in ["top", "accel", "brake", "grip"]:
		_check(card.vs[k].text == "stock", "stock against stock should read stock: %s %s" % [k, card.vs[k].text])
	card.set_values(e_stock, e_grip)
	var g: String = card.vs.grip.text
	_check(g.begins_with("▲ +") and card.vs.grip.get_theme_color("font_color") == TunerColours.BETTER, "the Grip preset should show more grip in green: %s" % g)
	var rv := PerformanceCard.radar_values(e_grip)
	_check(rv.size() == 5 and rv[3] > PerformanceCard.radar_values(e_stock)[3], "the radar's grip spoke should grow with the Grip preset")
	radar.set_values(PerformanceCard.radar_values(e_stock), rv)

	# rows against stock
	var spring: Dictionary = TunerModel.page("suspension").settings[2]
	var m2 := TunerModel.new(null, CarSpec.clone_spec(stock), stock)
	_check(m2.relative_text(spring) == "Stock", "stock springs should read Stock: %s" % m2.relative_text(spring))
	m2.nudge(spring, 1)
	m2.nudge(spring, 1)
	_check(m2.relative_text(spring) == "+2 stiffer", "two notches stiffer should read +2 stiffer: %s" % m2.relative_text(spring))
	m2.nudge(spring, -4)
	_check(m2.relative_text(spring) == "2 softer", "two notches under stock should read 2 softer: %s" % m2.relative_text(spring))
	_check(m2.value_text(spring) == "2 softer", "a setting with no unit shows its change from stock, not n / 10: %s" % m2.value_text(spring))
	var compound: Dictionary = TunerModel.page("tyres").settings[0]
	_check(m2.stock_notch(compound) == 1 and m2.relative_text(compound) == "Stock", "stock compound is Sport")

	# page graphics: every one loads from its scene and takes a setup
	var stock_est := TunerModel.estimate(stock)
	for id in ["tyres", "suspension", "gearbox", "engine", "diff", "brakes", "aero", "assists", "sound"]:
		var pg := PageGraphic.for_page(id)
		_check(pg != null, "page %s has no graphic" % id)
		var scene_path := "res://scenes/tuner_kit/%s.tscn" % pg.get_script().resource_path.get_file().get_basename()
		_check(ResourceLoader.exists(scene_path), "page %s's graphic has no scene: %s" % [id, scene_path])
		pg.free()
	var dyno := DynoGraphic.curves(stock)
	var peak_rpm := 0.0
	var peak := 0.0
	for p in dyno.power:
		if p.y > peak:
			peak = p.y
			peak_rpm = p.x
	_check(peak > 100.0 and peak_rpm > 4000.0, "the coupe's power should peak high in the rev range: %.0f kW at %.0f rpm" % [peak, peak_rpm])
	var boosted := CarSpec.clone_spec(stock)
	boosted.turbo_boost_max = 1.0
	_check(DynoGraphic.curves(boosted).power[12].y > dyno.power[12].y, "boost should lift the power curve")
	_check(is_equal_approx(DiffGraphic.lock_of({"rear_locking_differential_engage_torque": 200.0}), 0.8), "200 Nm engage reads 80% lock, as the row does")
	var drift := CarSpec.clone_spec(stock)
	TunerModel.new(null, drift, stock).apply_preset("Drift")
	_check(AssistLights.traction_level(stock) == 1 and AssistLights.traction_level(drift) == 0, "stock TC is Low, the Drift preset turns it off")
	_check(TyreGraphic._patch(1.6).x > TyreGraphic._patch(2.8).x, "a lower pressure should draw a wider footprint")
	var words := PerformanceCard.preview_words(e_stock, e_grip, "Compound")
	_check(words.begins_with("Next notch on Compound: ") and words.contains("▲") and words.contains("grip"), "next-notch words: %s" % words)
	_check(PerformanceCard.preview_words(e_stock, e_stock).ends_with("no change the estimates can see"), "no change should say so")
	var shown := []
	for id in ["tyres", "suspension", "gearbox", "engine"]:
		var pg := PageGraphic.for_page(id)
		pg.custom_minimum_size = Vector2(300, 200)
		grid.add_child(pg)
		shown.append(pg)
	await process_frame
	for pg in shown:
		pg.show_setup(grip, stock, {"est": e_grip, "stock_est": stock_est, "wheel_r": PlayerCar.CFG.wheel_r, "compound": 2})

	var shot := OS.get_environment("NEON_SHOT")
	if shot != "":
		for i in 4:
			await process_frame
		root.get_texture().get_image().save_png(shot)
		print("screenshot: ", shot)
	_end("")

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		print("FAIL ", msg)

func _end(msg: String) -> void:
	if msg != "":
		failures.append(msg)
	print("tuner_kit: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)

## The palette test's rule, for a colour defined here.
class PaletteCheck:
	static func ok(c: Color) -> bool:
		return not (c.g > 0.6 and c.b > 0.6 and c.r < 0.35) and not (c.r > 0.6 and c.b > 0.6 and c.g < 0.35)
