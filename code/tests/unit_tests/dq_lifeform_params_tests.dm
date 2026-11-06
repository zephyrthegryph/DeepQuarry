// param(var, schema, default =, required =, pos =), make(type, at =, name = value...) and built_from() (code/engine/lifeforms/params.dm).

/obj/item/dq_param_probe
	name = "param probe"
	var/charge = 0
	var/label = "unlabelled"
	var/mob/made_for = null
	var/list/held_parts = null
	/// What Initialize() saw: params are in place before the type's init code runs.
	var/charge_at_init = null
	var/label_at_init = null

CAPABILITIES(/obj/item/dq_param_probe)
	param(nameof(charge), int(0, 100), default = 5)
	param(nameof(label), schema_text(), pos = 1)
	param(nameof(made_for), /mob)
	built_from(nameof(held_parts))

/obj/item/dq_param_probe/Initialize(mapload)
	. = ..()
	charge_at_init = charge
	label_at_init = label

/obj/item/dq_param_part
	name = "param part"

/// A plain datum with a param: make() sets it before New() returns, and the required one is reported when missing.
/datum/dq_param_record
	var/amount = 0
	var/needed = null
	var/amount_in_new = null

CAPABILITIES(/datum/dq_param_record)
	param(nameof(amount), num(0, 10))
	param(nameof(needed), required = TRUE)

/datum/dq_param_record/New()
	. = ..()
	amount_in_new = amount

/datum/unit_test/dq_lifeform_params

/datum/unit_test/dq_lifeform_params/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)

	var/obj/item/dq_param_probe/P = make(/obj/item/dq_param_probe, at = T, by = user, charge = 40, label = "spare", made_for = OWNER)
	own(P)
	TEST_ASSERT_EQUAL(P.loc, T, "make(at =) places the instance")
	TEST_ASSERT_EQUAL(P.charge_at_init, 40, "a param is set before the type's init code runs")
	TEST_ASSERT_EQUAL(P.label_at_init, "spare", "every given param is set before init")
	TEST_ASSERT_EQUAL(P.made_for, user, "OWNER in a make() argument is `by`")

	var/obj/item/dq_param_probe/defaulted = make(/obj/item/dq_param_probe, at = T)
	own(defaulted)
	TEST_ASSERT_EQUAL(defaulted.charge, 5, "a param nothing gave takes its default")

	var/obj/item/dq_param_probe/clamped = make(/obj/item/dq_param_probe, at = T, charge = 500)
	own(clamped)
	TEST_ASSERT_EQUAL(clamped.charge, 100, "a value outside an int() schema is clamped")

	var/obj/item/dq_param_probe/positional = allocate(/obj/item/dq_param_probe, T, "by position")
	TEST_ASSERT_EQUAL(positional.label_at_init, "by position", "a positional constructor argument fills the param(pos = 1)")

	var/obj/item/dq_param_part/part_a = allocate(/obj/item/dq_param_part, T)
	var/obj/item/dq_param_part/part_b = allocate(/obj/item/dq_param_part, T)
	var/obj/item/dq_param_probe/built = make(/obj/item/dq_param_probe, at = T, parts = list(part_a, part_b))
	own(built)
	TEST_ASSERT_EQUAL(length(built.held_parts), 2, "built_from() holds the parts make() handed over")
	TEST_ASSERT_EQUAL(part_a.loc, built, "a part moves into what it built")

	var/datum/dq_param_record/record = make(/datum/dq_param_record, amount = 3, needed = "yes")
	TEST_ASSERT_EQUAL(record.amount_in_new, 3, "a plain datum's params are set before its New() body runs")
	qdel(record)

	GLOB.declare_report_capture = list()
	var/datum/dq_param_record/missing = make(/datum/dq_param_record, amount = 2)
	var/list/reports = GLOB.declare_report_capture
	GLOB.declare_report_capture = null
	qdel(missing)
	var/found = FALSE
	for(var/line in reports)
		if(findtext(line, "required param needed"))
			found = TRUE
	TEST_ASSERT(found, "a missing required param is reported ([jointext(reports, " | ")])")
