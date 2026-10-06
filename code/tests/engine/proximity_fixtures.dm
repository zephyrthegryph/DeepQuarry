// Fixtures of the client-proximity tracker (code/controllers/subsystems/proximity.dm). Compiled under UNIT_TESTS only; code/modules/unit_tests/dq_proximity_tests.dm drives them.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A tracked thing whose every() runs only while a client is near.
/obj/prox_probe
	name = "proximity probe"
	proximity_tracked = TRUE
	var/ticks = 0

CAPABILITIES(/obj/prox_probe)
	every(1 SECOND, then(PROC_REF(probe_tick)), when = STAT_RELEVANCE)

/obj/prox_probe/proc/probe_tick(datum/act/A)
	ticks++

/// A map effect that counts its triggers.
/obj/effect/map_effect/interval/prox_counter
	interval_lower_bound = 1 SECOND
	interval_upper_bound = 1 SECOND
	var/fired = 0

/obj/effect/map_effect/interval/prox_counter/trigger()
	fired++

/// The same, held relevant everywhere.
/obj/effect/map_effect/interval/prox_counter/always
	always_run = TRUE

#endif
