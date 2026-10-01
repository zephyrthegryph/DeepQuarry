// The APC on the foundation (code/modules/power/apc.dm) and the bundles it is built from:
// wall_machine(), maintenance_hatch(), cell_bay(), power_channels(), powered_by(), the ladder, the lock and
// emag ops, and the notices it hears.

/// A test APC that stays out of its area's power (the area keeps its real APC) and lets the test
/// decide the window gate (a test mob has no client, which can_use() requires).
/obj/machinery/power/apc/dx_test
	cell_type = null
	var/ui_ok = TRUE

/obj/machinery/power/apc/dx_test/init()
	ladder_set_stage(src, "secured")

/obj/machinery/power/apc/dx_test/ui_allowed(mob/user, action)
	return ui_ok

/// The test floor is a floor tile, not plating: the cable steps don't ask for it off.
/obj/machinery/power/apc/dx_test/floor_exposed(mob/user, obj/item/held)
	return TRUE

/// A test APC with a full cell, both allocated (so the test block takes both back).
/datum/unit_test/proc/dx_apc_make(turf/T)
	var/obj/machinery/power/apc/dx_test/A = allocate(/obj/machinery/power/apc/dx_test, T)
	var/obj/item/cell/apc/C = allocate(/obj/item/cell/apc, A)
	C.charge = C.maxcharge
	own_set(A, nameof(A.cell), C)
	return A

/// The op entry of `A` whose op has `key`, or null.
/proc/dx_apc_op(atom/A, key)
	RETURN_TYPE(/datum/interaction/capability)
	for(var/datum/interaction/capability/E as anything in cap_interactions(A))
		if(E.op?.key == key)
			return E
	return null

/// Why entry `E` (an op) is refused for `user` with `held` on `A` now: the op context's ordered stages.
/proc/dx_apc_why(atom/A, mob/user, obj/item/held, datum/interaction/capability/E)
	return op_entry_reason(E, user, A, held, null)

/// Whether the look `L` holds part `name` (with value `value`), and whether that part glows.
/proc/dx_apc_part(datum/look/L, name, value)
	for(var/list/entry in L.parts)
		if(entry[1] == name && (isnull(value) || entry[2] == "[value]"))
			return entry[3] ? "glow" : "part"
	return null

/// The APC's bundles give it the standard capabilities, one per key, in draw order.
/datum/unit_test/dx_apc_capabilities/Run()
	var/obj/machinery/power/apc/dx_test/A = dx_apc_make(run_loc_floor_bottom_left)
	TEST_ASSERT_NOTNULL(cap_of(A, /datum/capability/cover), "a cover")
	TEST_ASSERT_NOTNULL(cap_of(A, /datum/capability/panel), "a wire panel")
	TEST_ASSERT_NOTNULL(cap_of(A, /datum/capability/wires), "wires")
	TEST_ASSERT_NOTNULL(cap_of(A, /datum/capability/lock), "an ID lock")
	TEST_ASSERT_NOTNULL(cap_of(A, /datum/capability/slot/cell_bay), "a cell bay")
	TEST_ASSERT_NOTNULL(cap_of(A, /datum/capability/power_channels), "power channels")
	TEST_ASSERT_NOTNULL(cap_of(A, /datum/capability/wall_mount), "a wall mount")
	TEST_ASSERT_NOTNULL(cap_of(A, /datum/capability/construction), "a construction ladder")
	TEST_ASSERT_NOTNULL(compartment_of(A, BAY_HATCH), "the hatch's compartment")
	TEST_ASSERT_NULL(cap_of(A, /datum/capability/deconstruct), "no machine-frame dismantling")
	TEST_ASSERT_NULL(cap_of(A, /datum/capability/powered), "no dark layer")
	TEST_ASSERT_EQUAL(A.machine_wires, /datum/wires/apc, "the wiring is a type var")
	TEST_ASSERT_EQUAL(A.machine_board, /obj/item/module/power_control, "so is the board")
	for(var/key in list(CAP_LOCK, CAP_EMAG, "open_interface", "replace_cover", "reset_apc"))
		TEST_ASSERT_NOTNULL(dx_apc_op(A, key), "the op [key] is declared")
	TEST_ASSERT_EQUAL(dx_apc_op(A, CAP_LOCK).op.action, ACT_LOCK, "the lock op answers ACT_LOCK (an alt-click), with no alt entry point")
	TEST_ASSERT_EQUAL(dx_apc_op(A, CAP_EMAG).duration, 0.6 SECONDS, "the emag op is refined to its old wait")
	TEST_ASSERT(is_locked(A), "the ID lock starts engaged (cap_state default)")
	var/datum/system/power/power_system = system(/datum/system/power)
	TEST_ASSERT(A in power_system.members_with_role(POWER_ROLE_AREA_SUPPLY), "powered_by() joined the power system as an area supply")
	TEST_ASSERT_EQUAL(member_role(/datum/system/power, A), POWER_ROLE_AREA_SUPPLY, "with its role")
	qdel(A)
	TEST_ASSERT(!(A in power_system.members_with_role(POWER_ROLE_AREA_SUPPLY)), "and left it on deletion")

