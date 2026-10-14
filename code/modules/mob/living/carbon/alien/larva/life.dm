// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.


//Larvae regenerate health and nutrition from plasma and alien weeds.
/mob/living/carbon/alien/larva/life_environment_due()
	return TRUE

/mob/living/carbon/alien/larva/life_environment_exchange(datum/gas_mixture/environment)

	if(!environment) return

	var/turf/T = get_turf(src)
	if(LINDA_GAS_AMT(environment, GAS_PHORON) > 0 || (T && locate_on(T, /obj/effect/alien/weeds)))
		src.update_progression()
		src.mend(TREAT_TISSUE_REPAIR, 1)
		src.mend(TREAT_BURN_CARE, 1)
		src.mend(TREAT_ANTITOXIN, 1)
		src.mend(TREAT_OXYGENATION, 1)
