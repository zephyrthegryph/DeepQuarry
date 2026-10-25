// The init phase 0 forms (doc/rewrite/proposals/init_phase0.md): preset(), param(apply =, early = TRUE) and keeps_if(instead =).

// ---- preset() ----

/obj/item/dq_preset_probe
	name = "preset probe"
	var/preset_base = 0
	var/preset_double = 0
	var/preset_label = null
	var/preset_gated = 0
	var/preset_gate = FALSE
	/// What Initialize() saw: a preset is in place before the type's init code runs.
	var/double_at_init = null
	var/label_at_init = null

CAPABILITIES(/obj/item/dq_preset_probe)
	param(nameof(preset_base), num(0, 100))
	param(nameof(preset_gate))
	// Declared before its dependency on purpose: from = orders it after preset_double.
	preset(nameof(preset_label), PROC_REF(label_from_double), from = list(nameof(preset_double)))
	preset(nameof(preset_double), PROC_REF(double_of_base))
	preset(nameof(preset_gated), PROC_REF(gated_value), when = nameof(preset_gate))

/obj/item/dq_preset_probe/proc/double_of_base(target)
	return preset_base * 2

/obj/item/dq_preset_probe/proc/label_from_double(target)
	return "double-[preset_double]"

/obj/item/dq_preset_probe/proc/gated_value(target)
	return 7

/obj/item/dq_preset_probe/Initialize(mapload)
	. = ..()
	double_at_init = preset_double
	label_at_init = preset_label

/// A mapped value (a compiled default that differs) suppresses the preset, as it does a roll.
/obj/item/dq_preset_probe/mapped
	preset_double = 99

/datum/unit_test/dq_preset_form

/datum/unit_test/dq_preset_form/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_preset_probe/P = make(/obj/item/dq_preset_probe, at = T, preset_base = 6)
	own(P)
	TEST_ASSERT_EQUAL(P.double_at_init, 12, "a preset is computed from a param before the type's init code runs")
	TEST_ASSERT_EQUAL(P.label_at_init, "double-12", "from = orders a preset after the preset it reads, whatever the declaration order")
	TEST_ASSERT_EQUAL(P.preset_gated, 0, "a preset whose when = condition is false is not set")

	var/obj/item/dq_preset_probe/gated = make(/obj/item/dq_preset_probe, at = T, preset_gate = TRUE)
	own(gated)
	TEST_ASSERT_EQUAL(gated.preset_gated, 7, "a preset whose when = condition holds is set")

	var/obj/item/dq_preset_probe/mapped/M = make(/obj/item/dq_preset_probe/mapped, at = T, preset_base = 6)
	own(M)
	TEST_ASSERT_EQUAL(M.preset_double, 99, "a value that differs from the compiled default suppresses the preset")

// ---- param(apply =, early = TRUE) ----

/obj/item/dq_early_param_base
	name = "early param base"
	var/early_value = 0
	/// What the chain's code before the parent call saw (the reason a param goes early).
	var/applied = 0
	var/seen_before_chain = null
	var/seen_by_root_form = null

/obj/item/dq_early_param_base/proc/apply_early(value)
	applied = value + 1

CAPABILITIES(/obj/item/dq_early_param_base)
	param(nameof(early_value), num(0, 100), default = 3, apply = PROC_REF(apply_early), early = TRUE)
	preset(nameof(seen_by_root_form), PROC_REF(read_applied))

/obj/item/dq_early_param_base/proc/read_applied(target)
	return applied

/obj/item/dq_early_param_base/Initialize(mapload)
	seen_before_chain = applied
	. = ..()

/obj/item/dq_late_param_probe
	name = "late param probe"
	var/late_value = 0
	var/applied_late = 0
	var/seen_before_chain = null

/obj/item/dq_late_param_probe/proc/apply_late(value)
	applied_late = value + 1

CAPABILITIES(/obj/item/dq_late_param_probe)
	param(nameof(late_value), num(0, 100), apply = PROC_REF(apply_late))

/obj/item/dq_late_param_probe/Initialize(mapload)
	seen_before_chain = applied_late
	. = ..()

/datum/unit_test/dq_param_early_apply

/datum/unit_test/dq_param_early_apply/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_early_param_base/E = make(/obj/item/dq_early_param_base, at = T, early_value = 40)
	own(E)
	TEST_ASSERT_EQUAL(E.seen_before_chain, 41, "an early param's setter has run before the Initialize() chain")
	TEST_ASSERT_EQUAL(E.seen_by_root_form, 41, "and before the forms of the chain's root")
	TEST_ASSERT_EQUAL(E.applied, 41, "the setter runs once")

	var/obj/item/dq_early_param_base/defaulted = make(/obj/item/dq_early_param_base, at = T)
	own(defaulted)
	TEST_ASSERT_EQUAL(defaulted.seen_before_chain, 4, "a param nothing gave is defaulted before its early setter runs")

	var/obj/item/dq_late_param_probe/L = make(/obj/item/dq_late_param_probe, at = T, late_value = 10)
	own(L)
	TEST_ASSERT_EQUAL(L.seen_before_chain, 0, "an ordinary apply = still runs after the chain's pre-parent code")
	TEST_ASSERT_EQUAL(L.applied_late, 11, "and runs once at init")

// ---- keeps_if(instead =) ----

GLOBAL_LIST_EMPTY(dq_instead_log)

/obj/item/dq_instead_probe
	name = "instead probe"
	var/instead_allows = TRUE

CAPABILITIES(/obj/item/dq_instead_probe)
	param(nameof(instead_allows))
	keeps_if(PROC_REF(allowed), instead = PROC_REF(left_behind))

/obj/item/dq_instead_probe/proc/allowed()
	return instead_allows

/obj/item/dq_instead_probe/proc/left_behind()
	GLOB.dq_instead_log += "[type]@[loc]"

/datum/unit_test/dq_keeps_if_instead

/datum/unit_test/dq_keeps_if_instead/Run()
	var/turf/T = dq_containment_floor()
	GLOB.dq_instead_log.Cut()
	var/obj/item/dq_instead_probe/kept = make(/obj/item/dq_instead_probe, at = T)
	own(kept)
	TEST_ASSERT(!QDELETED(kept), "an instance whose condition holds is kept")
	TEST_ASSERT_EQUAL(length(GLOB.dq_instead_log), 0, "instead = does not run for a kept instance")

	var/obj/item/dq_instead_probe/dropped = make(/obj/item/dq_instead_probe, at = T, instead_allows = FALSE)
	TEST_ASSERT(QDELETED(dropped), "an instance whose condition fails is discarded")
	TEST_ASSERT_EQUAL(length(GLOB.dq_instead_log), 1, "instead = runs once for the discarded instance")
	TEST_ASSERT_EQUAL(GLOB.dq_instead_log[1], "[/obj/item/dq_instead_probe]@[T]", "instead = runs while the instance is still in place")
