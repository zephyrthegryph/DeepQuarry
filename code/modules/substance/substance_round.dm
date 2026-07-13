// Per-round determinism for the substance system.
//
// The design's central rule: a source substance's hidden profile is *learnable
// but rerolled every round* — the same archetype yields a fresh, internally-
// consistent profile each shift. We get that by seeding the five attributes from
// a stable per-round salt plus the archetype id, deterministically, so the same
// source reads identically all round but differs next round.

// The salt is fixed once per server round (globals reset between rounds) and is
// never exposed in-world — it only seeds the hidden profiles.
/proc/substance_round_salt()
	var/static/salt
	if(!salt)
		salt = "[rand(1, 1000000)]-[world.realtime]"
	return salt

// Deterministic 0..1 draw from a key and a named stream. md5 gives a stable hash;
// we take four hex digits off a stream-specific offset so each attribute axis
// draws independently for the same key. Same (key, stream) -> same value all round.
/proc/substance_hash_unit(key, stream)
	var/h = md5("[key]|[stream]|[substance_round_salt()]")
	if(!h)
		return 0
	var/hex = copytext(h, 1, 5) // first 4 hex digits -> 0..65535
	return hex2num(hex) / 65535

// Convenience: a deterministic integer in [lo, hi] for (key, stream).
/proc/substance_hash_range(key, stream, lo, hi)
	return round(lo + substance_hash_unit(key, stream) * (hi - lo))