/// What the APC declares in reactions() is only what it hears; its relations are its links.
/datum/unit_test/dx_apc_relations_and_reactions/Run()
	var/obj/machinery/power/apc/dx_test/A = dx_apc_make(run_loc_floor_bottom_left)
	var/datum/rx_table/T = rx_table_of(A)
	TEST_ASSERT_NOTNULL(T, "the APC has a reaction table")
	TEST_ASSERT_EQUAL(length(T.notices), 2, "it hears a hit and a slash")
	TEST_ASSERT(!length(T.everys) && !length(T.crosses) && !length(T.before_keyed), "and declares nothing else itself")
	TEST_ASSERT(T.after_keyed ~= list(CAP_EMAG = T.after_keyed[CAP_EMAG]), "the one after_op is the emag capability's, not the APC's")
	TEST_ASSERT(WANTS(A, /datum/notice/hit) && WANTS(A, /datum/notice/slashed), "both are wanted")
	TEST_ASSERT(!WANTS(A, /datum/notice/rx_fx), "and nothing else")
	var/obj/machinery/power/terminal/term = allocate(/obj/machinery/power/terminal, run_loc_floor_bottom_left)
	rel_set(A, nameof(A.terminal), term)
	TEST_ASSERT_EQUAL(term.master, A, "the terminal is paired: its master is the APC")
	rel_clear(A, nameof(A.terminal))
	TEST_ASSERT_NULL(term.master, "and both ends clear together")

/// The cover can't be pried open while the cover lock holds and the cell has charge.
/datum/unit_test/dx_apc_cover_lock/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/power/apc/dx_test/A = dx_apc_make(T)
	var/datum/interaction/capability/cover = cap_test_entry(A, "cover:[TOOL_CROWBAR]")
	TEST_ASSERT_NOTNULL(cover, "a crowbar cover")
	TEST_ASSERT_EQUAL(dx_apc_why(A, H, null, cover), "the cover is locked and cannot be opened", "locked with a charged cell")
	A.cell.charge = 0
	TEST_ASSERT_NULL(dx_apc_why(A, H, null, cover), "a flat cell lets it open")
	A.cell.charge = A.cell.maxcharge
	A.coverlocked = FALSE
	TEST_ASSERT_NULL(dx_apc_why(A, H, null, cover), "the cover lock off lets it open")
	A.stat_add(BROKEN)
	cap_set(A, CAP_BROKEN, TRUE)
	TEST_ASSERT(dx_apc_why(A, H, null, cover), "a broken closed APC can't be pried open")
	cap_set(A, CAP_BROKEN, FALSE)
	A.stat_remove(BROKEN)
	cap_set(A, CAP_COVER_OPEN, TRUE)
	TEST_ASSERT_NULL(dx_apc_why(A, H, null, cover), "the cover closes over a finished APC")
	ladder_set_stage(A, "board")
	TEST_ASSERT_EQUAL(dx_apc_why(A, H, null, cover), "take the power control board out first", "the cover can't close on an unsecured board")

