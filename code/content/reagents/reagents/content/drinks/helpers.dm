/// A drink's pull on body temperature toward `target` (B12). A warm drink (adj > 0) only warms
/// a body below the target and a cold one (adj < 0) only cools a body above it, and neither
/// overshoots. The cold branch used to subtract a negative number, heating the drinker.
/proc/drink_temperature_step(current, target, adj)
	if(adj > 0 && current < target)
		return min(target, current + adj * TEMPERATURE_DAMAGE_COEFFICIENT)
	if(adj < 0 && current > target)
		return max(target, current + adj * TEMPERATURE_DAMAGE_COEFFICIENT)
	return current
