// The APC proof conversion (code/modules/power/apc.dm) and the bundles it is built from:
// wall_machine(), maintenance_hatch(), cell_bay(), power_channels(), powered_by().

/// A test APC that stays out of its area's power (the area keeps its real APC) and lets the test
/// decide the window gate (a test mob has no client, which can_use() requires).
/obj/machinery/power/apc/dx_test
	cell_type = /obj/item/cell/apc
	var/ui_ok = TRUE

/obj/machinery/power/apc/dx_test/init()
	has_electronics = APC_HAS_ELECTRONICS_SECURED
	own_set(src, "cell", new cell_type(src))
	cell.charge = cell.maxcharge

/obj/machinery/power/apc/dx_test/ui_allowed(mob/user, action)
	return ui_ok

/// The capability entry of A named `name`, or null.
/proc/dx_apc_entry_named(atom/A, name)
	for(var/datum/interaction/capability/E as anything in cap_interactions(A))
		if(E.name == name)
			return E
	return null

/// The APC's bundles give it the standard capabilities, one per key, in draw order.
/datum/unit_test/dx_apc_capabilities/Run()
	var/obj/machinery/power/apc/dx_test/A = allocate(/obj/machinery/power/apc/dx_test, run_loc_floor_bottom_left)
	TEST_ASSERT_NOTNULL(cap_of(A, /datum/capability/cover), "a cover")
	TEST_ASSERT_NOTNULL(cap_of(A, /datum/capability/panel), "a wire panel")
	TEST_ASSERT_NOTNULL(cap_of(A, /datum/capability/wires), "wires")
	TEST_ASSERT_NOTNULL(cap_of(A, /datum/capability/lock), "an ID lock")
	TEST_ASSERT_NOTNULL(cap_of(A, /datum/capability/slot/cell_bay), "a cell bay")
	TEST_ASSERT_NOTNULL(cap_of(A, /datum/capability/power_channels), "power channels")
	TEST_ASSERT_NOTNULL(cap_of(A, /datum/capability/wall_mount), "a wall mount")
	TEST_ASSERT_EQUAL(wall_board_of(A), /obj/item/module/power_control, "the wall mount names the board")
	TEST_ASSERT(is_locked(A), "the ID lock starts engaged (cap_state default)")
	TEST_ASSERT(A in cap_system_members(/datum/cap_system/power, POWER_ROLE_AREA_SUPPLY), "powered_by() joined the power system as an area supply")
	TEST_ASSERT_EQUAL(cap_system_role(A, /datum/cap_system/power), POWER_ROLE_AREA_SUPPLY, "with its role")
	qdel(A)
	TEST_ASSERT(!(A in cap_system_members(/datum/cap_system/power, POWER_ROLE_AREA_SUPPLY)), "and left it on deletion")

/// The cover can't be pried open while the cover lock holds and the cell has charge.
/datum/unit_test/dx_apc_cover_lock/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/power/apc/dx_test/A = allocate(/obj/machinery/power/apc/dx_test, T)
	var/datum/interaction/capability/cover = cap_test_entry(A, "cover:[TOOL_CROWBAR]")
	TEST_ASSERT_NOTNULL(cover, "a crowbar cover")
	TEST_ASSERT_EQUAL(cap_gate_reason(A, H, null, cover), "the cover is locked and cannot be opened", "locked with a charged cell")
	A.cell.charge = 0
	TEST_ASSERT_NULL(cap_gate_reason(A, H, null, cover), "a flat cell lets it open")
	A.cell.charge = A.cell.maxcharge
	A.coverlocked = FALSE
	TEST_ASSERT_NULL(cap_gate_reason(A, H, null, cover), "the cover lock off lets it open")
	A.stat_add(BROKEN)
	cap_set(A, CAP_BROKEN, TRUE)
	TEST_ASSERT_EQUAL(cap_gate_reason(A, H, null, cover), "it's broken", "a broken closed APC can't be pried open")