/// The wire panel only with the cover closed; the wires only behind the open panel.
/datum/unit_test/dx_apc_panel_and_wires/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/power/apc/dx_test/A = dx_apc_make(T)
	var/datum/interaction/capability/panel = cap_test_entry(A, "panel:[TOOL_SCREWDRIVER]")
	var/datum/interaction/capability/pulse = cap_test_entry(A, "wires:multitool")
	TEST_ASSERT_NULL(dx_apc_why(A, H, null, panel), "the panel opens with the cover closed")
	TEST_ASSERT_EQUAL(dx_apc_why(A, H, null, pulse), "open the maintenance panel first", "wires behind the panel")
	cap_set(A, CAP_PANEL_OPEN, TRUE)
	TEST_ASSERT_NULL(dx_apc_why(A, H, null, pulse), "wires reachable with the panel open")
	var/datum/wires/W = wires_of(A)
	TEST_ASSERT(istype(W, /datum/wires/apc), "the wires are APC wires")
	TEST_ASSERT(W.interactable(H), "and interactable")
	cap_set(A, CAP_PANEL_OPEN, FALSE)
	cap_set(A, CAP_COVER_OPEN, TRUE)
	TEST_ASSERT_EQUAL(dx_apc_why(A, H, null, panel), "close the cover first", "no panel with the cover open")

/// The ID swipe: refused with the cover or the panel open and by the APC's own contracts; toggles otherwise.
/datum/unit_test/dx_apc_id_lock/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/power/apc/dx_test/A = dx_apc_make(T)
	var/obj/item/card/id/card = allocate(/obj/item/card/id, T)
	card.access = list(ACCESS_ENGINE_EQUIP)
	var/datum/interaction/capability/swipe = dx_apc_op(A, CAP_LOCK) // the one lock op: a held card, or the actor's own access
	var/datum/interaction/capability/toggle = swipe
	cap_set(A, CAP_COVER_OPEN, TRUE)
	TEST_ASSERT_EQUAL(dx_apc_why(A, H, card, swipe), "close the cover first", "no swipe with the cover open")
	cap_set(A, CAP_COVER_OPEN, FALSE)
	cap_set(A, CAP_PANEL_OPEN, TRUE)
	TEST_ASSERT_EQUAL(dx_apc_why(A, H, card, swipe), "close the maintenance panel first", "no swipe with the panel open")
	cap_set(A, CAP_PANEL_OPEN, FALSE)
	TEST_ASSERT_NULL(dx_apc_why(A, H, card, swipe), "the swipe is offered with the hatch shut")
	TEST_ASSERT_NULL(dx_apc_why(A, H, null, toggle), "and so is the toggle by the actor's own access")
	TEST_ASSERT(dispatch_succeeded(cap_lock_toggle(A, H, card)), "an engineering ID unlocks it")
	TEST_ASSERT(!is_locked(A), "unlocked")
	cap_set(A, CAP_EMAGGED, TRUE)
	TEST_ASSERT(dx_apc_why(A, H, card, swipe), "an emagged panel is unresponsive")
	cap_set(A, CAP_EMAGGED, FALSE)
	// ALLOW(ownership): test fixture setup writes the framework var directly to build the state under test
	A.hacker = H // any datum will do for "someone else has it"
	TEST_ASSERT_EQUAL(dx_apc_why(A, H, card, swipe), "it doesn't respond", "an AI that took it over locks the crew out")
	// ALLOW(ownership): test fixture setup writes the framework var directly to build the state under test
	A.hacker = null
	wires_of(A).cut(WIRE_IDSCAN)
	TEST_ASSERT(dx_apc_why(A, H, card, swipe), "a cut ID scan wire refuses the swipe")
	wires_of(A).cut(WIRE_IDSCAN) // cut() toggles
	A.stat_add(MAINT)
	TEST_ASSERT_EQUAL(dx_apc_why(A, H, card, swipe), "it isn't working", "nothing while unwired")
	A.stat_remove(MAINT)
	card.access = list()
	TEST_ASSERT_EQUAL(cap_lock_toggle(A, H, card), UI_REFUSED, "no access, no lock")

