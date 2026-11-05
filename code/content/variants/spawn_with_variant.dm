// Spawn helpers for the variant pattern.
//
// Every assoc-style spawn list (storage.starts_with, supply_pack.contains,
// vending products, etc.) uses values shaped as list(count, variant).
// Bare numbers/nulls are NOT supported — explicit list shape only.

/proc/spawn_with_variant(typepath, loc, variant)
	if(!typepath)
		return null
	var/atom/A = variant_new(typepath, loc) // a path, or a VARIANT() reference
	if(variant && istype(A, /obj/item))
		var/obj/item/I = A
		I.set_variant(variant)
		I.apply_variant()
	return A
