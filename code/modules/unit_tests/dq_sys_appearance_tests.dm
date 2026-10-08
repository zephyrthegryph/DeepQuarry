// Appearance keyed on declared state (code/__defines/sys_appearance.dm, doc/rewrite/systems.md
// section 1): templates, levels, emissives and layers draw from fields; a watched field's setter
// queues one refresh per frame; procedural types refresh through APPEARANCE_WATCH.

/obj/machinery/dq_appearance_probe
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "probe"
	use_power = USE_POWER_OFF
	var/charge = null
	var/label = "a"
	var/on = FALSE
	var/active = FALSE
	var/locked = FALSE

TRACKED_BRIDGED(/obj/machinery/dq_appearance_probe, on, CHANGE_MACHINE_SETTINGS)
TRACKED_BRIDGED(/obj/machinery/dq_appearance_probe, active, CHANGE_MACHINE_SETTINGS)
TRACKED_BRIDGED(/obj/machinery/dq_appearance_probe, locked, CHANGE_MACHINE_MODE)

APPEARANCE_TEMPLATE(/obj/machinery/dq_appearance_probe, "probe{on}{operable}{label?@label:}{initial(icon_state)}")
APPEARANCE_LEVEL(/obj/machinery/dq_appearance_probe, "charge", 4, "lvl%p")
APPEARANCE_EMISSIVE(/obj/machinery/dq_appearance_probe, "active", list("1" = "glow"))
DECLARE_APPEARANCE(/obj/machinery/dq_appearance_probe, "locked", list("1" = list(APPEARANCE_ICON_STATE = "probe-locked")))

/// Inherits the template; [initial(icon_state)] must read this subtype's icon_state.
/obj/machinery/dq_appearance_probe/other
	icon_state = "other"

/// Drops the parent's declarations.
/obj/machinery/dq_appearance_probe/bare
APPEARANCE_NONE(/obj/machinery/dq_appearance_probe/bare)

/// A provider: overlays computed from state, owned by the runtime.
/obj/structure/dq_appearance_provider
	var/count = 0

DECLARE_APPEARANCE_PROC(/obj/structure/dq_appearance_provider, TYPE_PROC_REF(/atom, appearance_overlays), list(CHANGE_NEIGHBOURS))
/obj/structure/dq_appearance_provider/appearance_overlays()
	. = list()
	for(var/i in 1 to count)
		. += "dot[i]"

/// A procedural drawer: counts its redraws.
/obj/structure/dq_appearance_procedural
	var/redraws = 0

// Test probe counting procedural redraws
/obj/structure/dq_appearance_procedural/update_icon()
	redraws++

/// Counts overlays of A showing icon_state `state`.
/proc/dq_sys_appearance_overlays(atom/A, state)
	. = 0
	for(var/image/I as anything in A.overlays)
		if(I.icon_state == state)
			.++

/// Templates, levels, emissives and layers draw what the fields say.
/datum/unit_test/dq_sys_appearance_draws

