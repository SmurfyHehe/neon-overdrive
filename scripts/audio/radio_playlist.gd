extends RefCounted
class_name RadioPlaylist

# A station's shuffled playlist on a running clock (file radio, 2026-10-06).
# Tracks play back to back in a shuffled order; when every track has played the
# list is reshuffled, and the first track of a new batch is never the one that just
# played. The order is a pure function of (track lengths, seed), so the radio can
# "keep playing" while you are on another station: locate(t) says which track is on
# at station-clock time t and how far into it, and tuning back in lands there.
#
# Crossfade (2026-10-10): with `overlap` > 0 each track starts that many seconds
# before the one before it ends, so the radio is never silent between songs. In
# the overlap locate() reports the new track plus the old one (prev_track) and
# how far the blend has got. overlap 0 is the old back-to-back behaviour.

var _lengths: PackedFloat32Array
var _rng := RandomNumberGenerator.new()
var _order: Array[int] = []        # track index of every entry played or queued so far
var _starts := PackedFloat64Array() # clock time at which each entry starts
var _overlaps := PackedFloat32Array() # per entry: seconds it overlaps the entry before
var _overlap := 0.0
var _total := 0.0                   # clock time at which the last queued entry ends

func _init(track_lengths: PackedFloat32Array, seed_value: int, overlap := 0.0) -> void:
	_lengths = track_lengths
	_rng.seed = seed_value
	_overlap = maxf(overlap, 0.0)

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
		var ov := 0.0
		if _overlap > 0.0 and not _order.is_empty():
			# never more than 40% of either song, so a short track still plays
			ov = minf(_overlap, 0.4 * minf(_lengths[_order[-1]], _lengths[i]))
		var start := _total - ov
		_order.append(i)
		_overlaps.append(ov)
		_starts.append(start)
		_total = start + _lengths[i]

## The track index of play-order entry `entry` (queues rounds as needed), so the
## radio can load the next song before it is on.
func entry_track(entry: int) -> int:
	if _lengths.is_empty():
		return -1
	while _order.size() <= entry:
		_extend()
	return _order[entry]

## Where the station is at clock time `t` seconds: {"entry": position in the play
## order (counts up forever), "track": index into the station's tracks, "offset":
## seconds into that track, "blend": 1 normally, 0..1 through the overlap with
## the song before, "prev_track" / "prev_offset": that song and where it is
## (prev_track is -1 outside an overlap)}.
func locate(t: float) -> Dictionary:
	if _lengths.is_empty() or _total_length() <= 0.0:
		return {"entry": -1, "track": -1, "offset": 0.0, "blend": 1.0, "prev_track": -1, "prev_offset": 0.0}
	t = maxf(t, 0.0)
	while t >= _total:
		_extend()
	if _order.is_empty():
		_extend()
	var entry := _starts.bsearch(t, false) - 1
	var offset := t - _starts[entry]
	var ov := _overlaps[entry]
	var out := {"entry": entry, "track": _order[entry], "offset": offset, "blend": 1.0,
			"prev_track": -1, "prev_offset": 0.0}
	if ov > 0.0 and offset < ov and entry > 0:
		out.blend = offset / ov
		out.prev_track = _order[entry - 1]
		out.prev_offset = _lengths[_order[entry - 1]] - ov + offset
	return out

func _total_length() -> float:
	var sum := 0.0
	for l in _lengths:
		sum += l
	return sum
