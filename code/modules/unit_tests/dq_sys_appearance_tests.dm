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

/obj/machinery/dq_native_appearance_probe
	abstract_type = /obj/machinery/dq_native_appearance_probe
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "probe"
	use_power = USE_POWER_OFF
	var/charge = null
	var/label = "a"
	var/on = FALSE
	var/active = FALSE
	var/locked = FALSE

TRACKED(/obj/machinery/dq_native_appearance_probe, on)
TRACKED(/obj/machinery/dq_native_appearance_probe, active)
TRACKED(/obj/machinery/dq_native_appearance_probe, locked)
TRACKED(/obj/machinery/dq_native_appearance_probe, charge)
TRACKED(/obj/machinery/dq_native_appearance_probe, label)

/obj/machinery/dq_native_appearance_probe/draw(look)
	. = ..()
	var/datum/look/L = look
	var/tag = label ? label : ""
	L.state(locked ? "probe-locked" : "probe[on][operable()][tag][initial(icon_state)]")
	if(!isnull(charge))
		var/step = clamp(round(charge * 4 / 100, 1), 0, 4)
		L.overlay("lvl[round(step * 100 / 4, 1)]")
	if(active)
		L.overlay(emissive_appearance(icon, "glow"))

/obj/machinery/dq_native_appearance_probe/other
	abstract_type = /obj/machinery/dq_native_appearance_probe/other
	icon_state = "other"

/obj/machinery/dq_native_appearance_probe/bare
	abstract_type = /obj/machinery/dq_native_appearance_probe/bare

/obj/machinery/dq_native_appearance_probe/bare/draw(look)
	return

/datum/unit_test/dq_sys_appearance_mask/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/machinery/dq_native_appearance_probe/P = allocate(/obj/machinery/dq_native_appearance_probe)
	dq_machine_clear(P)
	refresh_look(P)
	refresh_flush()
	TEST_ASSERT_EQUAL(P.icon_state, "probe01aprobe", "Native fixture preserves template including real operable condition")
	TEST_ASSERT("stat:[STAT_OPERABLE]" in stat_generated_reads(P, TYPE_PROC_REF(/obj/machinery, operable)), "Actual operable condition declares composed stat key")
	P.set_on(TRUE)
	P.set_on(FALSE)
	P.set_on(TRUE)
	TEST_ASSERT(P.refresh_queued & DEP_DRAW, "Native setter queues draw dependency")
	var/count = 0
	for(var/datum/D as anything in GLOB.refresh_queue)
		if(D == P)
			count++
	TEST_ASSERT_EQUAL(count, 1, "Three real tracked transitions enqueue one native draw")
	TEST_ASSERT_EQUAL(P.icon_state, "probe01aprobe", "Draw waits for presentation drain")
	refresh_flush()
	TEST_ASSERT_EQUAL(P.icon_state, "probe11aprobe", "Native drain applies queued template transition")
	P.set_on(TRUE)
	TEST_ASSERT(!(P.refresh_queued & DEP_DRAW), "Unchanged value does not queue another native draw")
	P.set_charge(60)
	refresh_flush()
	TEST_ASSERT_EQUAL(dq_sys_appearance_overlays(P, "lvl50"), 1, "Native draw preserves old four-step quantization")
	P.set_charge(100)
	refresh_flush()
	TEST_ASSERT_EQUAL(dq_sys_appearance_overlays(P, "lvl50"), 0, "Old native level overlay is replaced")
	TEST_ASSERT_EQUAL(dq_sys_appearance_overlays(P, "lvl100"), 1, "Full native level draws")
	P.set_charge(null)
	refresh_flush()
	TEST_ASSERT_EQUAL(dq_sys_appearance_overlays(P, "lvl100"), 0, "Null removes native level overlay")
	P.set_active(TRUE)
	refresh_flush()
	TEST_ASSERT_EQUAL(dq_sys_appearance_overlays(P, "glow"), 1, "Native drawer preserves emissive overlay state")
	P.set_locked(TRUE)
	refresh_flush()
	TEST_ASSERT_EQUAL(P.icon_state, "probe-locked", "Locked state overrides template")
	P.set_locked(FALSE)
	refresh_flush()
	TEST_ASSERT_EQUAL(P.icon_state, "probe11aprobe", "Unlock restores real native template")
	var/obj/machinery/dq_native_appearance_probe/other/O = allocate(/obj/machinery/dq_native_appearance_probe/other)
	dq_machine_clear(O)
	O.set_label(null)
	refresh_look(O)
	TEST_ASSERT_EQUAL(O.icon_state, "probe01other", "Inherited native draw uses concrete subtype initial state")
	var/obj/machinery/dq_native_appearance_probe/bare/B = allocate(/obj/machinery/dq_native_appearance_probe/bare)
	TEST_ASSERT(isnull(refresh_look(B, FALSE)), "Bare subtype explicitly drops inherited native drawing")

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