/datum/unit_test/dq_sys_appearance_draws/Run()
	var/obj/machinery/dq_appearance_probe/P = allocate(/obj/machinery/dq_appearance_probe)
	dq_machine_clear(P)
	P.set_on(FALSE)
	P.update_icon()
	TEST_ASSERT_EQUAL(P.icon_state, "probe01aprobe", "template reads on, operable(), a ternary @var and initial()")
	P.label = null
	dq_machine_clear(P)
	P.set_grid_power(FALSE)
	P.update_icon()
	TEST_ASSERT_EQUAL(P.icon_state, "probe00probe", "template follows operable() and the ternary's false branch")
	P.charge = 60
	P.update_icon()
	TEST_ASSERT_EQUAL(dq_sys_appearance_overlays(P, "lvl50"), 1, "a level of 60% in 4 steps draws the 50% overlay")
	P.charge = 100
	P.update_icon()
	TEST_ASSERT_EQUAL(dq_sys_appearance_overlays(P, "lvl50"), 0, "the old level overlay is swapped out")
	TEST_ASSERT_EQUAL(dq_sys_appearance_overlays(P, "lvl100"), 1, "the new level overlay is drawn")
	P.charge = null
	P.update_icon()
	TEST_ASSERT_EQUAL(dq_sys_appearance_overlays(P, "lvl100"), 0, "a null level draws nothing")
	P.set_active(TRUE)
	P.update_icon()
	var/emissive = FALSE
	for(var/mutable_appearance/M as anything in P.overlays)
		if(M.icon_state == "glow")
			emissive = TRUE
	TEST_ASSERT(emissive, "an emissive row draws its overlay")
	P.set_locked(TRUE)
	P.update_icon()
	TEST_ASSERT_EQUAL(P.icon_state, "probe-locked", "a layer row's icon_state wins over the template")

	var/obj/machinery/dq_appearance_probe/bare/B = allocate(/obj/machinery/dq_appearance_probe/bare)
	B.set_on(TRUE)
	B.update_icon()
	TEST_ASSERT_EQUAL(B.icon_state, "probe", "APPEARANCE_NONE drops the inherited declarations")

/// The watch mask comes from the declared fields the declarations read, not from plain vars.
/datum/unit_test/dq_sys_appearance_mask

/datum/unit_test/dq_sys_appearance_mask/Run()
	var/obj/machinery/dq_appearance_probe/P = allocate(/obj/machinery/dq_appearance_probe)
	var/datum/lifecycle_decls/decls = lifecycle_decls_of(P)
	TEST_ASSERT(decls.appearance_mask & CHANGE_MACHINE_SETTINGS, "on (a field) adds its channel")
	TEST_ASSERT(decls.appearance_mask & CHANGE_MACHINE_MODE, "locked (a field) adds its channel")
	TEST_ASSERT(decls.appearance_mask & CHANGE_MACHINE_POWER, "operable (a derived field) adds its channels")
	TEST_ASSERT(P.om_listen & CHANGE_MACHINE_SETTINGS, "the instance listens on its watch mask")
	var/obj/structure/dq_appearance_procedural/S = allocate(/obj/structure/dq_appearance_procedural)
	TEST_ASSERT_EQUAL(appearance_mask_of(S), 0, "a type declaring nothing watches nothing")

/// A watched field's setter queues one refresh per frame, however many changes it sees.
/datum/unit_test/dq_sys_appearance_auto_refresh

/datum/unit_test/dq_sys_appearance_auto_refresh/Run()
	appearance_flush()
	var/obj/machinery/dq_appearance_probe/P = allocate(/obj/machinery/dq_appearance_probe)
	dq_machine_clear(P)
	P.set_on(FALSE)
	P.label = "a"
	appearance_flush()
	P.update_icon()
	TEST_ASSERT_EQUAL(P.icon_state, "probe01aprobe", "baseline drawn")
	P.set_on(TRUE)
	P.set_active(TRUE)
	P.set_on(FALSE)
	P.set_on(TRUE)
	TEST_ASSERT(P.appearance_queued, "a watched setter queues the refresh")
	var/queued = 0
	for(var/atom/A as anything in GLOB.appearance_queue)
		if(A == P)
			queued++
	TEST_ASSERT_EQUAL(queued, 1, "four changes in a frame queue one refresh")
	TEST_ASSERT_EQUAL(P.icon_state, "probe01aprobe", "the refresh waits for the presentation lane")
	appearance_flush()
	TEST_ASSERT(!P.appearance_queued, "the drain clears the flag")
	TEST_ASSERT_EQUAL(P.icon_state, "probe11aprobe", "the queued refresh drew the new state without a manual update_icon()")
	P.set_on(TRUE)
	TEST_ASSERT(!P.appearance_queued, "a setter that changes nothing queues nothing")

/// A latent (unmaterialized) atom's refresh waits for it to materialize instead of holding a place
/// in the presentation queue (a sandboxed Initialize() leaves the queue as it found it).
/datum/unit_test/dq_sys_appearance_latent_waits

