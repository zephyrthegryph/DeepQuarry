// The vending machine proof conversion (code/modules/economy/vending.dm): capabilities(), draw(),
// tgui_data() and act_<action> procs, with no interaction datums.

/obj/machinery/vending/dx_test
	name = "dx test vendor"
	icon_state = "generic"
	products = list(/obj/item/pen = 3)
	premium = list(/obj/item/paper = 1)
	vend_delay = 1 HOURS // the delayed vend never fires inside a test; finish_vend() is called by hand
	shut_up = TRUE

/// No coin slot.
/obj/machinery/vending/dx_test/plain
	premium = null

/obj/machinery/vending/dx_test/locked
	req_access = list(ACCESS_SECURITY)

/obj/machinery/vending/dx_test/priced
	prices = list(/obj/item/pen = 5)

/obj/item/refill_cartridge/dx_test
	refill_type = /obj/machinery/vending/dx_test

/// A powered test vendor on the floor.
/proc/dx_vending_make(vendor_type, turf/T)
	var/obj/machinery/vending/dx_test/V = new vendor_type(T)
	V.set_stat(0)
	return V

/// A live, interactive window on `V` for `user`.
/proc/dx_vending_window(mob/user, obj/machinery/vending/V)
	var/datum/tgui/ui = new(user, V, "Vending")
	ui.status = STATUS_INTERACTIVE
	return ui

/// The first entry of A named `name`, or the first slot entry holding `held_type`.
/proc/dx_vending_entry(atom/A, name, held_type)
	for(var/datum/interaction/capability/E as anything in cap_interactions(A))
		if(name && E.name == name)
			return E
		if(held_type && E.held_type == held_type && istype(E.cap, /datum/capability/slot))
			return E
	return null

/// The whole table is declared, with no interaction datum of the machine's own.
/datum/unit_test/dx_vending_capabilities/Run()
	var/obj/machinery/vending/dx_test/V = allocate(/obj/machinery/vending/dx_test, run_loc_floor_bottom_left)
	TEST_ASSERT_NOTNULL(cap_of(V, /datum/capability/panel), "a panel")
	TEST_ASSERT_NOTNULL(cap_of(V, /datum/capability/wires), "wires")
	TEST_ASSERT_NOTNULL(cap_of(V, /datum/capability/emag), "an emag")
	TEST_ASSERT_NOTNULL(cap_of(V, /datum/capability/anchor), "an anchor")
	TEST_ASSERT_NOTNULL(V.slot_capability(nameof(V.coin)), "the coin slot")
	for(var/name in list("Refill", "Insert coin", "Stock", "Use", "Check vending logs"))
		TEST_ASSERT_NOTNULL(dx_vending_entry(V, name), "an entry named [name]")
	TEST_ASSERT(hascall(V, "finish_vend"), "the delayed vend is finish_vend")
	TEST_ASSERT(!hascall(V, "ui_act_vend") && !hascall(V, "interaction_coin") && !hascall(V, "interaction_refill"), "the old handlers are gone")
	TEST_ASSERT_EQUAL(V.tgui_id, "Vending", "the window is the type var")
	TEST_ASSERT_EQUAL(V.maintenance_flags, NONE, "no legacy maintenance interactions beside the capabilities")

