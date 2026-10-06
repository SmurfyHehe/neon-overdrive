extends RefCounted
class_name RadioPlaylist

# A station's shuffled playlist on a running clock (file radio, 2026-10-06).
# Tracks play back to back in a shuffled order; when every track has played the
# list is reshuffled, and the first track of a new batch is never the one that just
# played. The order is a pure function of (track lengths, seed), so the radio can
# "keep playing" while you are on another station: locate(t) says which track is on
# at station-clock time t and how far into it, and tuning back in lands there.

var _lengths: PackedFloat32Array
var _rng := RandomNumberGenerator.new()
var _order: Array[int] = []        # track index of every entry played or queued so far
var _starts := PackedFloat64Array() # clock time at which each entry starts
var _total := 0.0

func _init(track_lengths: PackedFloat32Array, seed_value: int) -> void:
	_lengths = track_lengths
	_rng.seed = seed_value

func track_count() -> int:
	return _lengths.size()

## Appends one shuffled round of every track.
func _extend() -> void:
	var batch: Array[int] = []
	for i in _lengths.size():
		batch.append(i)
	for i in range(batch.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := batch[i]
		batch[i] = batch[j]
		batch[j] = tmp
	if batch.size() > 1 and not _order.is_empty() and batch[0] == _order[-1]:
		var tmp := batch[0]
		batch[0] = batch[1]
		batch[1] = tmp
	for i in batch:
		_order.append(i)
		_starts.append(_total)
		_total += _lengths[i]

## Where the station is at clock time `t` seconds: {"entry": position in the play
## order (counts up forever), "track": index into the station's tracks, "offset":
## seconds into that track}.
func locate(t: float) -> Dictionary:
	if _lengths.is_empty() or _total_length() <= 0.0:
		return {"entry": -1, "track": -1, "offset": 0.0}
	t = maxf(t, 0.0)
	while t >= _total:
		_extend()
	if _order.is_empty():
		_extend()
	var entry := _starts.bsearch(t, false) - 1
	return {"entry": entry, "track": _order[entry], "offset": t - _starts[entry]}

func _total_length() -> float:
	var sum := 0.0
	for l in _lengths:
		sum += l
	return sum