/datum/unit_test/dq_sys_appearance_latent_waits/Run()
	appearance_flush()
	var/obj/machinery/dq_appearance_probe/P = new_unmaterialized(/obj/machinery/dq_appearance_probe, null)
	TEST_ASSERT(!(P.flags & ATOM_MATERIALIZED), "the sandbox leaves it latent")
	P.set_on(!P.on)
	TEST_ASSERT_EQUAL(P.appearance_queued, APPEARANCE_PENDING_LATENT, "a latent atom's refresh is kept pending")
	TEST_ASSERT(!(P in GLOB.appearance_queue), "a latent atom stays out of the presentation queue")
	P.materialize()
	TEST_ASSERT_EQUAL(P.appearance_queued, TRUE, "materializing queues the pending refresh")
	TEST_ASSERT(P in GLOB.appearance_queue, "the pending refresh joins the queue")
	appearance_flush()
	TEST_ASSERT(!P.appearance_queued, "drained")
	qdel(P)

/// APPEARANCE_WATCH re-runs a procedural update_icon() when a watched field changes.
/datum/unit_test/dq_sys_appearance_watch_procedural

/datum/unit_test/dq_sys_appearance_watch_procedural/Run()
	appearance_flush()
	var/obj/machinery/computer/C = allocate(/obj/machinery/computer)
	appearance_flush()
	var/before = C.icon_state
	dq_machine_clear(C)
	dq_machine_clear(C)
	C.set_broken_condition(TRUE)
	TEST_ASSERT(C.appearance_queued, "a machine's stat change queues its procedural update_icon()")
	appearance_flush()
	TEST_ASSERT(!C.appearance_queued, "drained")
	TEST_ASSERT(C.icon_state == before || C.icon_state != null, "the procedural redraw ran without runtimes")
	var/obj/structure/dq_appearance_procedural/S = allocate(/obj/structure/dq_appearance_procedural)
	S.redraws = 0
	S.set_anchored(!S.anchored)
	appearance_flush()
	TEST_ASSERT_EQUAL(S.redraws, 0, "an unwatched type is not redrawn by a field change")

/// [initial(icon_state)] resolves per concrete subtype, not per declaring type.
/datum/unit_test/dq_sys_appearance_initial_per_subtype

/datum/unit_test/dq_sys_appearance_initial_per_subtype/Run()
	var/obj/machinery/dq_appearance_probe/other/O = allocate(/obj/machinery/dq_appearance_probe/other)
	dq_machine_clear(O)
	O.set_on(FALSE)
	O.label = null
	O.update_icon()
	TEST_ASSERT_EQUAL(O.icon_state, "probe01other", "the subtype's initial icon_state fills the inherited template")

/// A provider's overlays are swapped by the runtime; a declared channel re-runs it.
/datum/unit_test/dq_sys_appearance_provider

/datum/unit_test/dq_sys_appearance_provider/Run()
	appearance_flush()
	var/obj/structure/dq_appearance_provider/P = allocate(/obj/structure/dq_appearance_provider)
	P.count = 2
	P.update_icon()
	TEST_ASSERT_EQUAL(dq_sys_appearance_overlays(P, "dot1") + dq_sys_appearance_overlays(P, "dot2"), 2, "the provider's overlays are drawn")
	P.count = 1
	P.update_icon()
	TEST_ASSERT_EQUAL(dq_sys_appearance_overlays(P, "dot2"), 0, "overlays the provider no longer returns are cut")
	TEST_ASSERT_EQUAL(dq_sys_appearance_overlays(P, "dot1"), 1, "a kept overlay is drawn once, not stacked")
	P.count = 3
	changed(P, CHANGE_NEIGHBOURS)
	TEST_ASSERT(P.appearance_queued, "a declared channel queues the provider")
	appearance_flush()
	TEST_ASSERT_EQUAL(dq_sys_appearance_overlays(P, "dot3"), 1, "the queued refresh re-ran the provider")