/// The coin slot: insert (a real coin, gated by the premium slot), premium stock unlocks, the eject
/// action gives it back, vending a premium product eats it, a fake coin is refused.
/datum/unit_test/dx_vending_coin_slot/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/vending/dx_test/V = allocate(/obj/machinery/vending/dx_test, T)
	V.set_stat(0)
	var/obj/item/coin/gold/C = allocate(/obj/item/coin/gold, T)
	var/datum/interaction/capability/entry = dx_vending_entry(V, null, /obj/item/coin)
	TEST_ASSERT_NOTNULL(entry, "the slot offers an insert entry for coins")
	TEST_ASSERT(H.put_in_active_hand(C), "the human holds the coin")
	TEST_ASSERT(entry.perform(H, V, C), "the coin goes in")
	TEST_ASSERT_EQUAL(V.coin, C, "the coin is in the slot")
	TEST_ASSERT_EQUAL(C.loc, V, "and inside the machine")
	TEST_ASSERT(V.categories & CAT_COIN, "premium products are shown")
	TEST_ASSERT_EQUAL(V.tgui_data(H)["coin"], C.name, "the window shows the coin")

	var/datum/tgui/ui = dx_vending_window(H, V)
	TEST_ASSERT(V.tgui_act("remove_coin", list(), ui), "the eject action runs")
	TEST_ASSERT_NULL(V.coin, "the slot is empty")
	TEST_ASSERT_EQUAL(C.loc, H, "the coin is back with the customer")
	TEST_ASSERT(!(V.categories & CAT_COIN), "premium products are hidden again")
	TEST_ASSERT(!V.tgui_data(H)["coin"], "the window shows no coin")
	TEST_ASSERT(!V.tgui_act("remove_coin", list(), ui), "an empty slot refuses")

	// A premium purchase swallows the coin.
	TEST_ASSERT(V.slot_insert(nameof(V.coin), C, H), "the coin goes in from code")
	var/datum/stored_item/vending_product/premium
	var/premium_key
	for(var/key in 1 to length(V.product_records))
		var/datum/stored_item/vending_product/R = V.product_records[key]
		if(R.category & CAT_COIN)
			premium = R
			premium_key = key
	TEST_ASSERT_NOTNULL(premium, "there is a premium product")
	TEST_ASSERT(V.tgui_act("vend", list("vend" = premium_key), ui), "the premium product vends against the coin")
	TEST_ASSERT_NULL(V.coin, "the coin was eaten")
	TEST_ASSERT(!(V.categories & CAT_COIN), "and the premium products are hidden")

	// Fake coins and a machine with no slot.
	var/obj/machinery/vending/dx_test/plain/P = allocate(/obj/machinery/vending/dx_test/plain, T)
	P.set_stat(0)
	var/datum/interaction/capability/plain_entry = dx_vending_entry(P, null, /obj/item/coin)
	TEST_ASSERT_EQUAL(plain_entry.why_not(H, P, C), "it has no coin slot", "no premium products, no coin slot")
	var/obj/item/fake_coin/gold/fake = allocate(/obj/item/fake_coin/gold, T)
	var/datum/interaction/capability/fake_entry
	for(var/datum/interaction/capability/E as anything in cap_interactions(V))
		if(E.name == "Insert coin")
			fake_entry = E
	TEST_ASSERT_NOTNULL(fake_entry, "fake coins have their own entry")
	V.set_stat(0)
	fake_entry.perform(H, V, fake)
	TEST_ASSERT_NULL(V.coin, "a fake coin is never taken")
	qdel(ui)

/// The vend action: validated key, busy, access, panel, price; the delayed vend is finish_vend.
/datum/unit_test/dx_vending_vend/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/vending/dx_test/V = allocate(/obj/machinery/vending/dx_test, T)
	V.set_stat(0)
	var/datum/tgui/ui = dx_vending_window(H, V)
	var/datum/stored_item/vending_product/R = V.product_records[1]
	var/before = R.get_amount()
	GLOB.refuse_capture = list()

	TEST_ASSERT(!V.tgui_act("vend", list("vend" = 99), ui), "a key past the list is refused (not clamped onto another product)")
	TEST_ASSERT(!V.tgui_act("vend", list("vend" = 0), ui), "key 0 is refused")
	TEST_ASSERT(!V.tgui_act("vend", list("vend" = "abc"), ui), "a non-number is refused")
	TEST_ASSERT(!V.tgui_act("vend", list(), ui), "a missing key is refused")
	TEST_ASSERT(!V.tgui_act("vend", list("vend" = 2), ui), "a premium product is refused with no coin shown")
	TEST_ASSERT(V.vend_ready, "nothing started")
	TEST_ASSERT_EQUAL(R.get_amount(), before, "and nothing was taken")

	cap_set(V, CAP_PANEL_OPEN, TRUE)
	TEST_ASSERT(!V.tgui_act("vend", list("vend" = 1), ui), "an open service panel refuses")
	cap_set(V, CAP_PANEL_OPEN, FALSE)

	TEST_ASSERT(V.tgui_act("vend", list("vend" = "1"), ui), "a free product vends (numeric text is fine)")
	TEST_ASSERT(!V.vend_ready, "the machine is busy until it finishes")
	TEST_ASSERT(!V.tgui_act("vend", list("vend" = 1), ui), "a second request while busy is refused")
	var/list/refusals = GLOB.refuse_capture
	GLOB.refuse_capture = null
	var/found_busy = FALSE
	for(var/list/entry in refusals)
		if(findtext(entry[2], "busy"))
			found_busy = TRUE
	TEST_ASSERT(found_busy, "the busy refusal was told to the customer")
	var/obj/item/pen/existing = locate() in T
	V.finish_vend(R, H)
	TEST_ASSERT(V.vend_ready, "finish_vend frees the machine")
	TEST_ASSERT_EQUAL(R.get_amount(), before - 1, "one was taken")
	var/found_pen = FALSE
	for(var/obj/item/pen/P in T)
		if(P != existing)
			found_pen = TRUE
	TEST_ASSERT(found_pen, "the product is on the floor")
	for(var/obj/item/pen/P in T)
		qdel(P)
	TEST_ASSERT(V.tgui_act("toggle_voice", list(), ui) == FALSE, "the speaker switch needs the panel")
	cap_set(V, CAP_PANEL_OPEN, TRUE)
	TEST_ASSERT(V.tgui_act("toggle_voice", list(), ui), "with the panel open it flips")
	TEST_ASSERT(!V.shut_up, "the speaker is on")
	TEST_ASSERT_EQUAL(V.tgui_data(H)["panel"], 1, "the window shows the panel")
	TEST_ASSERT_EQUAL(V.tgui_data(H)["speaker"], 1, "and the speaker")
	qdel(ui)