/// The emag op: a contract in front of it, an effect refined in, and the shared commit after it.
/datum/unit_test/dx_apc_emag/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/power/apc/dx_test/A = dx_apc_make(T)
	var/obj/item/card/emag/card = allocate(/obj/item/card/emag, T)
	var/datum/interaction/capability/emag = dx_apc_op(A, CAP_EMAG)
	TEST_ASSERT_NOTNULL(emag, "an emag op")
	cap_set(A, CAP_COVER_OPEN, TRUE)
	TEST_ASSERT_EQUAL(dx_apc_why(A, H, card, emag), "close the cover first", "not with the cover open")
	cap_set(A, CAP_COVER_OPEN, FALSE)
	A.stat_add(MAINT)
	TEST_ASSERT_EQUAL(dx_apc_why(A, H, card, emag), "it isn't working", "not while unwired")
	A.stat_remove(MAINT)
	TEST_ASSERT_NULL(dx_apc_why(A, H, card, emag), "offered on a working closed APC")
	var/datum/rx_table/table = rx_table_of(A)
	TEST_ASSERT_EQUAL(length(table.after_keyed[CAP_EMAG]), 1, "the emag capability's after_op reaction is in the table")
	TEST_ASSERT(A.on_emag(H, card), "the refined effect ran")
	TEST_ASSERT(!is_locked(A), "and unlocked it")
	var/datum/op_ctx/ctx = op_ctx_take(H, A, card, emag.op)
	var/uses = card.uses
	A.emag_committed(ctx)
	ctx.release()
	TEST_ASSERT(is_emagged(A), "the commit sets the bit")
	TEST_ASSERT_EQUAL(card.uses, uses - 1, "and spends one use")
	TEST_ASSERT(istext(emag_op_ok(H, A, card)), "a second swipe is refused")
	A.reboot()
	TEST_ASSERT(!is_emagged(A), "a reboot clears it")

/// cell_bay(): insert and eject through the slot, the MAINT refusal, the size rule, the charge accessors.
/datum/unit_test/dx_apc_cell_bay/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/power/apc/dx_test/A = dx_apc_make(T)
	TEST_ASSERT_EQUAL(cell_charge_percent(A), 100, "a full cell reads 100%")
	TEST_ASSERT(cap_cell_charged(A, H, null) == TRUE, "charged")
	cap_set(A, CAP_COVER_OPEN, TRUE)
	var/obj/item/cell/C = slot_eject(A, nameof(A.cell), H)
	TEST_ASSERT_EQUAL(C?.type, /obj/item/cell/apc, "the cell comes out")
	TEST_ASSERT_NULL(A.cell, "the slot is empty")
	TEST_ASSERT_EQUAL(cell_charge_percent(A), 0, "no cell reads 0, not null")
	TEST_ASSERT(istext(cap_cell_charged(A, H, null)), "and refuses as low")
	TEST_ASSERT("The power cell is missing." in caps_examine(A, H), "examine says it's missing")
	var/datum/interaction/capability/insert
	for(var/datum/interaction/capability/slot_insert/E in cap_interactions(A))
		insert = E
	TEST_ASSERT_NOTNULL(insert, "an insert entry")
	A.stat_add(MAINT)
	TEST_ASSERT_EQUAL(cap_gate_reason(A, H, C, insert), "You need to install the wiring and electronics first.", "no cell before the electronics")
	A.stat_remove(MAINT)
	TEST_ASSERT_NULL(cap_gate_reason(A, H, C, insert), "a cell goes in once the electronics are in")
	var/obj/item/cell/small = allocate(/obj/item/cell/device, T)
	TEST_ASSERT_EQUAL(slot_insert(A, nameof(A.cell), small, H), FALSE, "a small cell doesn't fit")
	TEST_ASSERT(slot_insert(A, nameof(A.cell), C, H), "the cell goes back in")
	TEST_ASSERT_EQUAL(A.cell, C, "held by the slot var")
	refresh_flush()
	TEST_ASSERT(cap_test_has_layer(A, "cell"), "the cell shows through the open cover")
	TEST_ASSERT(cap_test_has_layer(A, "cover-open"), "under the open cover layer")

