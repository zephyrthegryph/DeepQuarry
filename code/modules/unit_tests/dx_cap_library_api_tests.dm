// The review-2 library API (code/datums/capabilities/library/): the standard gating arguments on
// every constructor, `layer =` and CAP_NO_LAYER, emag refusal ordering and delay, the removable
// cover, the accessors, and capability UI data nested under data["caps"].

/obj/cap_fixture/lib_gated
	var/ready = TRUE

/obj/cap_fixture/lib_gated/capabilities()
	. = ..()
	. += cap_cover(open_tool = BY_HAND, removable = TRUE, layer = CAP_NO_LAYER)
	. += cap_panel(blocked_by = COVER, needs = PROC_REF(lib_ready), else_say = "it isn't ready", works_unpowered = FALSE, layer = "hatch")
	. += cap_lock()

/obj/cap_fixture/lib_gated/proc/lib_ready(mob/user, obj/item/held)
	return ready

/obj/cap_fixture/lib_emag
	var/allow = FALSE
	var/effects = 0

/obj/cap_fixture/lib_emag/capabilities()
	. = ..()
	. += cap_emag(effect = PROC_REF(lib_effect), delay = 2 SECONDS, behind = PANEL)
	. += cap_panel()

/obj/cap_fixture/lib_emag/proc/lib_effect(mob/user, obj/item/card/emag/card)
	effects++
	return allow

/obj/cap_fixture/lib_slot
	var/obj/item/cell/cell

/obj/cap_fixture/lib_slot/capabilities()
	. = ..()
	. += cap_slot(nameof(cell), /obj/item/cell, layer = "cell", blocked_by = COVER)
	. += cap_cover(open_tool = BY_HAND)

/// Constructor gating reaches the entries: blocked_by, needs + else_say, works_unpowered = FALSE.
/datum/unit_test/dx_cap_library_gating/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/lib_gated/A = allocate(/obj/cap_fixture/lib_gated, T)
	var/datum/interaction/capability/panel_entry = cap_test_entry(A, "panel:[TOOL_SCREWDRIVER]")
	TEST_ASSERT_NOTNULL(panel_entry, "the panel entry")
	TEST_ASSERT_EQUAL(panel_entry.blocked_by, COVER, "blocked_by is merged onto the entry")
	TEST_ASSERT(!panel_entry.works_unpowered, "a capability-level works_unpowered = FALSE restricts its entry")
	TEST_ASSERT_NULL(cap_gate_reason(A, H, null, panel_entry), "the panel is reachable with the cover closed")
	A.ready = FALSE
	TEST_ASSERT_EQUAL(cap_gate_reason(A, H, null, panel_entry), "it isn't ready", "the constructor's needs refuses with its else_say")
	A.ready = TRUE
	A.powered = FALSE
	TEST_ASSERT_EQUAL(cap_gate_reason(A, H, null, panel_entry), "it has no power", "refused while unpowered")
	A.powered = TRUE
	cap_set(A, CAP_COVER_OPEN, TRUE)
	TEST_ASSERT_EQUAL(cap_gate_reason(A, H, null, panel_entry), "close the cover first", "blocked while the cover is open")

/// layer = overrides the drawn layer name; CAP_NO_LAYER draws nothing. UI data nests under data["caps"].
/datum/unit_test/dx_cap_library_layers_ui/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/lib_gated/A = allocate(/obj/cap_fixture/lib_gated, T)
	cap_set(A, CAP_COVER_OPEN | CAP_PANEL_OPEN, TRUE)
	refresh_flush()
	TEST_ASSERT(cap_test_has_layer(A, "hatch"), "the panel draws its overridden layer")
	TEST_ASSERT(!cap_test_has_layer(A, "panel_open"), "and not its standard one")
	TEST_ASSERT(!cap_test_has_layer(A, "cover_open"), "CAP_NO_LAYER draws nothing")
	TEST_ASSERT(!cap_test_has_layer(A, CAP_NO_LAYER), "not even a layer named CAP_NO_LAYER")
	var/list/data = list()
	A.caps_ui_data(H, data)
	TEST_ASSERT_NULL(data["locked"], "no top-level capability keys (M11)")
	TEST_ASSERT_NOTNULL(data["caps"], "capability data is nested under caps")
	TEST_ASSERT_EQUAL(data["caps"]["hatch"]?["open"], TRUE, "keyed by the capability's layer")
	TEST_ASSERT_EQUAL(data["caps"]["locked"]?["locked"], FALSE, "the lock's data")
	TEST_ASSERT_EQUAL(data["caps"]["[/datum/capability/cover]"]?["open"], TRUE, "a capability that draws nothing is keyed by its key")