/// Access: a locked vendor refuses a customer with no ID until it is emagged; a paid product with no
/// way to pay takes nothing and leaves the machine free.
/datum/unit_test/dx_vending_access_and_price/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/vending/dx_test/locked/L = allocate(/obj/machinery/vending/dx_test/locked, T)
	L.set_stat(0)
	var/datum/tgui/ui = dx_vending_window(H, L)
	TEST_ASSERT(!L.tgui_act("vend", list("vend" = 1), ui), "no ID, no product")
	TEST_ASSERT(L.vend_ready, "the machine stays free")
	cap_set(L, CAP_EMAGGED, TRUE)
	TEST_ASSERT(L.tgui_act("vend", list("vend" = 1), ui), "an emagged vendor ignores the lock")
	TEST_ASSERT(!L.vend_ready, "and vends")
	qdel(ui)

	var/obj/machinery/vending/dx_test/priced/P = allocate(/obj/machinery/vending/dx_test/priced, T)
	P.set_stat(0)
	ui = dx_vending_window(H, P)
	var/datum/stored_item/vending_product/R = P.product_records[1]
	TEST_ASSERT_EQUAL(R.price, 5, "the product has a price")
	var/before = R.get_amount()
	TEST_ASSERT(!P.tgui_act("vend", list("vend" = 1), ui), "nothing to pay with, no product")
	TEST_ASSERT(P.vend_ready, "the machine is free again")
	TEST_ASSERT_EQUAL(R.get_amount(), before, "nothing was taken")
	TEST_ASSERT(P.tgui_data(H)["chargesMoney"], "the window says it charges")
	// A machine that can't work refuses every action.
	P.set_stat(NOPOWER)
	TEST_ASSERT(!P.tgui_act("vend", list("vend" = 1), ui), "an unpowered vendor refuses")
	qdel(ui)

/// The panel and its wires: a screwdriver toggles the panel, the wires need it open, the wires
/// datum reads the capability state, and the panel state is drawn.
/datum/unit_test/dx_vending_panel_wires/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/vending/dx_test/V = allocate(/obj/machinery/vending/dx_test, T)
	V.set_stat(0)
	var/obj/item/tool/screwdriver/screwdriver = allocate(/obj/item/tool/screwdriver, T)
	var/datum/interaction/capability/toggle = cap_test_entry(V, "panel:[TOOL_SCREWDRIVER]")
	var/datum/interaction/capability/pulse = cap_test_entry(V, "wires:multitool")
	TEST_ASSERT_NOTNULL(toggle, "a screwdriver toggles the panel")
	TEST_ASSERT_NOTNULL(pulse, "a multitool pulses the wires")
	var/datum/wires/vending/W = wires_of(V)
	TEST_ASSERT(istype(W), "the wires datum is the capability's")
	TEST_ASSERT_EQUAL(pulse.why_not(H, V, null), "needs a multitool", "the tool comes first")
	TEST_ASSERT(!W.interactable(H), "closed: the wires can't be used")
	TEST_ASSERT(!wires_exposed(V), "and are not exposed")
	TEST_ASSERT(H.put_in_active_hand(screwdriver), "the human holds a screwdriver")
	TEST_ASSERT(toggle.perform(H, V, screwdriver), "the panel opens")
	TEST_ASSERT(panel_is_open(V), "the bit is set")
	TEST_ASSERT(wires_exposed(V), "the wires are exposed")
	TEST_ASSERT(W.interactable(H), "and usable")
	refresh_flush()
	TEST_ASSERT(cap_test_has_layer(V, "generic-panel"), "the open panel is drawn as the vendor's own panel state")
	W.on_pulse(WIRE_CONTRABAND)
	TEST_ASSERT(V.categories & CAT_HIDDEN, "the contraband wire shows the hidden products")
	W.on_cut(WIRE_IDSCAN, FALSE)
	TEST_ASSERT(V.scan_id, "cutting the ID scan wire leaves it scanning")
	TEST_ASSERT(toggle.perform(H, V, screwdriver), "the panel closes")
	refresh_flush()
	TEST_ASSERT(!cap_test_has_layer(V, "generic-panel"), "the panel state is gone")
	// Anchoring needs the panel closed (the old wrench interaction did too).
	var/datum/interaction/capability/anchor = dx_vending_entry(V, "Anchor")
	TEST_ASSERT_NOTNULL(anchor, "the machine can be (un)anchored")
	cap_set(V, CAP_PANEL_OPEN, TRUE)
	TEST_ASSERT_EQUAL(anchor.why_not(H, V, null), "needs a wrench", "the wrench is asked for first")
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)
	TEST_ASSERT_EQUAL(anchor.why_not(H, V, wrench), "close the maintenance panel first", "an open panel blocks anchoring")