/// The ladder builds the frame in order (board, ten cable, fastener) and takes it apart again, and the
/// hooks keep MAINT, the terminal and the cover in step.
/datum/unit_test/dx_apc_ladder/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/power/apc/dx_test/A = dx_apc_make(T)
	var/obj/item/module/power_control/board = allocate(/obj/item/module/power_control, A) // the board this APC was "built" with
	var/datum/construction_ladder/ladder = ladder_of(A)
	var/list/problems = ladder.validate()
	TEST_ASSERT(!length(problems), "the APC's ladder is valid: [jointext(problems, "; ")]")
	TEST_ASSERT(ladder.states ~= list("frame", "board", "wired", "secured"), "a frame, a board, cable, a fastener: [json_encode(ladder.states)]")
	TEST_ASSERT_EQUAL(ladder.at, BAY_HATCH, "worked at the hatch")
	TEST_ASSERT_EQUAL(ladder.undo_delay, 5 SECONDS, "every undo is slow")
	TEST_ASSERT(!A.cell_out(H, null), "the cell must be out to unfasten")
	cap_set(A, CAP_COVER_OPEN, TRUE)
	var/obj/item/cell/C = slot_eject(A, nameof(A.cell), H, drop = TRUE)
	TEST_ASSERT(A.cell_out(H, null), "and it is out")
	var/obj/item/tool/screwdriver/driver = dq_fast_tool(/obj/item/tool/screwdriver, T)
	TEST_ASSERT(ladder_walk(H, A, ladder_step(A, "secured", "wired"), driver), "unfastening runs")
	TEST_ASSERT(A.has_stat(MAINT), "an unsecured APC is under maintenance")
	var/obj/item/tool/wirecutters/cutters = dq_fast_tool(/obj/item/tool/wirecutters, T)
	TEST_ASSERT(ladder_walk(H, A, ladder_step(A, "wired", "board"), cutters), "cutting the cable out runs")
	TEST_ASSERT_NULL(A.terminal, "the terminal went with the cable")
	var/obj/item/stack/cable_coil/refund = locate() in T.contents
	TEST_ASSERT_NOTNULL(refund, "the ladder gave the cable back")
	TEST_ASSERT_EQUAL(refund?.get_amount(), 10, "all ten lengths")
	qdel(refund)
	TEST_ASSERT(A.board_unfastened(), "the board is in and not fastened")
	TEST_ASSERT(ladder_walk(H, A, ladder_step(A, "board", "frame"), null), "the board comes out by hand")
	TEST_ASSERT_EQUAL(ladder.state_of(A), "frame", "back on the bare frame")
	TEST_ASSERT(board.loc == T, "the same board dropped out")
	TEST_ASSERT_EQUAL(A.frame_ruined(), FALSE, "a whole frame")
	TEST_ASSERT(ladder_walk(H, A, ladder_step(A, "frame", "board"), board), "the board goes in")
	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T, 10)
	TEST_ASSERT(ladder_walk(H, A, ladder_step(A, "board", "wired"), coil), "ten lengths of cable go in")
	TEST_ASSERT_NOTNULL(A.terminal, "the terminal is made")
	TEST_ASSERT_EQUAL(A.terminal.master, A, "paired with the APC")
	TEST_ASSERT(ladder_walk(H, A, ladder_step(A, "wired", "secured"), driver), "the fastener secures it")
	TEST_ASSERT(!A.has_stat(MAINT), "a secured APC works")
	slot_insert(A, nameof(A.cell), C, H)
	TEST_ASSERT(!A.cell_out(H, null), "and the cell is back in")

/// A thing that hit or slashed the APC is heard through its notices.
/datum/unit_test/dx_apc_hits/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/power/apc/dx_test/A = dx_apc_make(T)
	var/obj/item/tool/crowbar/bat = allocate(/obj/item/tool/crowbar, T)
	bat.force = 10
	bat.w_class = ITEMSIZE_NORMAL
	A.stat_add(BROKEN)
	cap_set(A, CAP_BROKEN, TRUE)
	PUBLISH(A, /datum/notice/hit, H, bat)
	TEST_ASSERT(A.stat & BROKEN, "a hit is heard and changes nothing on a whole-ish APC")
	var/knocked = FALSE
	for(var/i in 1 to 200)
		cap_set(A, CAP_COVER_OPEN | CAP_COVER_REMOVED, FALSE)
		PUBLISH(A, /datum/notice/hit, H, bat)
		if(cover_removed(A))
			knocked = TRUE
			break
	TEST_ASSERT(knocked, "a broken APC hit hard enough loses its cover")
	var/datum/interaction/capability/claws = dx_apc_op(A, CAP_CLAW)
	TEST_ASSERT_NOTNULL(claws, "a breakable machine has the claw op")
	TEST_ASSERT(!claws.is_meant(H, A, null), "a hand that can't shred isn't offered it")
	var/before = A.beenhit
	A.on_slashed(take_notice(/datum/notice/slashed, H))
	TEST_ASSERT_EQUAL(A.beenhit, before + 1, "a slash that lands counts toward springing the cover")

