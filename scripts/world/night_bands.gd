extends RefCounted
class_name NightBands

# Hour bands (living world step 2, 2026-10-08): the four parts of a night from
# docs/planning/living-world-time-and-people-2026-10-08.md section 1, read off
# the night clock (NightClock.minutes, game minutes since 8 p.m.).
#
#   Dusk       8-10 p.m.   busiest, full traffic
#   Late      10 p.m.-1    thinning out
#   Dead       1-4 a.m.    thinnest (the 2 a.m. bar-close burst is an event, step 3)
#   Pre-dawn   4-6 a.m.    a little busier again: early workers, deliveries
#
# Traffic: traffic_share() is the share of the player's Traffic slider that is
# on the road at that time. It only ever goes DOWN from the slider (the 16-car
# budget, traffic decisions section 9), so the dead hours also save CPU. The
# curve is smooth so a band change never empties the road at once, and the
# TrafficManager only benches or brings back cars where you cannot see them.
#
# Radio: Dave's rotation adds a few lines that fit the band (band_lines()).
# Placeholders in his voice, the story is Roy's to write.

enum Band { DUSK, LATE, DEAD, PREDAWN }

const NAMES := ["Dusk", "Late", "Dead hours", "Pre-dawn"]
## Band start, game minutes since 8 p.m.
const STARTS := [0.0, 120.0, 300.0, 480.0]

## Share of the slider's cars on the road: [minutes since 8 p.m., share],
## straight lines between the points. Lowest (30%) around 3:30 a.m.
const TRAFFIC_CURVE := [
	[0.0, 1.0], [120.0, 1.0], [180.0, 0.8], [300.0, 0.55], [360.0, 0.45],
	[450.0, 0.3], [480.0, 0.35], [540.0, 0.5], [600.0, 0.55],
]

const BAND_LINES := [
	[  # Dusk
		"Dave: Shift's starting. Commuters still out there, driver. Let them get home first.",
		"Dave: Buses are running, shops are open, everybody's in a hurry. Except us.",
		"Dave: Traffic report: busy, all lanes. Same as every night at this hour."],
	[  # Late
		"Dave: The lines are open. Nobody's calling yet. They will.",
		"Dave: Taxis and the people who can't sleep. That's the road now.",
		"Dave: Windows going dark all over town. One by one. Don't take it personally."],
	[  # Dead hours
		"Dave: Coffee machine's making the noise again. I'm choosing to believe it's fine.",
		"Dave: If you can see another car right now, wave. You two might be the only ones awake.",
		"Dave: Dead hours. The city's asleep and I'm talking to the sodium lamps. And you."],
	[  # Pre-dawn
		"Dave: Bread trucks and garbage trucks. The morning people are coming.",
		"Dave: First kitchens lighting up. Somebody's making coffee they actually enjoy.",
		"Dave: Go home soon, driver. The sun doesn't care how fast you are."],
]

static func band_of(minutes: float) -> int:
	for i in range(STARTS.size() - 1, -1, -1):
		if minutes >= STARTS[i]:
			return i
	return Band.DUSK

static func band_name(band: int) -> String:
	return NAMES[clampi(band, 0, NAMES.size() - 1)]

## 0.3 .. 1.0, for game minutes since 8 p.m. (outside the night: the ends).
static func traffic_share(minutes: float) -> float:
	if not is_finite(minutes):
		return 1.0
	var c: Array = TRAFFIC_CURVE
	if minutes <= c[0][0]:
		return c[0][1]
	for i in range(1, c.size()):
		if minutes <= c[i][0]:
			var t: float = (minutes - c[i - 1][0]) / (c[i][0] - c[i - 1][0])
			return lerpf(c[i - 1][1], c[i][1], t)
	return c[c.size() - 1][1]

static func band_lines(band: int) -> Array:
	return BAND_LINES[clampi(band, 0, BAND_LINES.size() - 1)]