/// A removable cover: removed, it stays open, can't be closed, and cover_removed() says so.
/datum/unit_test/dx_cap_library_cover_removable/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/lib_gated/A = allocate(/obj/cap_fixture/lib_gated, T)
	var/obj/item/tool/crowbar/crowbar = allocate(/obj/item/tool/crowbar, T)
	var/datum/interaction/capability/remove = cap_test_entry(A, "cover:remove")
	var/datum/interaction/capability/toggle = cap_test_entry(A, "cover:[BY_HAND]")
	TEST_ASSERT_NOTNULL(remove, "removable = TRUE adds a removal entry")
	TEST_ASSERT_EQUAL(remove.tool, TOOL_CROWBAR, "pried off with a crowbar")
	TEST_ASSERT_EQUAL(remove.stance, I_HURT, "on harm intent")
	TEST_ASSERT_NULL(cap_test_entry(allocate(/obj/cap_fixture/cover_crowbar, T), "cover:remove"), "not removable by default")
	TEST_ASSERT(!cover_removed(A), "starts in place")
	TEST_ASSERT(dispatch_succeeded(cap_dispatch(new /datum/dispatch_context(H, A, crowbar, remove))), "removing runs")
	TEST_ASSERT(cover_removed(A) && cover_is_open(A), "removed and open")
	TEST_ASSERT_EQUAL(toggle.why_not(H, A, null), "the cover has been removed", "a removed cover can't be closed")
	TEST_ASSERT("Its cover has been removed." in A.caps_examine(H), "examine says so")

/// The emag effect runs first and may refuse: no bit, no use spent. The delay is the entry's timed cost.
/datum/unit_test/dx_cap_library_emag_refusal/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/lib_emag/A = allocate(/obj/cap_fixture/lib_emag, T)
	var/obj/item/card/emag/card = allocate(/obj/item/card/emag, T)
	var/datum/interaction/capability/entry = cap_test_entry(A, "emag")
	TEST_ASSERT_EQUAL(entry.duration, 2 SECONDS, "delay is the entry's timed cost")
	TEST_ASSERT_EQUAL(entry.behind, PANEL, "gating via the constructor")
	TEST_ASSERT_EQUAL(cap_gate_reason(A, H, card, entry), "open the maintenance panel first", "behind the panel")
	var/uses = card.uses
	TEST_ASSERT_EQUAL(cap_dispatch(new /datum/dispatch_context(H, A, card, entry)), UI_REFUSED, "a refusing effect refuses")
	TEST_ASSERT_EQUAL(A.effects, 1, "the effect ran first")
	TEST_ASSERT(!is_emagged(A), "no bit set")
	TEST_ASSERT_EQUAL(card.uses, uses, "no use spent")
	A.allow = TRUE
	TEST_ASSERT(dispatch_succeeded(cap_dispatch(new /datum/dispatch_context(H, A, card, entry))), "an allowing effect runs")
	TEST_ASSERT(is_emagged(A), "the bit is set")
	TEST_ASSERT_EQUAL(card.uses, uses - 1, "one use spent")

/// A slot that draws its item: layer, draws_var, blocked_by; the accessors.
/datum/unit_test/dx_cap_library_slot_layer/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/lib_slot/A = allocate(/obj/cap_fixture/lib_slot, T)
	var/obj/item/cell/cell = allocate(/obj/item/cell, T)
	var/datum/capability/slot/S = A.slot_capability(nameof(A.cell))
	TEST_ASSERT_EQUAL(S.draws_var, nameof(A.cell), "a slot with a layer draws its var")
	var/obj/item/cap_slot_probe/probe = allocate(/obj/item/cap_slot_probe, T)
	var/datum/capability/slot/plain = probe.slot_capability(nameof(probe.cell))
	TEST_ASSERT_NULL(plain.draws_var, "a slot without a layer draws nothing")
	TEST_ASSERT_EQUAL(plain.layer_name, CAP_NO_LAYER, "its layer is CAP_NO_LAYER")
	var/datum/interaction/capability/insert
	for(var/datum/interaction/capability/slot_insert/E in cap_interactions(A))
		insert = E
	TEST_ASSERT(H.put_in_active_hand(cell), "holding a cell")
	cap_set(A, CAP_COVER_OPEN, TRUE)
	TEST_ASSERT_EQUAL(insert.why_not(H, A, cell), "close the cover first", "blocked_by gates the slot")
	cap_set(A, CAP_COVER_OPEN, FALSE)
	TEST_ASSERT(insert.perform(H, A, cell), "inserting runs through cap_dispatch")
	TEST_ASSERT_EQUAL(A.cell, cell, "inserted")
	refresh_flush()
	TEST_ASSERT(cap_test_has_layer(A, "cell"), "the slot layer is drawn while filled")
	TEST_ASSERT(!is_bolted(A) && !is_welded(A), "the accessors read clear bits")
	cap_set(A, CAP_BOLTED | CAP_WELDED, TRUE)
	TEST_ASSERT(is_bolted(A) && is_welded(A), "and set ones")