/// power_channels() owns channel / breaker / nightshift: tgui_act reaches its act_ procs, validated and logged.
/datum/unit_test/dx_apc_power_channel_actions/Run()
	var/obj/machinery/power/apc/dx_test/A = dx_apc_make(run_loc_floor_bottom_left)
	var/datum/tgui/ui = ui_test_window(A)
	var/records = length(GLOB.dispatch_records)
	TEST_ASSERT(A.tgui_act("channel", list("channel" = POWER_CHANNEL_LIGHTING, "mode" = POWERCHAN_OFF_AUTO), ui), "act_channel ran")
	TEST_ASSERT_EQUAL(A.lighting, POWERCHAN_OFF, "the lighting channel is off")
	TEST_ASSERT_EQUAL(GLOB.dispatch_records[length(GLOB.dispatch_records)], "channel|0|1", "logged (LOG_GAME)")
	TEST_ASSERT(!A.tgui_act("channel", list("channel" = "x", "mode" = 3), ui), "a bad channel is refused")
	TEST_ASSERT(A.tgui_act("channel", list("channel" = POWER_CHANNEL_LIGHTING, "mode" = POWERCHAN_ON_AUTO), ui), "and back on auto")
	TEST_ASSERT_EQUAL(A.lighting, POWERCHAN_ON_AUTO, "on auto")
	var/was = A.operating
	TEST_ASSERT(A.tgui_act("breaker", list(), ui), "act_breaker ran")
	TEST_ASSERT_EQUAL(A.operating, !was, "the breaker flipped")
	TEST_ASSERT(A.tgui_act("nightshift", list("nightshift" = NIGHTSHIFT_NEVER), ui), "act_nightshift ran")
	TEST_ASSERT_EQUAL(A.nightshift_setting, NIGHTSHIFT_NEVER, "night shift set")
	TEST_ASSERT(!A.tgui_act("nightshift", list("nightshift" = NIGHTSHIFT_ALWAYS), ui), "the breaker is still cycling")
	TEST_ASSERT_EQUAL(A.nightshift_setting, NIGHTSHIFT_NEVER, "unchanged during the cooldown")
	TEST_ASSERT(length(GLOB.dispatch_records) - records >= 4, "each successful action recorded")
	var/list/data = A.tgui_data(null, ui, null)
	TEST_ASSERT_NOTNULL(data["caps"]?["power"]?["powerChannels"], "the channels are the capability's data")
	TEST_ASSERT_EQUAL(length(data["caps"]["power"]["powerChannels"]), 3, "three channels")
	TEST_ASSERT(data["caps"]?["cell"]?["charge"] > 0, "cell_bay reports the charge")
	A.ui_ok = FALSE
	TEST_ASSERT(!A.tgui_act("breaker", list(), ui), "the APC's ui_allowed gates capability actions too")
	A.ui_ok = TRUE
	TEST_ASSERT(A.tgui_act("cover", list(), ui), "the APC's own act_cover")
	TEST_ASSERT(!A.coverlocked, "cover lock off")
	qdel(ui)

/// A power failure is a timed_set(): on for its time, then back off by itself; a reboot ends it.
/datum/unit_test/dx_apc_power_failure/Run()
	var/obj/machinery/power/apc/dx_test/A = dx_apc_make(run_loc_floor_bottom_left)
	A.energy_fail(10)
	TEST_ASSERT(A.power_failed, "failed")
	TEST_ASSERT(time_left(A, nameof(A.power_failed)) > 0, "for a while")
	var/list/pending = A.timed_until[nameof(A.power_failed)]
	TEST_ASSERT_NOTNULL(pending, "a revert is pending")
	A.energy_fail(1)
	TEST_ASSERT(A.timed_until[nameof(A.power_failed)] ~= pending, "a shorter failure keeps the longer one")
	timed_expire(A, nameof(A.power_failed), pending[1])
	TEST_ASSERT(!A.power_failed, "the failure reverts by itself")
	A.energy_fail(10)
	var/datum/tgui/ui = ui_test_window(A)
	TEST_ASSERT(A.tgui_act("reboot", list(), ui), "act_reboot ran")
	TEST_ASSERT(!A.power_failed, "a reboot ends it")
	TEST_ASSERT_EQUAL(time_left(A, nameof(A.power_failed)), 0, "and cancels the revert")
	qdel(ui)

