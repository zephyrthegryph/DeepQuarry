// registry(REGISTRY_X, key =, by =), registry_get(), registry_all() and radio_listen(freq =, filter =) (code/engine/lifeforms/registry.dm).

#define REGISTRY_DQ_LIFEFORM_PROBES "dq_lifeform_probes"
REGISTRY_DECLARE(dq_lifeform_probes, REGISTRY_DQ_LIFEFORM_PROBES)

/obj/item/dq_registry_probe
	name = "registry probe"
	var/probe_tag = "alpha"
	var/frequency = 1441

TRACKED(/obj/item/dq_registry_probe, probe_tag)
TRACKED(/obj/item/dq_registry_probe, frequency)

CAPABILITIES(/obj/item/dq_registry_probe)
	registry(REGISTRY_DQ_LIFEFORM_PROBES, key = nameof(probe_tag), by = REG_Z)
	radio_listen(freq = nameof(frequency))

/datum/unit_test/dq_lifeform_registry

/datum/unit_test/dq_lifeform_registry/proc/listening(obj/device, freq)
	var/datum/radio_frequency/F = SSradio.frequencies["[freq]"]
	if(!F)
		return FALSE
	for(var/filter in F.devices)
		if(device in F.devices[filter])
			return TRUE
	return FALSE

/datum/unit_test/dq_lifeform_registry/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_registry_probe/A = allocate(/obj/item/dq_registry_probe, T)
	var/obj/item/dq_registry_probe/B = allocate(/obj/item/dq_registry_probe, T)
	B.set_probe_tag("beta")

	TEST_ASSERT_EQUAL(registry_get(REGISTRY_DQ_LIFEFORM_PROBES, "alpha"), A, "an instance is filed under its key from init")
	TEST_ASSERT_EQUAL(registry_get(REGISTRY_DQ_LIFEFORM_PROBES, "beta"), B, "a written key re-files the instance")
	TEST_ASSERT(!(B in registry_all(REGISTRY_DQ_LIFEFORM_PROBES, "alpha")), "the old key no longer lists it")
	TEST_ASSERT_EQUAL(registry_get(REGISTRY_DQ_LIFEFORM_PROBES, "alpha", z = T.z), A, "by = REG_Z files it under its z-level")
	TEST_ASSERT_NULL(registry_get(REGISTRY_DQ_LIFEFORM_PROBES, "alpha", z = T.z + 100), "another z-level does not list it")
	TEST_ASSERT(A in REGISTRY_MEMBERS(REGISTRY_DQ_LIFEFORM_PROBES), "the registry's plain member list holds it too")
	TEST_ASSERT_EQUAL(length(registry_all(REGISTRY_DQ_LIFEFORM_PROBES)), 2, "registry_all() with no key lists every member")

	TEST_ASSERT(listening(A, 1441), "radio_listen() tunes to the var's frequency at init")
	A.set_frequency(1443)
	TEST_ASSERT(listening(A, 1443), "a written frequency retunes")
	TEST_ASSERT(!listening(A, 1441), "and leaves the old frequency")

	qdel(B)
	TEST_ASSERT_NULL(registry_get(REGISTRY_DQ_LIFEFORM_PROBES, "beta"), "destruction removes it from the registry")
	TEST_ASSERT(!(B in REGISTRY_MEMBERS(REGISTRY_DQ_LIFEFORM_PROBES)), "and from the plain member list")
	qdel(A)
	TEST_ASSERT(!listening(A, 1443), "destruction stops the radio listener")
