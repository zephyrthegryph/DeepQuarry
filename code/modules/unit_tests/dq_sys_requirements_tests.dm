// Requirement clauses over the target's state (doc/rewrite/systems.md section 6).

/obj/dq_req_probe
	name = "requirement probe"
	anchored = TRUE
	var/locked = FALSE
	var/cover
	var/list/parts
	var/obj/item/fitted
	var/mode = 1
	var/panel_open = FALSE
	var/emagged = FALSE
	var/working = TRUE
	var/uses = 0

/// A derived field: native requirement("operable") calls it.
/obj/dq_req_probe/proc/operable()
	return working

MSG_DEF_SELF(dq_req/locked, "it's locked")
MSG_DEF_SELF(dq_req/inoperable, "it isn't operable")

CAPABILITIES(/obj/dq_req_probe)
	op("dq_req_toggle", hand(), label("Toggle"), needs(req(PROC_REF(is_operable), because = MSG(dq_req/inoperable)), req(PROC_REF(is_unlocked), because = MSG(dq_req/locked))), then(PROC_REF(dq_req_toggle)))

/obj/dq_req_probe/proc/is_operable(datum/act/A)
	return read_once(operable()) ? null : MSG(dq_req/inoperable)

/obj/dq_req_probe/proc/is_unlocked(datum/act/A)
	return read_once(!locked) ? null : MSG(dq_req/locked)

/obj/dq_req_probe/proc/dq_req_toggle(datum/act/op/A)
	uses++
	return OP_OK

/// Evaluate a genuine native requirement with the real probe and actor context.
/datum/unit_test/proc/dq_req_reason(key, datum/entry/part/req/R, mob/actor, atom/target)
	var/datum/act/op/A = allocate(/datum/act/op)
	A.holder = target
	A.target = target
	A.actor = actor
	return op_req_check(A, R)

/// Field clauses pass and fail on the field's truth, and generate their reasons from the name and value.
/datum/unit_test/dq_sys_requirements_fields

/datum/unit_test/dq_sys_requirements_fields/Run()
	var/turf/T = test_floor()
	var/obj/dq_req_probe/probe = allocate(/obj/dq_req_probe, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	TEST_ASSERT_NULL(dq_req_reason("not_locked", req(TYPE_PROC_REF(/obj/dq_req_probe, check_unlocked)), H, probe), "an unlocked probe passes native requirement")
	probe.locked = TRUE
	TEST_ASSERT_EQUAL(dq_req_reason("not_locked", req(TYPE_PROC_REF(/obj/dq_req_probe, check_unlocked)), H, probe), "it's locked", "generated reason for a set flag")
	TEST_ASSERT_EQUAL(dq_req_reason("not_locked_custom", req(TYPE_PROC_REF(/obj/dq_req_probe, check_unlocked), because = "the controls are locked"), H, probe), "the controls are locked", "a declared reason replaces the generated one")

	TEST_ASSERT_EQUAL(dq_req_reason("has_cover", req(TYPE_PROC_REF(/obj/dq_req_probe, check_cover)), H, probe), "it has no cover", "a null field has none")
	probe.cover = "steel"
	TEST_ASSERT_NULL(dq_req_reason("has_cover", req(TYPE_PROC_REF(/obj/dq_req_probe, check_cover)), H, probe), "a set field passes")

	TEST_ASSERT_EQUAL(dq_req_reason("has_parts", req(TYPE_PROC_REF(/obj/dq_req_probe, check_parts)), H, probe), "it has no parts", "a null list has none")
	probe.parts = list()
	TEST_ASSERT_EQUAL(dq_req_reason("has_parts", req(TYPE_PROC_REF(/obj/dq_req_probe, check_parts)), H, probe), "it has no parts", "an empty list counts as false")
	probe.parts += "gear"
	TEST_ASSERT_NULL(dq_req_reason("has_parts", req(TYPE_PROC_REF(/obj/dq_req_probe, check_parts)), H, probe), "a filled list passes")

	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, probe)
	rel_set(probe, nameof(probe.fitted), wrench)
	TEST_ASSERT_EQUAL(dq_req_reason("no_fitted", req(TYPE_PROC_REF(/obj/dq_req_probe, check_no_fitted)), H, probe), "it already has \a [wrench]", "an atom in the way is named")

	TEST_ASSERT_NULL(dq_req_reason("mode_one", req(TYPE_PROC_REF(/obj/dq_req_probe, check_mode_one)), H, probe), "native requirement passes on the value")
	probe.mode = 2
	TEST_ASSERT_EQUAL(dq_req_reason("mode_one", req(TYPE_PROC_REF(/obj/dq_req_probe, check_mode_one)), H, probe), "its mode must be 1", "native requirement's generated reason")
	TEST_ASSERT_NULL(dq_req_reason("mode_not_one", req_not(req(TYPE_PROC_REF(/obj/dq_req_probe, check_mode_one))), H, probe), "negated native requirement")

	TEST_ASSERT_NULL(dq_req_reason("operable", req(TYPE_PROC_REF(/obj/dq_req_probe, check_operable)), H, probe), "a derived field is read through its proc")
	probe.working = FALSE
	TEST_ASSERT_EQUAL(dq_req_reason("operable", req(TYPE_PROC_REF(/obj/dq_req_probe, check_operable)), H, probe), "it isn't operable", "a false derived field")

	// Numeric native acceptance constructors reject an actual wrong property unit.
	var/rejected = FALSE
	try
		req_acceptance_max_size(ITEMSIZE_SMALL, PROP_UNIT_KELVIN)
	catch(var/exception/bad_unit)
		rejected = TRUE
	TEST_ASSERT(rejected, "A wrong size unit must not silently construct an accepting requirement")