/// draw(): the library parts, the bluescreen, the explicit glows and the light.
/datum/unit_test/dx_apc_draw/Run()
	var/obj/machinery/power/apc/dx_test/A = dx_apc_make(run_loc_floor_bottom_left)
	var/datum/look/L = GLOB.look_builder
	L.reset()
	A.draw(L)
	TEST_ASSERT_EQUAL(dx_apc_part(L, "locked"), "glow", "all good: the lock glows")
	TEST_ASSERT_EQUAL(dx_apc_part(L, "charge", A.charging), "glow", "the charge indicator glows")
	TEST_ASSERT(A.operating ? (dx_apc_part(L, "channel-0", A.equipment) == "glow") : TRUE, "power_channels() draws the channel glows while operating")
	TEST_ASSERT_NOTNULL(L.light_spec, "the screen lights")
	L.reset()
	A.energy_fail(10)
	A.draw(L)
	TEST_ASSERT_EQUAL(dx_apc_part(L, "emagged"), "part", "a failed APC shows the bluescreen")
	TEST_ASSERT_EQUAL(L.light_spec?[3], "#0000FF", "in blue")
	TEST_ASSERT_NULL(dx_apc_part(L, "locked"), "no glows on the bluescreen")
	A.act_reboot(null)
	cap_set(A, CAP_PANEL_OPEN, TRUE)
	L.reset()
	A.draw(L)
	TEST_ASSERT_NOTNULL(dx_apc_part(L, "panel-open"), "the open wire panel")
	TEST_ASSERT_NULL(L.light_spec, "the light is off")
	cap_set(A, CAP_PANEL_OPEN, FALSE)
	cap_set(A, CAP_BROKEN, TRUE)
	L.reset()
	A.draw(L)
	TEST_ASSERT_NOTNULL(dx_apc_part(L, "broken"), "broken")
	cap_set(A, CAP_COVER_OPEN | CAP_COVER_REMOVED, TRUE)
	L.reset()
	A.draw(L)
	TEST_ASSERT(("cover-removed" in L.variants) && ("cell" in L.variants), "the cover knocked off shows the coverless frame with its cell")
	TEST_ASSERT_NULL(dx_apc_part(L, "cover-open"), "no open cover over it")
	L.reset()

/// The area's lights and consoles are MEMBER relations of the area: the APC reads them through the store.
/datum/unit_test/dx_apc_area_members/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/area/A = get_area(T)
	var/obj/machinery/light/L = allocate(/obj/machinery/light, T)
	TEST_ASSERT(L in area_members(A, POWER_ROLE_LIGHTING), "a light is a member of its area with the lighting role")
	TEST_ASSERT(is_member(A, L), "as a relation")
	var/obj/machinery/power/apc/dx_test/APC = dx_apc_make(T)
	APC.area = A
	TEST_ASSERT(L in APC.area_lights(), "the APC reads its lights through the relation")
	qdel(L)
	TEST_ASSERT(!(L in area_members(A, POWER_ROLE_LIGHTING)), "a deleted light leaves it")
	// A console joins through its capability like the light, and declaring that wakes nothing at init.
	var/obj/machinery/computer/C = allocate(/obj/machinery/computer, T)
	TEST_ASSERT(C in area_members(A, POWER_ROLE_COMPUTER), "a console is a member of its area with the computer role")
	TEST_ASSERT(test_machine_idle(C), "declaring the membership did not wake the console at init")
	qdel(C)
	TEST_ASSERT(!(C in area_members(A, POWER_ROLE_COMPUTER)), "a deleted console leaves it")