/// Emag: unlocks the product lock, repeatable, and every swipe spends a charge.
/datum/unit_test/dx_vending_emag/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/vending/dx_test/locked/V = allocate(/obj/machinery/vending/dx_test/locked, T)
	V.set_stat(0)
	var/obj/item/card/emag/card = allocate(/obj/item/card/emag, T)
	var/datum/interaction/capability/entry = cap_test_entry(V, "emag")
	TEST_ASSERT_NOTNULL(entry, "an emag entry")
	TEST_ASSERT(H.put_in_active_hand(card), "the human holds the card")
	card.uses = 5
	TEST_ASSERT(!is_emagged(V), "not emagged yet")
	TEST_ASSERT(entry.perform(H, V, card), "the emag runs")
	TEST_ASSERT(is_emagged(V), "the product lock is shorted")
	TEST_ASSERT_EQUAL(card.uses, 4, "one charge spent")
	TEST_ASSERT_NOTEQUAL(cap_dispatch(new /datum/dispatch_context(H, V, card, entry)), UI_REFUSED, "a second swipe runs too (repeatable, as it always was)")
	TEST_ASSERT_EQUAL(card.uses, 3, "and spends another")

/// Refill: a matching cartridge restocks and is used up; unbolted or with the panel open it is refused.
/datum/unit_test/dx_vending_refill/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/vending/dx_test/V = allocate(/obj/machinery/vending/dx_test, T)
	V.set_stat(0)
	var/obj/item/refill_cartridge/dx_test/cart = allocate(/obj/item/refill_cartridge/dx_test, T)
	var/datum/interaction/capability/entry = dx_vending_entry(V, "Refill")
	TEST_ASSERT_NOTNULL(entry, "a refill entry")
	var/datum/stored_item/vending_product/R = V.product_records[1]
	R.amount = 0
	TEST_ASSERT_EQUAL(R.get_amount(), 0, "the shelf is empty")
	cap_set(V, CAP_PANEL_OPEN, TRUE)
	TEST_ASSERT_EQUAL(entry.why_not(H, V, cart), "close the maintenance panel first", "an open panel blocks refilling")
	cap_set(V, CAP_PANEL_OPEN, FALSE)
	V.set_anchored(FALSE)
	TEST_ASSERT_EQUAL(entry.why_not(H, V, cart), "you cannot refill it while it is not secured", "an unsecured vendor can't be refilled")
	V.set_anchored(TRUE)
	TEST_ASSERT_NULL(entry.why_not(H, V, cart), "a bolted, closed vendor can")
	TEST_ASSERT(entry.perform(H, V, cart), "the cartridge is used")
	TEST_ASSERT_EQUAL(R.get_amount(), 3, "the shelf is full again")
	TEST_ASSERT(QDELETED(cart), "the cartridge is used up")

/// draw(): the dark and broken faces, the panel state; nothing calls update_icon.
/datum/unit_test/dx_vending_draw/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/machinery/vending/dx_test/V = allocate(/obj/machinery/vending/dx_test, T)
	V.set_stat(0)
	changed(V)
	refresh_flush()
	TEST_ASSERT_EQUAL(V.icon_state, "generic", "a working vendor shows its face")
	V.set_stat(NOPOWER)
	changed(V)
	refresh_flush()
	TEST_ASSERT_EQUAL(V.icon_state, "generic-off", "no power: the dark face")
	V.set_stat(0)
	changed(V)
	V.malfunction()
	refresh_flush()
	TEST_ASSERT(is_broken(V), "malfunctioning breaks it")
	TEST_ASSERT_EQUAL(V.icon_state, "generic-broken", "broken: the broken face")
	TEST_ASSERT(!cap_test_has_layer(V, "generic-panel"), "no panel state while closed")
	cap_set(V, CAP_PANEL_OPEN, TRUE)
	refresh_flush()
	TEST_ASSERT(cap_test_has_layer(V, "generic-panel"), "panel open: its state is laid over the face")
	for(var/obj/item/pen/P in T)
		qdel(P)
