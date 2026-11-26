// What a generated route does besides moving reagents (chem_route_compile(), code/domains/world_model/reagents/blocks/routes.dm): the one product whose making is
// itself an event.

/// The effects of the route `R`, or null: nitroglycerin goes off when it is made (the nitration was meant to be cold).
/proc/chem_route_effects(datum/chem_route/R)
	if(length(R.products) && R.products[1] == REAGENT_ID_NITROGLYCERIN)
		return sets_off(kind = XFORM_FX_EXPLOSION, divisor = 2, skip_in_tests = TRUE)
	return null
