// Spawn helpers for the variant pattern.
//
// Every assoc-style spawn list (storage.starts_with, supply_pack.contains,
// vending products, etc.) uses values shaped as list(count, variant).
// Bare numbers/nulls are NOT supported — explicit list shape only.

/proc/spawn_with_variant(typepath, loc, variant)
	if(!typepath)
		return null
	var/atom/A = new typepath(loc)
	if(variant && istype(A, /obj/item))
		var/obj/item/I = A
		I.variant = variant
		I.apply_variant()
	return A
