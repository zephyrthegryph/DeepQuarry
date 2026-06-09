// Spawn helpers for the consolidation pattern.
//
// Every assoc-style spawn list (storage.starts_with, supply_pack.contains,
// vending products, etc.) uses values shaped as list(count, variant).
// Bare numbers/nulls are NOT supported — explicit list shape only.

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

/proc/spawn_with_variant(typepath, loc, variant)
	if(!typepath)
		return null
	var/atom/A = new typepath(loc)
	if(variant && istype(A, /obj/item))
		var/obj/item/I = A
		I.variant = variant
		I.apply_variant()
	return A
