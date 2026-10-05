extends RefCounted
class_name RadioSequencer

# A tiny synthwave band, generated in code: zero licences, nothing to download.
# Four bars looping: bass, an arpeggio, a pad, and a kick / snare / hat drum
# machine. Every sample is a function of the absolute sample index, so a station
# can "keep playing" while you are on another one: tuning in just starts the
# render at the station's current index (see RadioManager). Starting values for
# Roy's ear; each station is one row of data in STATIONS.

const MIX_RATE := 22050.0
const STEPS_PER_BAR := 16
const BARS := 4
const LOOP_STEPS := STEPS_PER_BAR * BARS

# name, bpm, root (midi note of the chord root's tonic), chords (semitone offset of each
# bar's root, and whether it is minor), arp pattern (indices into the chord's 4 notes),
# bass pattern (16 steps, 1 = play), pulse width, brightness.
const STATIONS := [
	{"name": "Neon FM", "bpm": 108.0, "root": 57, "chords": [[0, true], [-4, false], [-7, false], [-2, false]],
		"arp": [0, 1, 2, 3, 2, 1, 2, 3], "bass": [1, 0, 1, 1, 1, 0, 1, 0, 1, 0, 1, 1, 1, 0, 1, 0], "pulse": 0.35, "bright": 0.7},
	{"name": "Night Drive", "bpm": 94.0, "root": 50, "chords": [[0, true], [-2, false], [-4, false], [-5, true]],
		"arp": [0, 2, 1, 3, 0, 2, 3, 1], "bass": [1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 1, 0], "pulse": 0.5, "bright": 0.5},
	{"name": "Open Road", "bpm": 118.0, "root": 52, "chords": [[0, true], [-5, false], [-4, false], [-7, true]],
		"arp": [0, 1, 3, 2, 0, 1, 3, 2], "bass": [1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1], "pulse": 0.25, "bright": 0.9},
]

var _rng_state := 12345
# one-pole filters, restarted whenever a render starts (a few ms of settling)
var _bass_lp := 0.0
var _hat_lp := 0.0
var _snare_lp := 0.0

static func station_count() -> int:
	return STATIONS.size()

static func midi_hz(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)

## Seconds in one loop of the station.
static func loop_seconds(station: int) -> float:
	var bpm: float = STATIONS[station].bpm
	return LOOP_STEPS * 60.0 / bpm / 4.0

## Renders `frames` mono samples (as stereo frames) from absolute sample `start`.
func render(station: int, start: int, frames: int) -> PackedVector2Array:
	var st: Dictionary = STATIONS[station]
	var out := PackedVector2Array()
	out.resize(frames)
	var step_secs: float = 60.0 / float(st.bpm) / 4.0
	var bass_pat: Array = st.bass
	var arp_pat: Array = st.arp
	var pulse: float = st.pulse
	var bright: float = st.bright
	_rng_state = 12345 + start % 1000003
	_bass_lp = 0.0
	_hat_lp = 0.0
	_snare_lp = 0.0
	for i in frames:
		var t := float(start + i) / MIX_RATE
		var pos := t / step_secs
		var idx := int(pos)
		var frac := pos - idx
		var step := idx % LOOP_STEPS
		var bar := (step / STEPS_PER_BAR) % BARS
		var sb := step % STEPS_PER_BAR
		var chord: Array = st.chords[bar]
		var base: float = float(st.root) + float(chord[0])
		var minor: bool = chord[1]
		var third := 3.0 if minor else 4.0
		var tones := [base, base + third, base + 7.0, base + 12.0]

		# bass: saw one octave+ down, on its pattern, plucked, low-passed
		var bass := 0.0
		if bass_pat[sb] == 1:
			var bf := midi_hz(base - 24.0)
			var saw := 2.0 * fposmod(t * bf, 1.0) - 1.0
			_bass_lp += 0.12 * (saw - _bass_lp)
			bass = _bass_lp * exp(-3.0 * frac) * 0.9

		# arp: two slightly detuned pulses, plucked, on every step
		var an: float = tones[arp_pat[sb % arp_pat.size()]]
		var af := midi_hz(an + 12.0)
		var p1 := 1.0 if fposmod(t * af, 1.0) < pulse else -1.0
		var p2 := 1.0 if fposmod(t * af * 1.006, 1.0) < pulse else -1.0
		var arp := (p1 + p2) * 0.5 * exp(-6.0 * frac) * 0.30 * bright

		# pad: the triad as soft sines, breathing over the bar
		var breathe := 0.6 + 0.4 * sin(TAU * (t / (step_secs * STEPS_PER_BAR)) + 1.0)
		var pad := (sin(TAU * t * midi_hz(tones[0])) + sin(TAU * t * midi_hz(tones[1])) + sin(TAU * t * midi_hz(tones[2]))) * 0.07 * breathe

		# drums: four on the floor kick, snare on 2 and 4, hats on the off 8ths
		var kick := 0.0
		if sb % 4 == 0:
			var kt := frac * step_secs
			kick = sin(TAU * (45.0 * kt + 80.0 * (1.0 - exp(-30.0 * kt)) / 30.0)) * exp(-9.0 * kt) * 0.9
		var snare := 0.0
		if sb == 4 or sb == 12:
			var stt := frac * step_secs
			_snare_lp += 0.4 * (_noise() - _snare_lp)
			snare = ((_noise() - _snare_lp) * 0.5 + sin(TAU * 190.0 * stt) * 0.4) * exp(-14.0 * stt) * 0.6
		var hat := 0.0
		if sb % 2 == 1:
			var ht := frac * step_secs
			_hat_lp += 0.6 * (_noise() - _hat_lp)
			hat = (_noise() - _hat_lp) * exp(-45.0 * ht) * 0.25

		var s := tanh((bass + arp + pad + kick + snare + hat) * 0.9) * 0.55
		out[i] = Vector2(s, s)
	return out

func _noise() -> float:
	_rng_state = (_rng_state * 1103515245 + 12345) & 0x7fffffff
	return _rng_state / 1073741823.5 - 1.0