/// The wire panel only with the cover closed; the wires only behind the open panel.
/datum/unit_test/dx_apc_panel_and_wires/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/power/apc/dx_test/A = allocate(/obj/machinery/power/apc/dx_test, T)
	var/datum/interaction/capability/panel = cap_test_entry(A, "panel:[TOOL_SCREWDRIVER]")
	var/datum/interaction/capability/pulse = cap_test_entry(A, "wires:multitool")
	var/datum/interaction/capability/secure = dx_apc_entry_named(A, "Secure electronics")
	TEST_ASSERT_NULL(cap_gate_reason(A, H, null, panel), "the panel opens with the cover closed")
	TEST_ASSERT_EQUAL(cap_gate_reason(A, H, null, pulse), "open the maintenance panel first", "wires behind the panel")
	cap_set(A, CAP_PANEL_OPEN, TRUE)
	TEST_ASSERT_NULL(cap_gate_reason(A, H, null, pulse), "wires reachable with the panel open")
	var/datum/wires/W = wires_of(A)
	TEST_ASSERT(istype(W, /datum/wires/apc), "the wires are APC wires")
	TEST_ASSERT(W.interactable(H), "and interactable")
	cap_set(A, CAP_PANEL_OPEN, FALSE)
	cap_set(A, CAP_COVER_OPEN, TRUE)
	TEST_ASSERT_EQUAL(cap_gate_reason(A, H, null, panel), "close the cover first", "no panel with the cover open")
	TEST_ASSERT_NOTNULL(secure, "the electronics step exists")
	TEST_ASSERT_EQUAL(cap_gate_reason(A, H, null, secure), "remove the power cell first", "the screwdriver works the electronics with the cover open")

/// The ID swipe: refused with the cover or the panel open, and by the APC's own rules; toggles otherwise.
/datum/unit_test/dx_apc_id_lock/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/power/apc/dx_test/A = allocate(/obj/machinery/power/apc/dx_test, T)
	var/obj/item/card/id/card = allocate(/obj/item/card/id, T)
	card.access = list(ACCESS_ENGINE_EQUIP)
	var/datum/capability/lock/L = cap_of(A, /datum/capability/lock)
	var/datum/interaction/capability/swipe = cap_built_entries(L, A)[1]
	cap_set(A, CAP_COVER_OPEN, TRUE)
	TEST_ASSERT_EQUAL(cap_gate_reason(A, H, card, swipe), "close the cover first", "no swipe with the cover open")
	cap_set(A, CAP_COVER_OPEN, FALSE)
	cap_set(A, CAP_PANEL_OPEN, TRUE)
	TEST_ASSERT_EQUAL(cap_gate_reason(A, H, card, swipe), "close the maintenance panel first", "no swipe with the panel open")
	cap_set(A, CAP_PANEL_OPEN, FALSE)
	TEST_ASSERT_NULL(cap_gate_reason(A, H, card, swipe), "the swipe is offered with the hatch shut")
	TEST_ASSERT(dispatch_succeeded(A.cap_lock_swipe(H, card)), "an engineering ID unlocks it")
	TEST_ASSERT(!is_locked(A), "unlocked")
	cap_set(A, CAP_EMAGGED, TRUE)
	TEST_ASSERT_EQUAL(A.cap_lock_swipe(H, card), UI_REFUSED, "an emagged panel is unresponsive")
	TEST_ASSERT(!is_locked(A), "still unlocked")
	cap_set(A, CAP_EMAGGED, FALSE)
	card.access = list()
	TEST_ASSERT_EQUAL(A.cap_lock_swipe(H, card), UI_REFUSED, "no access, no lock")

/// The emag: refused with the cover open (gate) or while broken (needs); otherwise it unlocks and sets the bit.
/datum/unit_test/dx_apc_emag/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/power/apc/dx_test/A = allocate(/obj/machinery/power/apc/dx_test, T)
	var/obj/item/card/emag/card = allocate(/obj/item/card/emag, T)
	var/datum/interaction/capability/emag = cap_test_entry(A, "emag")
	TEST_ASSERT_NOTNULL(emag, "an emag entry")
	TEST_ASSERT_EQUAL(emag.duration, 0.6 SECONDS, "with the old wait")
	cap_set(A, CAP_COVER_OPEN, TRUE)
	TEST_ASSERT_EQUAL(cap_gate_reason(A, H, card, emag), "close the cover first", "not with the cover open")
	cap_set(A, CAP_COVER_OPEN, FALSE)
	A.stat_add(MAINT)
	TEST_ASSERT_EQUAL(cap_gate_reason(A, H, card, emag), "it isn't working", "not while unwired")
	A.stat_remove(MAINT)
	TEST_ASSERT_NULL(cap_gate_reason(A, H, card, emag), "offered on a working closed APC")
	TEST_ASSERT(dispatch_succeeded(A.cap_emag_use(H, card)), "the emag works")
	TEST_ASSERT(is_emagged(A), "emagged")
	TEST_ASSERT(!is_locked(A), "and the effect unlocked it")
	A.reboot()
	TEST_ASSERT(!is_emagged(A), "a reboot clears it")

