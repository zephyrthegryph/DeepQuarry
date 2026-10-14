/proc/dq_resolve_spawn_value(value)
	// Returns list("count" = N, "variant" = V)
	if(isnull(value))
		return list("count" = 1, "variant" = null)
	if(isnum(value))
		return list("count" = value, "variant" = null)
	if(islist(value))
		var/list/L = value
		var/c = isnum(L[1]) ? L[1] : 1
		var/v = (L.len >= 2 && istext(L[2])) ? L[2] : null
		return list("count" = c, "variant" = v)
	return list("count" = 1, "variant" = null)