/// Anchoring, panel, emag and access clauses.
/datum/unit_test/dq_sys_requirements_state

/datum/unit_test/dq_sys_requirements_state/Run()
	var/turf/T = test_floor()
	var/obj/dq_req_probe/probe = allocate(/obj/dq_req_probe, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	TEST_ASSERT_NULL(dq_req_reason("anchored", req(TYPE_PROC_REF(/obj/dq_req_probe, check_anchored)), H, probe), "anchored passes")
	TEST_ASSERT_EQUAL(dq_req_reason("unanchored", req_not(req(TYPE_PROC_REF(/obj/dq_req_probe, check_anchored)), because = "unanchor it first"), H, probe), "unanchor it first", "must be unanchored")
	probe.set_anchored(FALSE)
	TEST_ASSERT_EQUAL(dq_req_reason("anchored", req(TYPE_PROC_REF(/obj/dq_req_probe, check_anchored)), H, probe), "it must be anchored first", "must be anchored")

	TEST_ASSERT_EQUAL(dq_req_reason("panel_open", req(TYPE_PROC_REF(/obj/dq_req_probe, check_panel_open)), H, probe), "open the maintenance panel first", "panel must be open")
	TEST_ASSERT_NULL(dq_req_reason("panel_closed", req(TYPE_PROC_REF(/obj/dq_req_probe, check_panel_closed)), H, probe), "a closed panel passes native requirement(FALSE)")
	probe.panel_open = TRUE
	TEST_ASSERT_EQUAL(dq_req_reason("panel_closed", req(TYPE_PROC_REF(/obj/dq_req_probe, check_panel_closed)), H, probe), "close the maintenance panel first", "panel must be closed")

	TEST_ASSERT_NULL(dq_req_reason("not_emagged", req(TYPE_PROC_REF(/obj/dq_req_probe, check_not_emagged)), H, probe), "not emagged passes")
	probe.emagged = TRUE
	TEST_ASSERT_EQUAL(dq_req_reason("not_emagged", req(TYPE_PROC_REF(/obj/dq_req_probe, check_not_emagged)), H, probe), "its controls have been tampered with", "emagged fails")

	TEST_ASSERT_NULL(dq_req_reason("access", req(TYPE_PROC_REF(/obj/dq_req_probe, check_access)), H, probe), "no req_access: anyone passes")
	probe.req_access = list(ACCESS_CAPTAIN)
	TEST_ASSERT_EQUAL(dq_req_reason("access", req(TYPE_PROC_REF(/obj/dq_req_probe, check_access)), H, probe), "access denied", "an ID-less actor lacks the access")

/// A lifted guard: the Menu lists the op, and the op refuses with the guard's reason without running the effect.
/datum/unit_test/dq_sys_requirements_menu

/datum/unit_test/dq_sys_requirements_menu/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/obj/dq_req_probe/probe = allocate(/obj/dq_req_probe, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	var/list/names = list()
	for(var/list/row as anything in op_menu(H, probe, null))
		if(row["enabled"])
			names += row["label"]
	TEST_ASSERT("Toggle" in names, "offered while unlocked and working: [jointext(names, ",")]")

	probe.locked = TRUE
	var/datum/op_result/refused = test_click(H, probe, null)
	TEST_ASSERT_EQUAL(refused?.outcome, ACT_REFUSED, "the touch is refused")
	TEST_ASSERT_EQUAL(reason_text(refused?.reason), "it's locked", "with the guard's reason")
	TEST_ASSERT_EQUAL(probe.uses, 0, "the effect didn't run")

	probe.locked = FALSE
	cooldown_set_end(H, next_click, 0)
	test_click(H, probe, null)
	TEST_ASSERT_EQUAL(probe.uses, 1, "unlocked, the effect runs")
	test_driver_end()

/obj/dq_req_probe/proc/check_unlocked(datum/act/op/A)
	return read_once(locked) ? "it's locked" : null

/obj/dq_req_probe/proc/check_cover(datum/act/op/A)
	return read_once(cover) ? null : "it has no cover"

/obj/dq_req_probe/proc/check_parts(datum/act/op/A)
	return read_once(length(parts)) ? null : "it has no parts"

/obj/dq_req_probe/proc/check_no_fitted(datum/act/op/A)
	return read_once(fitted) ? "it already has \a [fitted]" : null

/obj/dq_req_probe/proc/check_mode_one(datum/act/op/A)
	return read_once(mode == 1) ? null : "its mode must be 1"

/obj/dq_req_probe/proc/check_operable(datum/act/op/A)
	return read_once(operable()) ? null : "it isn't operable"

/obj/dq_req_probe/proc/check_anchored(datum/act/op/A)
	return anchored ? null : "it must be anchored first"

/obj/dq_req_probe/proc/check_panel_open(datum/act/op/A)
	return read_once(panel_open) ? null : "open the maintenance panel first"

/obj/dq_req_probe/proc/check_panel_closed(datum/act/op/A)
	return read_once(panel_open) ? "close the maintenance panel first" : null

/obj/dq_req_probe/proc/check_not_emagged(datum/act/op/A)
	return read_once(emagged) ? "its controls have been tampered with" : null

/obj/dq_req_probe/proc/check_access(datum/act/op/A)
	return read_once(allowed(A.actor)) ? null : "access denied"
