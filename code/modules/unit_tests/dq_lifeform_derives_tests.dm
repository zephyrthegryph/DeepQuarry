// starts_as(STATE) and derives(target, PROC_REF(x), from =) (code/engine/lifeforms/derives.dm).

/obj/item/dq_starts_probe
	name = "starts probe"
	var/lit = FALSE
	var/lit_quietly = null
	var/lit_count = 0

CAPABILITIES(/obj/item/dq_starts_probe)
	op("light", hand(), label("Light it"), then(PROC_REF(light_up)))

/obj/item/dq_starts_probe/proc/light_up(datum/act/op/A)
	lit = TRUE
	lit_count++
	lit_quietly = GLOB.starts_as_running

/// A mapped variant that starts lit: the op's effects run at creation, with no actor and no messages.
/obj/item/dq_starts_probe/lit_start

CAPABILITIES(/obj/item/dq_starts_probe/lit_start)
	starts_as("light")

/obj/item/dq_derives_probe
	name = "derives probe"
	var/pressure = 100
	var/volume = 10
	var/summary = null
	var/computes = 0


CAPABILITIES(/obj/item/dq_derives_probe)
	derives(nameof(summary), PROC_REF(describe), from = list(nameof(pressure), nameof(volume)))

/obj/item/dq_derives_probe/proc/describe()
	computes++
	return "[pressure * volume]"

/datum/unit_test/dq_lifeform_derives

/datum/unit_test/dq_lifeform_derives/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_starts_probe/plain = allocate(/obj/item/dq_starts_probe, T)
	TEST_ASSERT(!plain.lit, "a type without starts_as() starts in its declared state")
	var/obj/item/dq_starts_probe/lit_start/lit = allocate(/obj/item/dq_starts_probe/lit_start, T)
	TEST_ASSERT(lit.lit, "starts_as() ran the op's effects at creation")
	TEST_ASSERT_EQUAL(lit.lit_count, 1, "once")
	TEST_ASSERT_EQUAL(lit.lit_quietly, TRUE, "while GLOB.starts_as_running was set (no actor, no messages)")
	TEST_ASSERT(!GLOB.starts_as_running, "and the flag is down after it")

	var/obj/item/dq_derives_probe/D = allocate(/obj/item/dq_derives_probe, T)
	TEST_ASSERT_EQUAL(D.summary, "1000", "derives() computes its target at init")
	D.set_pressure(50)
	TEST_ASSERT_EQUAL(D.summary, "500", "a written input recomputes it")
	D.set_volume(3)
	TEST_ASSERT_EQUAL(D.summary, "150", "every input in from = is followed")
	var/before = D.computes
	D.set_volume(3)
	TEST_ASSERT_EQUAL(D.computes, before, "an unchanged write recomputes nothing")

// Computation releases the lazy recursion guard before teardown.
// Deletion must accept that empty guard, and later holders still recompute.
/datum/unit_test/dq_lifeform_derives/recreate/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_derives_probe/first = allocate(/obj/item/dq_derives_probe, T)
	TEST_ASSERT_EQUAL(first.summary, "1000", "The first real holder computes its initial value")
	TEST_ASSERT_NULL(GLOB.derives_running, "Completed computation releases the lazy recursion guard before deletion")
	qdel(first)
	var/obj/item/dq_derives_probe/second = allocate(/obj/item/dq_derives_probe, T)
	TEST_ASSERT_EQUAL(second.summary, "1000", "A new holder computes after the previous holder was deleted")
	second.set_pressure(7)
	TEST_ASSERT_EQUAL(second.summary, "70", "The new holder continues to recompute after input changes")

/// derives() from a relation a constructor param fills: the param is written from /atom/New(), before the instance's lifeform plan has
/// run, and the write must not recompute (it crashed with "bad index"); init computes it.
/obj/item/dq_derives_param_probe
	name = "derives param probe"
	var/obj/item/dq_derives_probe/source = null
	var/source_summary = null

CAPABILITIES(/obj/item/dq_derives_param_probe)
	ref_one(nameof(source), /obj/item/dq_derives_probe)
	param(nameof(source), pos = 1)
	derives(nameof(source_summary), PROC_REF(read_source), from = list(nameof(source)))

/obj/item/dq_derives_param_probe/proc/read_source()
	return source?.summary

/datum/unit_test/dq_lifeform_derives_param

/datum/unit_test/dq_lifeform_derives_param/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_derives_probe/S = allocate(/obj/item/dq_derives_probe, T)
	var/obj/item/dq_derives_param_probe/P = allocate(/obj/item/dq_derives_param_probe, T, S)
	TEST_ASSERT_EQUAL(P.source, S, "the positional param filled the relation")
	TEST_ASSERT_EQUAL(P.source_summary, "1000", "derives() from a param-written relation computes at init")
	rel_set(P, nameof(P.source), null)
	TEST_ASSERT_EQUAL(P.source_summary, null, "and follows later writes")