/// cell_bay(): insert and eject through the slot, the MAINT refusal, the charge accessors.
/datum/unit_test/dx_apc_cell_bay/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/power/apc/dx_test/A = allocate(/obj/machinery/power/apc/dx_test, T)
	TEST_ASSERT_EQUAL(cell_charge_percent(A), 100, "a full cell reads 100%")
	TEST_ASSERT(A.cap_cell_charged(H, null) == TRUE, "charged")
	cap_set(A, CAP_COVER_OPEN, TRUE)
	var/obj/item/cell/C = A.slot_eject(nameof(A.cell), H)
	TEST_ASSERT_EQUAL(C?.type, /obj/item/cell/apc, "the cell comes out")
	TEST_ASSERT_NULL(A.cell, "the slot is empty")
	TEST_ASSERT_EQUAL(cell_charge_percent(A), 0, "no cell reads 0, not null")
	TEST_ASSERT(istext(A.cap_cell_charged(H, null)), "and refuses as low")
	TEST_ASSERT("The power cell is missing." in A.caps_examine(H), "examine says it's missing")
	A.stat_add(MAINT)
	TEST_ASSERT(!A.slot_insert(nameof(A.cell), C, H), "no cell before the electronics")
	A.stat_remove(MAINT)
	TEST_ASSERT(A.slot_insert(nameof(A.cell), C, H), "the cell goes back in")
	TEST_ASSERT_EQUAL(A.cell, C, "held by the slot var")
	refresh_flush()
	TEST_ASSERT(cap_test_has_layer(A, "cell"), "the cell shows through the open cover")
	TEST_ASSERT(cap_test_has_layer(A, "cover_open"), "under the open cover layer")

/// power_channels() owns channel / breaker / nightshift: tgui_act reaches its act_ procs, validated and logged.
/datum/unit_test/dx_apc_power_channel_actions/Run()
	var/obj/machinery/power/apc/dx_test/A = allocate(/obj/machinery/power/apc/dx_test, run_loc_floor_bottom_left)
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
	var/obj/machinery/power/apc/dx_test/A = allocate(/obj/machinery/power/apc/dx_test, run_loc_floor_bottom_left)
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

/// draw(): the library layers, the bluescreen, the glows and the light.
/datum/unit_test/dx_apc_draw/Run()
	var/obj/machinery/power/apc/dx_test/A = allocate(/obj/machinery/power/apc/dx_test, run_loc_floor_bottom_left)
	var/datum/look/L = GLOB.look_builder
	L.reset()
	A.draw(L)
	TEST_ASSERT("locked" in L.glows, "all good: the lock glow")
	TEST_ASSERT("apco3-[A.charging]" in L.glows, "the charge glow")
	TEST_ASSERT(A.operating ? ("apco0-[A.equipment]" in L.glows) : TRUE, "power_channels() draws the channel glows while operating")
	TEST_ASSERT_NOTNULL(L.light_spec, "the screen lights")
	L.reset()
	A.energy_fail(10)
	A.draw(L)
	TEST_ASSERT("emagged" in L.overlays, "a failed APC shows the bluescreen")
	TEST_ASSERT_EQUAL(L.light_spec?[3], "#0000FF", "in blue")
	TEST_ASSERT(!("locked" in L.glows), "no glows on the bluescreen")
	A.act_reboot(null)
	cap_set(A, CAP_PANEL_OPEN, TRUE)
	L.reset()
	A.draw(L)
	TEST_ASSERT("panel_open" in L.overlays, "the open wire panel")
	TEST_ASSERT_NULL(L.light_spec, "the light is off")
	cap_set(A, CAP_PANEL_OPEN, FALSE)
	cap_set(A, CAP_BROKEN, TRUE)
	L.reset()
	A.draw(L)
	TEST_ASSERT("broken" in L.overlays, "broken")
	cap_set(A, CAP_COVER_OPEN | CAP_COVER_REMOVED, TRUE)
	L.reset()
	A.draw(L)
	TEST_ASSERT_EQUAL(L.icon_state, "apc2-nocover", "the cover knocked off shows the coverless frame with its cell")
	TEST_ASSERT(!("cover_open" in L.overlays), "no open cover over it")
	L.reset()
