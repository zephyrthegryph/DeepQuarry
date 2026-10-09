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

/// A derived field: REQ_FIELD("operable") calls it.
/obj/dq_req_probe/proc/operable()
	return working

MSG_DEF_SELF(dq_req/locked, "it's locked")
MSG_DEF_SELF(dq_req/inoperable, "it isn't operable")

CAPABILITIES(/obj/dq_req_probe)
	op("dq_req_toggle", hand(), label("Toggle"), needs(req(PROC_REF(is_operable), because = MSG(dq_req/inoperable)), req(PROC_REF(is_unlocked), because = MSG(dq_req/locked))), then(PROC_REF(dq_req_toggle)))

/obj/dq_req_probe/proc/is_operable(datum/act/A)
	return read_once(operable())

/obj/dq_req_probe/proc/is_unlocked(datum/act/A)
	return read_once(!locked)

/obj/dq_req_probe/proc/dq_req_toggle(datum/act/op/A)
	uses++
	return OP_OK

/// null if the one-clause spec passes on `probe`, else its reason.
/datum/unit_test/proc/dq_req_reason(key, list/spec, mob/actor, atom/target)
	var/datum/predicate/P = dq_predicate_for("dq_req_test:[key]", spec)
	TEST_ASSERT_NULL(P.errors, "[key] compiles: [jointext(P.errors || list(), "; ")]")
	return P.why_not(actor, target, null)

/// Field clauses pass and fail on the field's truth, and generate their reasons from the name and value.
/datum/unit_test/dq_sys_requirements_fields

/datum/unit_test/dq_sys_requirements_fields/Run()
	var/turf/T = test_floor()
	var/obj/dq_req_probe/probe = allocate(/obj/dq_req_probe, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	TEST_ASSERT_NULL(dq_req_reason("not_locked", list(REQ_FIELD_NOT("locked")), H, probe), "an unlocked probe passes REQ_FIELD_NOT")
	probe.locked = TRUE
	TEST_ASSERT_EQUAL(dq_req_reason("not_locked", list(REQ_FIELD_NOT("locked")), H, probe), "it's locked", "generated reason for a set flag")
	TEST_ASSERT_EQUAL(dq_req_reason("not_locked_custom", list(REQ_FIELD_NOT("locked", "the controls are locked")), H, probe), "the controls are locked", "a declared reason replaces the generated one")

	TEST_ASSERT_EQUAL(dq_req_reason("has_cover", list(REQ_FIELD("cover")), H, probe), "it has no cover", "a null field has none")
	probe.cover = "steel"
	TEST_ASSERT_NULL(dq_req_reason("has_cover", list(REQ_FIELD("cover")), H, probe), "a set field passes")

	TEST_ASSERT_EQUAL(dq_req_reason("has_parts", list(REQ_FIELD("parts")), H, probe), "it has no parts", "a null list has none")
	probe.parts = list()
	TEST_ASSERT_EQUAL(dq_req_reason("has_parts", list(REQ_FIELD("parts")), H, probe), "it has no parts", "an empty list counts as false")
	probe.parts += "gear"
	TEST_ASSERT_NULL(dq_req_reason("has_parts", list(REQ_FIELD("parts")), H, probe), "a filled list passes")

	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, probe)
	rel_set(probe, nameof(probe.fitted), wrench)
	TEST_ASSERT_EQUAL(dq_req_reason("no_fitted", list(REQ_FIELD_NOT("fitted")), H, probe), "it already has \a [wrench]", "an atom in the way is named")

	TEST_ASSERT_NULL(dq_req_reason("mode_one", list(REQ_FIELD_EQ("mode", 1)), H, probe), "REQ_FIELD_EQ passes on the value")
	probe.mode = 2
	TEST_ASSERT_EQUAL(dq_req_reason("mode_one", list(REQ_FIELD_EQ("mode", 1)), H, probe), "its mode must be 1", "REQ_FIELD_EQ's generated reason")
	TEST_ASSERT_NULL(dq_req_reason("mode_not_one", list(REQ_NOT(REQ_FIELD_EQ("mode", 1))), H, probe), "negated REQ_FIELD_EQ")

	TEST_ASSERT_NULL(dq_req_reason("operable", list(REQ_FIELD("operable")), H, probe), "a derived field is read through its proc")
	probe.working = FALSE
	TEST_ASSERT_EQUAL(dq_req_reason("operable", list(REQ_FIELD("operable")), H, probe), "it isn't operable", "a false derived field")

	var/datum/predicate/bad = new
	bad.spec = list(list(PRED_OP_FIELD, "locked", REQ_FIELD_MODE_TRUE, null, 5))
	bad.test_only = TRUE
	TEST_ASSERT(!bad.compile(), "a non-text reason is a compile error")

/// Anchoring, panel, emag and access clauses.
/datum/unit_test/dq_sys_requirements_state

/datum/unit_test/dq_sys_requirements_state/Run()
	var/turf/T = test_floor()
	var/obj/dq_req_probe/probe = allocate(/obj/dq_req_probe, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	TEST_ASSERT_NULL(dq_req_reason("anchored", list(REQ_ANCHORED), H, probe), "anchored passes")
	TEST_ASSERT_EQUAL(dq_req_reason("unanchored", list(REQ_NOT(REQ_ANCHORED)), H, probe), "unanchor it first", "must be unanchored")
	probe.set_anchored(FALSE)
	TEST_ASSERT_EQUAL(dq_req_reason("anchored", list(REQ_ANCHORED), H, probe), "it must be anchored first", "must be anchored")

	TEST_ASSERT_EQUAL(dq_req_reason("panel_open", list(REQ_PANEL(TRUE)), H, probe), "open the maintenance panel first", "panel must be open")
	TEST_ASSERT_NULL(dq_req_reason("panel_closed", list(REQ_PANEL(FALSE)), H, probe), "a closed panel passes REQ_PANEL(FALSE)")
	probe.panel_open = TRUE
	TEST_ASSERT_EQUAL(dq_req_reason("panel_closed", list(REQ_PANEL(FALSE)), H, probe), "close the maintenance panel first", "panel must be closed")

	TEST_ASSERT_NULL(dq_req_reason("not_emagged", list(REQ_NOT_EMAGGED), H, probe), "not emagged passes")
	probe.emagged = TRUE
	TEST_ASSERT_EQUAL(dq_req_reason("not_emagged", list(REQ_NOT_EMAGGED), H, probe), "its controls have been tampered with", "emagged fails")

	TEST_ASSERT_NULL(dq_req_reason("access", list(REQ_ACCESS), H, probe), "no req_access: anyone passes")
	probe.req_access = list(ACCESS_CAPTAIN)
	TEST_ASSERT_EQUAL(dq_req_reason("access", list(REQ_ACCESS), H, probe), "access denied", "an ID-less actor lacks the access")

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
	H.next_click = 0
	test_click(H, probe, null)
	TEST_ASSERT_EQUAL(probe.uses, 1, "unlocked, the effect runs")
	test_driver_end()