/// The cover can't close while the board is in and the ladder is short of "secured": on the board and on the cable
/// alike. On a bare frame or a secured APC it closes.
/datum/unit_test/dx_apc_cover_board_unfastened/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/power/apc/dx_test/A = dx_apc_make(T)
	var/datum/interaction/capability/cover = cap_test_entry(A, "cover:[TOOL_CROWBAR]")
	cap_set(A, CAP_COVER_OPEN, TRUE)
	var/list/expect = list("frame" = FALSE, "board" = TRUE, "wired" = TRUE, "secured" = FALSE)
	for(var/stage in expect)
		ladder_set_stage(A, stage)
		TEST_ASSERT_EQUAL(!!A.board_unfastened(), expect[stage], "board_unfastened() on [stage]")
		var/why = dx_apc_why(A, H, null, cover)
		if(expect[stage])
			TEST_ASSERT_EQUAL(why, "take the power control board out first", "the cover refuses to close on [stage]")
		else
			TEST_ASSERT_NULL(why, "the cover closes on [stage]")

/// Night shift and emergency lighting: the APC writes only its tracked state; the area's lights read it through
/// their area and redraw themselves.
/datum/unit_test/dx_apc_lights_read_area/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/area/Ar = get_area(T)
	var/obj/machinery/power/apc/was_apc = Ar.apc
	var/obj/machinery/power/apc/dx_test/APC = dx_apc_make(T)
	rel_set(Ar, nameof(Ar.apc), APC) // the test APC serves the area for the test
	var/obj/machinery/light/L = allocate(/obj/machinery/light, T)
	TEST_ASSERT_EQUAL(L.power_area, Ar, "a light relates to its area")
	var/was_setting = APC.nightshift_setting
	var/was_lights = APC.nightshift_lights
	APC.set_nightshift_setting(NIGHTSHIFT_AUTO)
	APC.set_nightshift(TRUE)
	refresh_flush()
	rx_drain()
	TEST_ASSERT(Ar.lights_nightshift, "its area derives night lighting through its apc relation")
	TEST_ASSERT(L.nightshift_enabled, "the light derives it through its area")
	if(L.on)
		TEST_ASSERT_EQUAL(L.light_range, L.brightness_range_ns, "and redrew itself at night brightness")
	APC.set_nightshift_setting(NIGHTSHIFT_NEVER)
	refresh_flush()
	rx_drain()
	TEST_ASSERT(!L.nightshift_enabled, "the UI setting overrides the night shift")
	var/was_emergency = APC.emergency_lights
	APC.set_emergency_lights(TRUE)
	refresh_flush()
	rx_drain()
	TEST_ASSERT(L.area_emergency_off, "emergency lighting off reaches the light")
	TEST_ASSERT(!L.has_emergency_power(0), "and it has no emergency power")
	APC.set_emergency_lights(was_emergency)
	APC.set_nightshift_setting(was_setting)
	APC.set_nightshift_lights(was_lights)
	rel_set(Ar, nameof(Ar.apc), was_apc)
	refresh_flush()
	rx_drain()
	TEST_ASSERT(!L.nightshift_enabled && !L.area_emergency_off, "the light follows the area back")

/// A silicon's touch travels the interface route: the open cover blocks only a hand. The requirement text is
/// the shared one.
/datum/unit_test/dx_apc_interface_routes/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/power/apc/dx_test/A = dx_apc_make(T)
	var/datum/interaction/capability/iface = dx_apc_op(A, "open_interface")
	TEST_ASSERT(iface.is_meant(H, A, null), "a hand means the interface with the cover shut")
	cap_set(A, CAP_COVER_OPEN, TRUE)
	TEST_ASSERT(!iface.is_meant(H, A, null), "the open cover is in a hand's way (the cell behind it is what it reaches)")
	var/saved = GLOB.op_route_now
	GLOB.op_route_now = ROUTE_INTERFACE
	TEST_ASSERT(iface.is_meant(H, A, null), "but not in the interface's")
	GLOB.op_route_now = saved
	cap_set(A, CAP_COVER_OPEN, FALSE)
	A.stat_add(MAINT)
	TEST_ASSERT_EQUAL(dx_apc_why(A, H, null, iface), req_reason_phrase(/datum/msg/req_not_working), "an unsecured APC isn't working")
	A.stat_remove(MAINT)
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	TEST_ASSERT_EQUAL(R.op_route(null), ROUTE_INTERFACE, "a silicon's empty-handed click is the interface route")
	TEST_ASSERT_EQUAL(H.op_route(null), ROUTE_PHYSICAL, "a human's is physical")
