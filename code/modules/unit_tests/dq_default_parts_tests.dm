// default_parts() (code/library/machine/parts.dm): a machine refreshes its default parts as it initializes.

/obj/machinery/dq_default_parts_probe
	name = "default parts probe"
	circuit = /obj/item/circuitboard/protean_reconstitutor
	/// RefreshParts() calls, and whether the type's own init code saw them done.
	var/refreshes = 0
	var/refreshed_before_own_init = FALSE

CAPABILITIES(/obj/machinery/dq_default_parts_probe)
	default_parts()

/obj/machinery/dq_default_parts_probe/Initialize(mapload)
	. = ..()
	refreshed_before_own_init = refreshes > 0

/obj/machinery/dq_default_parts_probe/RefreshParts()
	refreshes++

/// Without the entry nothing refreshes at init.
/obj/machinery/dq_default_parts_probe_plain
	name = "plain parts probe"
	circuit = /obj/item/circuitboard/protean_reconstitutor
	var/refreshes = 0

/obj/machinery/dq_default_parts_probe_plain/RefreshParts()
	refreshes++

/datum/unit_test/dq_default_parts

/datum/unit_test/dq_default_parts/Run()
	var/turf/T = dq_containment_floor()
	var/obj/machinery/dq_default_parts_probe/P = allocate(/obj/machinery/dq_default_parts_probe, T)
	TEST_ASSERT_EQUAL(P.refreshes, 1, "default_parts() refreshes the parts once as the machine initializes")
	TEST_ASSERT(P.refreshed_before_own_init, "before the type's own code after ..() (on_holder_init)")
	var/obj/machinery/dq_default_parts_probe_plain/Q = allocate(/obj/machinery/dq_default_parts_probe_plain, T)
	TEST_ASSERT_EQUAL(Q.refreshes, 0, "a machine without the entry does not")
