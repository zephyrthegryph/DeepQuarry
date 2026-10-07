// Behaviour-preservation tests for vending machines (phase 2): what a customer, a maintenance worker, an AI-driven event or an admin can observe of a
// vendor through public inputs (clicks, window buttons, wires, the damage and stumble entry points, time), so the same file passes before and after
// the vendor moves from the legacy declaration forms to the engine forms. Rules as in dq_p2_smes_behaviour.dm and dq_p2_chargers_behaviour.dm:
//   - Input goes through test_click(), the window adapter p2v_ui(), the wires datum's cut()/pulse(), the menu adapter and time; never an op key.
//   - State is read through the adapter block below (the only place that names today's accessors) and plain vars.
//   - Every input is followed by p2v_settle(): converted tool ops carry waits where today's code is instant.
//   - Nothing depends on message text or on a click result being non-null.
//
// The block is five by five. The vendor stands at p2v_spot(), the customer beside it.
//
// Not pinned (and why): the card PIN prompt (a typed prompt with no client answers nothing, so a card whose account needs a PIN is only pinned as refused);
// the unlucky trait's ten percent and the one percent bonus vend (rolls the test seed cannot steer); the stumble-into two percent (same); the explosion
// chance of malfunctioning (a quarter of light blasts); the NIF install of the NIFSoft shop (needs a working NIF); the log panel's contents (its own window).

// ---------------------------------------------------------------------------------------------------------------------
// Adapters: today's accessors, wrapped. After the conversion only these bodies change.
// ---------------------------------------------------------------------------------------------------------------------

/// The service panel is open.
/proc/p2v_panel_open(obj/machinery/vending/V)
	return !!panel_open(V)

/// The vendor is emagged (its product lock shorted out).
/proc/p2v_emagged(obj/machinery/vending/V)
	return !!emag_emagged(V)

/// The vendor is broken.
/proc/p2v_broken(obj/machinery/vending/V)
	return !!V.broken_now()

/// The vendor's wire record.
/proc/p2v_wires(obj/machinery/vending/V)
	return wiring_of(V)

/// The window's data as a viewer is sent it.
/proc/p2v_data(obj/machinery/vending/V, mob/user)
	return V.tgui_data(user)

/// Presses a window button as the actor: the engine's op if the vendor has one for the action, else today's tgui_act().
/proc/p2v_ui(mob/actor, obj/machinery/vending/V, action, list/args)
	var/datum/op_result/result = test_ui(actor, V, action, args)
	if(result)
		return result
	var/datum/tgui/ui = new(actor, V, "Vending")
	ui.status = STATUS_INTERACTIVE
	. = V.tgui_act(action, args || list(), ui)
	qdel(ui)

/// The actor asks the vendor for its log (the menu entry "Check vending logs").
/proc/p2v_check_logs(mob/actor, obj/machinery/vending/V)
	return test_menu(actor, V, "check_logs")

/// The vendor's records, in order.
/proc/p2v_records(obj/machinery/vending/V)
	return V.product_records.Copy()

/// The record of a product type.
/proc/p2v_record(obj/machinery/vending/V, path)
	RETURN_TYPE(/datum/stored_item/vending_product)
	for(var/datum/stored_item/vending_product/R as anything in V.product_records)
		if(R.item_path == path)
			return R
	return null

/// The window key (the position in the list) of a product type.
/proc/p2v_key(obj/machinery/vending/V, path)
	for(var/i in 1 to length(V.product_records))
		var/datum/stored_item/vending_product/R = V.product_records[i]
		if(R.item_path == path)
			return i
	return 0

/// The vendor is ready for a purchase (none in progress).
/proc/p2v_ready(obj/machinery/vending/V)
	return !!V.vend_ready

/// The coin held, or null.
/proc/p2v_coin(obj/machinery/vending/V)
	return V.coin

/// Which categories the window lists now.
/proc/p2v_categories(obj/machinery/vending/V)
	return V.categories

/// The wires' effects, read: shoot, electrified, contraband shown, scanning the ID.
/proc/p2v_shoot(obj/machinery/vending/V)
	return !!V.shoot_inventory

/proc/p2v_electrified(obj/machinery/vending/V)
	return !!shock_live(V)

/proc/p2v_scans_id(obj/machinery/vending/V)
	return !!V.scan_id

/// The vendor is told to be quiet or loud (the brand intelligence event does this).
/proc/p2v_set_quiet(obj/machinery/vending/V, quiet)
	V.set_shut_up(quiet)

/// The vendor is told to shoot its stock (the brand intelligence event, a cut wire).
/proc/p2v_set_shoot(obj/machinery/vending/V, on)
	V.set_shoot_inventory(on)

/// The vendor is electrified by an event for `lasts` (null: until released).
/proc/p2v_set_electrified(obj/machinery/vending/V, lasts)
	hold(V, STAT_ELECTRIFIED, 1, SRC_ROUND_EVENT, lasts)

/// The look the vendor draws: its icon state and overlays.
/proc/p2v_look(obj/machinery/vending/V)
	var/datum/look/look = new
	V.draw(look)
	return look

/// A test vendor's windows are recorded (a test mob has no client), and so are its shocks, its speech and its vends.
/obj/machinery/vending/p2v_test
	name = "p2 vendor"
	icon_state = "generic"
	products = list(/obj/item/pen = 3, /obj/item/paper = 2)
	contraband = list(/obj/item/clipboard = 2)
	premium = list(/obj/item/flame/lighter = 1)
	vend_delay = 1 SECONDS
	slogan_delay = 1 HOURS
	var/list/p2v_opened
	var/p2v_shocks = 0
	var/p2v_shock_result = 0
	var/list/p2v_spoken

/obj/machinery/vending/p2v_test/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, custom_state)
	LAZYADD(p2v_opened, user)
	return ..()

/obj/machinery/vending/p2v_test/shock(mob/user, prb)
	p2v_shocks++
	return p2v_shock_result

/obj/machinery/vending/p2v_test/speak(message)
	if(power_lost())
		return
	LAZYADD(p2v_spoken, message)

/// No coin slot: no premium stock.
/obj/machinery/vending/p2v_test/plain
	premium = null

/// Locked to the security access.
/obj/machinery/vending/p2v_test/locked
	req_access = list(ACCESS_SECURITY)

/// Everything has a price.
/obj/machinery/vending/p2v_test/priced
	prices = list(/obj/item/pen = 5, /obj/item/paper = 20)

/// Keeps a log and wants the armory for it.
/obj/machinery/vending/p2v_test/logged
	has_logs = 1
	req_log_access = ACCESS_ARMORY

/// Talks: slogans and a thank you.
/obj/machinery/vending/p2v_test/talker
	product_slogans = "Buy!;Buy more!"
	vend_reply = "Thanks!"
	slogan_delay = 1 SECONDS

/// Refill cartridges of the test vendor, and a universal one.
/obj/item/refill_cartridge/p2v
	refill_type = /obj/machinery/vending/p2v_test

GLOBAL_LIST_EMPTY(p2v_wire_windows)

/// A wire window opened for a mob (recorded: a test mob has no client).
/datum/cap_data/wires/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, custom_state)
	if(istype(owner, /obj/machinery/vending))
		LAZYADD(GLOB.p2v_wire_windows, user)
	return ..()

GLOBAL_LIST_EMPTY(p2v_log_windows)

/// A log panel opened for a mob (recorded).
/datum/dq_vending_log_panel/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, custom_state)
	LAZYADD(GLOB.p2v_log_windows, user)
	return ..()

// ---------------------------------------------------------------------------------------------------------------------
// The base: the kernel on its injected clock around the test, the floor as it was after.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_vending
	abstract_type = /datum/unit_test/dq_p2_vending
	var/list/p2v_vendors
	var/list/p2v_accounts
	var/saved_vendor_account
	var/saved_luminosity
	var/area/lit_area

/datum/unit_test/dq_p2_vending/Run()
	test_driver_begin()
	test_rng(1)
	GLOB.p2v_wire_windows = null
	GLOB.p2v_log_windows = null
	run_gate()
	for(var/obj/machinery/vending/V as anything in p2v_vendors)
		if(!QDELETED(V))
			qdel(V)
	for(var/datum/money_account/A as anything in p2v_accounts)
		registry_leave(REGISTRY_MONEY_ACCOUNTS, A)
	if(lit_area)
		lit_area.luminosity = saved_luminosity
	if(saved_vendor_account)
		GLOB.vendor_account = saved_vendor_account
	for(var/turf/T in block(run_loc_floor_bottom_left, run_loc_floor_top_right))
		own_turf_contents(T)
	GLOB.p2v_wire_windows = null
	GLOB.p2v_log_windows = null
	test_driver_end()

/datum/unit_test/dq_p2_vending/proc/run_gate()
	return

// ---- places and people ----

/datum/unit_test/dq_p2_vending/proc/p2v_spot()
	return get_step(run_loc_floor_bottom_left, EAST)

/datum/unit_test/dq_p2_vending/proc/p2v_side_spot()
	return get_step(p2v_spot(), NORTH)

/// A vendor standing at the spot, powered and bolted down.
/datum/unit_test/dq_p2_vending/proc/p2v_vendor(type = /obj/machinery/vending/p2v_test)
	var/obj/machinery/vending/V = allocate(type, p2v_spot())
	dq_machine_clear(V)
	LAZYADD(p2v_vendors, V)
	return V

/// The room is lit (a vendor sees who stands near it through view(), which shows nothing in the dark).
/datum/unit_test/dq_p2_vending/proc/p2v_light_room()
	lit_area = get_area(run_loc_floor_bottom_left)
	saved_luminosity = lit_area.luminosity
	lit_area.luminosity = 1

/// A conscious person with hands, who cannot be knocked out by the test's passing time.
/datum/unit_test/dq_p2_vending/proc/p2v_actor(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || p2v_side_spot())
	H.enable_godmode()
	return H

/// A person who can be hurt (the shock tests).
/datum/unit_test/dq_p2_vending/proc/p2v_mortal(turf/T)
	return allocate(/mob/living/carbon/human, T || p2v_side_spot())

/// Time for any wait a tool, a window press or a vend delay may start.
/datum/unit_test/dq_p2_vending/proc/p2v_settle(t = 3 SECONDS)
	test_time(t)
	if(GLOB.op_pure_depth)
		Fail("pure depth [GLOB.op_pure_depth] after settle")
		GLOB.op_pure_depth = 0

/// The actor puts `held` in the active hand (an empty hand when null), clicks the target and waits.
/datum/unit_test/dq_p2_vending/proc/touch(mob/living/carbon/human/H, atom/target, obj/item/held, t = 3 SECONDS)
	H.drop_item()
	if(held)
		H.put_in_active_hand(held)
	test_click(H, target, held)
	p2v_settle(t)

/// The actor presses a window button and waits.
/datum/unit_test/dq_p2_vending/proc/press(mob/actor, obj/machinery/vending/V, action, list/args, t = 3 SECONDS)
	. = p2v_ui(actor, V, action, args)
	p2v_settle(t)

/// A tool with no speed penalty.
/datum/unit_test/dq_p2_vending/proc/tool(path)
	return dq_fast_tool(path, p2v_side_spot())

/// The actor opens or closes the service panel.
/datum/unit_test/dq_p2_vending/proc/toggle_panel(mob/living/carbon/human/H, obj/machinery/vending/V)
	touch(H, V, tool(/obj/item/tool/screwdriver))

/// An ID card on the actor (worn) with `access`, and (when money is given) an account of that much behind it. Returns the card.
/datum/unit_test/dq_p2_vending/proc/p2v_id(mob/living/carbon/human/H, list/access, money)
	var/obj/item/card/id/C = allocate(/obj/item/card/id, p2v_side_spot())
	C.access = access ? access.Copy() : list()
	C.registered_name = H.real_name
	if(!isnull(money))
		var/datum/money_account/A = create_account(H.real_name, money)
		A.security_level = 0
		C.associated_account_number = A.account_number
		LAZYADD(p2v_accounts, A)
	if(!H.get_equipped_item(SLOT_ID_UNIFORM))
		H.equip_to_slot_or_del(allocate(/obj/item/clothing/under/color/grey, p2v_side_spot()), SLOT_ID_UNIFORM)
	H.equip_to_slot_or_del(C, SLOT_ID_ID)
	return C

/// The account behind a card.
/datum/unit_test/dq_p2_vending/proc/p2v_account(obj/item/card/id/C)
	RETURN_TYPE(/datum/money_account)
	return get_account(C.associated_account_number)

/// The vendor's department account holds `amount` more than it did (a fresh account the vendor pays into).
/datum/unit_test/dq_p2_vending/proc/p2v_own_vendor_account(money = 0)
	saved_vendor_account = GLOB.vendor_account
	var/datum/money_account/A = create_account("P2 Vendor Dept", money)
	LAZYADD(p2v_accounts, A)
	GLOB.vendor_account = A
	return A

/// Every product left on the vendor's shelves, hidden and premium included.
/datum/unit_test/dq_p2_vending/proc/p2v_stock_total(obj/machinery/vending/V)
	. = 0
	for(var/datum/stored_item/vending_product/R as anything in V.product_records)
		. += R.get_amount()

/// How many things of `path` lie on the turf of `V`.
/datum/unit_test/dq_p2_vending/proc/p2v_count_on_floor(obj/machinery/vending/V, path)
	. = 0
	for(var/obj/item/I in get_turf(V))
		if(istype(I, path) && !QDELETED(I))
			.++

// ---------------------------------------------------------------------------------------------------------------------
// Records and the window's data
// ---------------------------------------------------------------------------------------------------------------------

/// The lists a vendor is built from become one record per product: its count (one when unnamed), its price (none: free) and its category.
/datum/unit_test/dq_p2_vending/records_from_the_product_lists
/datum/unit_test/dq_p2_vending/records_from_the_product_lists/run_gate()
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/p2v_test/priced)
	TEST_ASSERT_EQUAL(length(p2v_records(V)), 4, "one record per product, hidden and premium included")
	var/datum/stored_item/vending_product/pen = p2v_record(V, /obj/item/pen)
	var/datum/stored_item/vending_product/paper = p2v_record(V, /obj/item/paper)
	var/datum/stored_item/vending_product/clip = p2v_record(V, /obj/item/clipboard)
	var/datum/stored_item/vending_product/lighter = p2v_record(V, /obj/item/flame/lighter)
	TEST_ASSERT_EQUAL(pen.get_amount(), 3, "the pen count")
	TEST_ASSERT_EQUAL(paper.get_amount(), 2, "the paper count")
	TEST_ASSERT_EQUAL(clip.get_amount(), 2, "the hidden count")
	TEST_ASSERT_EQUAL(lighter.get_amount(), 1, "an unnamed amount is one")
	TEST_ASSERT_EQUAL(pen.price, 5, "the pen's price")
	TEST_ASSERT_EQUAL(paper.price, 20, "the paper's price")
	TEST_ASSERT_EQUAL(clip.price, 0, "an unpriced product is free")
	TEST_ASSERT_EQUAL(pen.category, CAT_NORMAL, "pens are normal stock")
	TEST_ASSERT_EQUAL(clip.category, CAT_HIDDEN, "the clipboard is contraband")
	TEST_ASSERT_EQUAL(lighter.category, CAT_COIN, "the lighter is premium")
	TEST_ASSERT(V.has_prices, "a vendor with prices charges")
	TEST_ASSERT(V.has_premium, "a vendor with premium stock has a coin slot")
	TEST_ASSERT_EQUAL(pen.item_name, initial(/obj/item/pen::name), "a record is named by its item")
	TEST_ASSERT_EQUAL(p2v_categories(V), CAT_NORMAL, "only normal stock is listed to begin with")
	TEST_ASSERT_NULL(V.products, "the build lists are consumed")

/// A vendor with neither prices nor premium stock does not charge and has no coin slot.
/datum/unit_test/dq_p2_vending/free_vendor_has_no_prices_or_slot
/datum/unit_test/dq_p2_vending/free_vendor_has_no_prices_or_slot/run_gate()
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/p2v_test/plain)
	TEST_ASSERT(!V.has_prices, "nothing is priced")
	TEST_ASSERT(!V.has_premium, "no premium stock, no coin slot")
	var/mob/living/carbon/human/H = p2v_actor()
	var/list/data = p2v_data(V, H)
	TEST_ASSERT(!data["chargesMoney"], "the window says it is free")

/// The window lists the shown categories only: contraband after the wire, premium with a coin.
/datum/unit_test/dq_p2_vending/window_lists_the_shown_categories
/datum/unit_test/dq_p2_vending/window_lists_the_shown_categories/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	var/list/data = p2v_data(V, H)
	var/list/products = data["products"]
	TEST_ASSERT_EQUAL(length(products), 2, "the pen and the paper")
	var/list/first = products[1]
	TEST_ASSERT_EQUAL(first["key"], p2v_key(V, /obj/item/pen), "a product is keyed by its place in the records")
	TEST_ASSERT_EQUAL(first["amount"], 3, "and shows its count")
	TEST_ASSERT_EQUAL(first["name"], initial(/obj/item/pen::name), "and its name")
	TEST_ASSERT_EQUAL(first["price"], 0, "and its price")
	TEST_ASSERT(first["isatom"], "and that it is an atom")
	p2v_wires_pulse(H, V, WIRE_CONTRABAND)
	TEST_ASSERT_EQUAL(length(p2v_data(V, H)["products"]), 3, "the contraband wire adds the hidden stock")
	var/obj/item/coin/gold/coin = allocate(/obj/item/coin/gold, p2v_side_spot())
	touch(H, V, coin)
	TEST_ASSERT_EQUAL(length(p2v_data(V, H)["products"]), 4, "a coin adds the premium stock")

/// The window says whether the panel is open and whether the speaker is on.
/datum/unit_test/dq_p2_vending/window_shows_panel_and_speaker
/datum/unit_test/dq_p2_vending/window_shows_panel_and_speaker/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	var/list/data = p2v_data(V, H)
	TEST_ASSERT_EQUAL(data["panel"], 0, "the panel is shut")
	TEST_ASSERT_NULL(data["speaker"], "and the speaker switch is not shown")
	toggle_panel(H, V)
	data = p2v_data(V, H)
	TEST_ASSERT_EQUAL(data["panel"], 1, "the panel is open")
	TEST_ASSERT_EQUAL(data["speaker"], 0, "and the speaker is off")
	p2v_set_quiet(V, FALSE)
	TEST_ASSERT_EQUAL(p2v_data(V, H)["speaker"], 1, "and on when told to be loud")

/// The window greets a customer by what they carry: nothing, cash, an ID with no account, an ID with one.
/datum/unit_test/dq_p2_vending/window_greets_the_customer
/datum/unit_test/dq_p2_vending/window_greets_the_customer/run_gate()
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/p2v_test/priced)
	var/mob/living/carbon/human/H = p2v_actor()
	var/list/data = p2v_data(V, H)
	TEST_ASSERT_EQUAL(data["userMoney"], 0, "no money with nothing")
	TEST_ASSERT_NULL(data["user"], "and no user")
	TEST_ASSERT(length(data["guestNotice"]), "a guest is told what to bring")
	TEST_ASSERT(data["chargesMoney"], "a priced vendor charges")
	var/obj/item/spacecash/c50/cash = allocate(/obj/item/spacecash/c50, p2v_side_spot())
	H.put_in_active_hand(cash)
	data = p2v_data(V, H)
	TEST_ASSERT_EQUAL(data["userMoney"], 50, "cash in hand is the customer's money")
	H.drop_item()
	var/obj/item/card/id/C = p2v_id(H, null, 700)
	data = p2v_data(V, H)
	TEST_ASSERT_EQUAL(data["userMoney"], 700, "the account behind the ID is the customer's money")
	var/list/user = data["user"]
	TEST_ASSERT_EQUAL(user["name"], p2v_account(C).owner_name, "the account's owner")
	C.associated_account_number = 0
	data = p2v_data(V, H)
	TEST_ASSERT_NULL(data["user"], "an ID with no account names no user")
	TEST_ASSERT_EQUAL(data["userMoney"], 0, "and has no money")

/// The window shows the coin and the product being paid for.
/datum/unit_test/dq_p2_vending/window_shows_coin_and_the_vend_in_progress
/datum/unit_test/dq_p2_vending/window_shows_coin_and_the_vend_in_progress/run_gate()
	p2v_own_vendor_account(0)
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/p2v_test/priced)
	var/mob/living/carbon/human/H = p2v_actor()
	TEST_ASSERT(!p2v_data(V, H)["coin"], "no coin shown")
	TEST_ASSERT_NULL(p2v_data(V, H)["actively_vending"], "nothing being vended")
	var/obj/item/coin/gold/coin = allocate(/obj/item/coin/gold, p2v_side_spot())
	touch(H, V, coin)
	TEST_ASSERT_EQUAL(p2v_data(V, H)["coin"], coin.name, "the coin is shown by name")
	var/obj/item/spacecash/c50/cash = allocate(/obj/item/spacecash/c50, p2v_side_spot())
	H.put_in_active_hand(cash)
	press(H, V, "vend", list("vend" = p2v_key(V, /obj/item/pen)), 0)
	TEST_ASSERT_EQUAL(p2v_data(V, H)["actively_vending"], initial(/obj/item/pen::name), "the product being paid for is shown while it is vended")
	p2v_settle()
	TEST_ASSERT_NULL(p2v_data(V, H)["actively_vending"], "and gone when it is delivered")

// ---------------------------------------------------------------------------------------------------------------------
// Vending: free products
// ---------------------------------------------------------------------------------------------------------------------

/// A free product is delivered to the floor after the vend delay, one less in stock; the vendor is busy until then.
/datum/unit_test/dq_p2_vending/vend_free_product
/datum/unit_test/dq_p2_vending/vend_free_product/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	var/datum/stored_item/vending_product/R = p2v_record(V, /obj/item/pen)
	var/key = p2v_key(V, /obj/item/pen)
	press(H, V, "vend", list("vend" = key), 0)
	TEST_ASSERT(!p2v_ready(V), "busy while it vends")
	TEST_ASSERT_EQUAL(p2v_count_on_floor(V, /obj/item/pen), 0, "nothing on the floor yet")
	p2v_settle()
	TEST_ASSERT(p2v_ready(V), "ready again")
	TEST_ASSERT_EQUAL(R.get_amount(), 2, "one less in stock")
	TEST_ASSERT_EQUAL(p2v_count_on_floor(V, /obj/item/pen), 1, "one pen on the floor")

/// A request for a key that names no listed product is refused (not clamped onto another product), and takes nothing.
/datum/unit_test/dq_p2_vending/vend_refuses_bad_keys
/datum/unit_test/dq_p2_vending/vend_refuses_bad_keys/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	var/datum/stored_item/vending_product/R = p2v_record(V, /obj/item/pen)
	press(H, V, "vend", list("vend" = 99))
	press(H, V, "vend", list("vend" = 0))
	press(H, V, "vend", list("vend" = "abc"))
	press(H, V, "vend", list())
	TEST_ASSERT(p2v_ready(V), "nothing started")
	TEST_ASSERT_EQUAL(R.get_amount(), 3, "and nothing was taken")
	TEST_ASSERT_EQUAL(p2v_count_on_floor(V, /obj/item/pen) + p2v_count_on_floor(V, /obj/item/paper), 0, "nothing was delivered")

/// A numeric text key is read as a number.
/datum/unit_test/dq_p2_vending/vend_takes_a_numeric_text_key
/datum/unit_test/dq_p2_vending/vend_takes_a_numeric_text_key/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	press(H, V, "vend", list("vend" = "[p2v_key(V, /obj/item/pen)]"))
	TEST_ASSERT_EQUAL(p2v_count_on_floor(V, /obj/item/pen), 1, "the pen came out")

/// Hidden and premium products cannot be vended while their category is not shown.
/datum/unit_test/dq_p2_vending/vend_refuses_unshown_categories
/datum/unit_test/dq_p2_vending/vend_refuses_unshown_categories/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	press(H, V, "vend", list("vend" = p2v_key(V, /obj/item/clipboard)))
	press(H, V, "vend", list("vend" = p2v_key(V, /obj/item/flame/lighter)))
	TEST_ASSERT(p2v_ready(V), "nothing started")
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/clipboard).get_amount(), 2, "the hidden stock is whole")
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/flame/lighter).get_amount(), 1, "the premium stock is whole")
	p2v_wires_pulse(H, V, WIRE_CONTRABAND)
	press(H, V, "vend", list("vend" = p2v_key(V, /obj/item/clipboard)))
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/clipboard).get_amount(), 1, "the hidden stock vends once the wire shows it")

/// A second request while the first is in progress is refused.
/datum/unit_test/dq_p2_vending/vend_is_busy_until_delivered
/datum/unit_test/dq_p2_vending/vend_is_busy_until_delivered/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	var/datum/stored_item/vending_product/R = p2v_record(V, /obj/item/pen)
	var/key = p2v_key(V, /obj/item/pen)
	press(H, V, "vend", list("vend" = key), 0)
	press(H, V, "vend", list("vend" = key), 0)
	p2v_settle()
	TEST_ASSERT_EQUAL(R.get_amount(), 2, "only one was taken")
	TEST_ASSERT_EQUAL(p2v_count_on_floor(V, /obj/item/pen), 1, "and only one delivered")
	press(H, V, "vend", list("vend" = key))
	TEST_ASSERT_EQUAL(R.get_amount(), 1, "and the next one goes once it is free")

/// An empty shelf vends nothing.
/datum/unit_test/dq_p2_vending/vend_refuses_an_empty_shelf
/datum/unit_test/dq_p2_vending/vend_refuses_an_empty_shelf/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	var/datum/stored_item/vending_product/R = p2v_record(V, /obj/item/pen)
	R.amount = 0
	press(H, V, "vend", list("vend" = p2v_key(V, /obj/item/pen)))
	TEST_ASSERT(p2v_ready(V), "nothing started")
	TEST_ASSERT_EQUAL(p2v_count_on_floor(V, /obj/item/pen), 0, "and nothing came out")

/// A vendor whose service panel is open vends nothing.
/datum/unit_test/dq_p2_vending/vend_refuses_with_the_panel_open
/datum/unit_test/dq_p2_vending/vend_refuses_with_the_panel_open/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	toggle_panel(H, V)
	press(H, V, "vend", list("vend" = p2v_key(V, /obj/item/pen)))
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/pen).get_amount(), 3, "nothing was taken")
	toggle_panel(H, V)
	press(H, V, "vend", list("vend" = p2v_key(V, /obj/item/pen)))
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/pen).get_amount(), 2, "with the panel shut it vends")

/// A vendor that cannot work (unpowered, broken) refuses every button.
/datum/unit_test/dq_p2_vending/vend_refuses_when_inoperable
/datum/unit_test/dq_p2_vending/vend_refuses_when_inoperable/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	var/key = p2v_key(V, /obj/item/pen)
	dq_machine_clear(V)
	V.set_grid_power(FALSE)
	press(H, V, "vend", list("vend" = key))
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/pen).get_amount(), 3, "an unpowered vendor vends nothing")
	dq_machine_clear(V)
	V.atom_break()
	TEST_ASSERT(p2v_broken(V), "it broke")
	press(H, V, "vend", list("vend" = key))
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/pen).get_amount(), 3, "a broken vendor vends nothing")

/// Someone who is out cold or restrained cannot work the window.
/datum/unit_test/dq_p2_vending/vend_refuses_an_incapable_customer
/datum/unit_test/dq_p2_vending/vend_refuses_an_incapable_customer/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	var/key = p2v_key(V, /obj/item/pen)
	H.equip_to_slot_or_del(allocate(/obj/item/handcuffs, p2v_side_spot()), SLOT_ID_HANDCUFFED)
	TEST_ASSERT(H.restrained(), "the customer is restrained")
	press(H, V, "vend", list("vend" = key))
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/pen).get_amount(), 3, "a restrained customer vends nothing")

/// A vendor with access requirements refuses a customer with no ID, takes one with the access, and ignores the lock once emagged or its scanner is cut.
/datum/unit_test/dq_p2_vending/vend_checks_access
/datum/unit_test/dq_p2_vending/vend_checks_access/run_gate()
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/p2v_test/locked)
	var/mob/living/carbon/human/H = p2v_actor()
	var/key = p2v_key(V, /obj/item/pen)
	press(H, V, "vend", list("vend" = key))
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/pen).get_amount(), 3, "no ID, no product")
	TEST_ASSERT(p2v_ready(V), "and the machine stays free")
	var/obj/item/card/id/wrong = p2v_id(H, list(ACCESS_ENGINE))
	press(H, V, "vend", list("vend" = key))
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/pen).get_amount(), 3, "the wrong access gets nothing")
	wrong.access = list(ACCESS_SECURITY)
	press(H, V, "vend", list("vend" = key))
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/pen).get_amount(), 2, "the right access gets a product")
	wrong.access = list()
	var/obj/machinery/vending/V2 = p2v_vendor(/obj/machinery/vending/p2v_test/locked)
	V2.forceMove(get_step(p2v_spot(), EAST))
	var/mob/living/carbon/human/other = p2v_actor(get_step(p2v_side_spot(), EAST))
	var/obj/item/card/emag/card = allocate(/obj/item/card/emag, p2v_side_spot())
	card.uses = 5
	touch(other, V2, card)
	TEST_ASSERT(p2v_emagged(V2), "the card shorted the lock")
	press(other, V2, "vend", list("vend" = key))
	TEST_ASSERT_EQUAL(p2v_record(V2, /obj/item/pen).get_amount(), 2, "an emagged vendor ignores the lock")

/// Cutting the ID scan wire leaves it scanning; pulsing it turns the scan off, and a vendor that does not scan sells to anyone.
/datum/unit_test/dq_p2_vending/vend_without_the_id_scan
/datum/unit_test/dq_p2_vending/vend_without_the_id_scan/run_gate()
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/p2v_test/locked)
	var/mob/living/carbon/human/H = p2v_actor()
	var/key = p2v_key(V, /obj/item/pen)
	TEST_ASSERT(p2v_scans_id(V), "it scans to begin with")
	p2v_wires_pulse(H, V, WIRE_IDSCAN)
	TEST_ASSERT(!p2v_scans_id(V), "the pulse turns the scan off")
	press(H, V, "vend", list("vend" = key))
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/pen).get_amount(), 2, "an unscanning vendor sells to anyone")
	p2v_wires_cut(H, V, WIRE_IDSCAN)
	TEST_ASSERT(p2v_scans_id(V), "cutting the wire puts the scan back")

// ---------------------------------------------------------------------------------------------------------------------
// Vending: paying
// ---------------------------------------------------------------------------------------------------------------------

/// Cash that covers the price pays; the change stays in the pile; a pile that is spent is used up.
/datum/unit_test/dq_p2_vending/vend_pays_with_cash
/datum/unit_test/dq_p2_vending/vend_pays_with_cash/run_gate()
	var/datum/money_account/dept = p2v_own_vendor_account(0)
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/p2v_test/priced)
	var/mob/living/carbon/human/H = p2v_actor()
	var/obj/item/spacecash/c50/cash = allocate(/obj/item/spacecash/c50, p2v_side_spot())
	H.put_in_active_hand(cash)
	var/datum/stored_item/vending_product/R = p2v_record(V, /obj/item/pen)
	press(H, V, "vend", list("vend" = p2v_key(V, /obj/item/pen)))
	TEST_ASSERT_EQUAL(cash.worth, 45, "the price came off the pile")
	TEST_ASSERT_EQUAL(dept.money, 5, "and into the vendor account")
	TEST_ASSERT_EQUAL(R.get_amount(), 2, "the pen was taken")
	TEST_ASSERT_EQUAL(p2v_count_on_floor(V, /obj/item/pen), 1, "and delivered")
	cash.worth = 5
	press(H, V, "vend", list("vend" = p2v_key(V, /obj/item/pen)))
	TEST_ASSERT(QDELETED(cash), "a pile that is spent is used up")
	TEST_ASSERT_EQUAL(dept.money, 10, "the vendor account was paid")

/// Too little cash buys nothing and costs nothing.
/datum/unit_test/dq_p2_vending/vend_refuses_too_little_cash
/datum/unit_test/dq_p2_vending/vend_refuses_too_little_cash/run_gate()
	var/datum/money_account/dept = p2v_own_vendor_account(0)
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/p2v_test/priced)
	var/mob/living/carbon/human/H = p2v_actor()
	var/obj/item/spacecash/c50/cash = allocate(/obj/item/spacecash/c50, p2v_side_spot())
	cash.worth = 4
	H.put_in_active_hand(cash)
	press(H, V, "vend", list("vend" = p2v_key(V, /obj/item/pen)))
	TEST_ASSERT_EQUAL(cash.worth, 4, "the cash is whole")
	TEST_ASSERT_EQUAL(dept.money, 0, "the account is untouched")
	TEST_ASSERT(p2v_ready(V), "the machine is free")
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/pen).get_amount(), 3, "and nothing was taken")

/// An electronic wallet pays as cash does (it is a cash pile of its own kind).
/datum/unit_test/dq_p2_vending/vend_pays_with_an_ewallet
/datum/unit_test/dq_p2_vending/vend_pays_with_an_ewallet/run_gate()
	var/datum/money_account/dept = p2v_own_vendor_account(0)
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/p2v_test/priced)
	var/mob/living/carbon/human/H = p2v_actor()
	var/obj/item/spacecash/ewallet/wallet = allocate(/obj/item/spacecash/ewallet, p2v_side_spot())
	wallet.owner_name = "Test Owner"
	wallet.worth = 30
	H.put_in_active_hand(wallet)
	press(H, V, "vend", list("vend" = p2v_key(V, /obj/item/pen)))
	TEST_ASSERT_EQUAL(wallet.worth, 25, "the price came off the wallet")
	TEST_ASSERT_EQUAL(dept.money, 5, "and into the vendor account")

/// An ID with an account pays from it; too little in the account buys nothing; an ID with no account buys nothing.
/datum/unit_test/dq_p2_vending/vend_pays_with_a_card
/datum/unit_test/dq_p2_vending/vend_pays_with_a_card/run_gate()
	var/datum/money_account/dept = p2v_own_vendor_account(0)
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/p2v_test/priced)
	var/mob/living/carbon/human/H = p2v_actor()
	var/obj/item/card/id/C = p2v_id(H, null, 12)
	var/datum/money_account/mine = p2v_account(C)
	press(H, V, "vend", list("vend" = p2v_key(V, /obj/item/paper)))
	TEST_ASSERT_EQUAL(mine.money, 12, "too little in the account: nothing paid")
	TEST_ASSERT(p2v_ready(V), "the machine is free")
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/paper).get_amount(), 2, "and nothing taken")
	press(H, V, "vend", list("vend" = p2v_key(V, /obj/item/pen)))
	TEST_ASSERT_EQUAL(mine.money, 7, "the price came out of the account")
	TEST_ASSERT_EQUAL(dept.money, 5, "and into the vendor account")
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/pen).get_amount(), 2, "the pen was taken")
	C.associated_account_number = 0
	press(H, V, "vend", list("vend" = p2v_key(V, /obj/item/pen)))
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/pen).get_amount(), 2, "an ID with no account buys nothing")
	TEST_ASSERT(p2v_ready(V), "and leaves the machine free")

/// A customer with nothing to pay with buys nothing from a priced vendor.
/datum/unit_test/dq_p2_vending/vend_refuses_no_payment
/datum/unit_test/dq_p2_vending/vend_refuses_no_payment/run_gate()
	p2v_own_vendor_account(0)
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/p2v_test/priced)
	var/mob/living/carbon/human/H = p2v_actor()
	press(H, V, "vend", list("vend" = p2v_key(V, /obj/item/pen)))
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/pen).get_amount(), 3, "nothing was taken")
	TEST_ASSERT(p2v_ready(V), "the machine is free")

/// A card whose account is protected by a PIN buys nothing without an answer to the prompt (a test mob answers none).
/datum/unit_test/dq_p2_vending/vend_refuses_a_pin_card_unanswered
/datum/unit_test/dq_p2_vending/vend_refuses_a_pin_card_unanswered/run_gate()
	var/datum/money_account/dept = p2v_own_vendor_account(0)
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/p2v_test/priced)
	var/mob/living/carbon/human/H = p2v_actor()
	var/obj/item/card/id/C = p2v_id(H, null, 100)
	p2v_account(C).security_level = 1
	press(H, V, "vend", list("vend" = p2v_key(V, /obj/item/pen)))
	TEST_ASSERT_EQUAL(p2v_account(C).money, 100, "nothing paid")
	TEST_ASSERT_EQUAL(dept.money, 0, "nothing received")
	TEST_ASSERT(p2v_ready(V), "the machine is free")

/// A card whose account is protected by a PIN pays once the PIN is typed in the prompt the vend asks (the prompt is the op's own step).
/datum/unit_test/dq_p2_vending/vend_pays_with_a_pin_card_when_answered
/datum/unit_test/dq_p2_vending/vend_pays_with_a_pin_card_when_answered/run_gate()
	var/datum/money_account/dept = p2v_own_vendor_account(0)
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/p2v_test/priced)
	var/mob/living/carbon/human/H = p2v_actor()
	var/obj/item/card/id/C = p2v_id(H, null, 100)
	var/datum/money_account/mine = p2v_account(C)
	mine.security_level = 1
	var/key = p2v_key(V, /obj/item/pen)
	p2v_ui(H, V, "vend", list("vend" = key))
	p2v_settle(0)
	TEST_ASSERT_EQUAL(mine.money, 100, "nothing is paid before the PIN is answered")
	test_answer(H, mine.remote_access_pin)
	p2v_settle()
	TEST_ASSERT_EQUAL(mine.money, 95, "the price came out of the account")
	TEST_ASSERT_EQUAL(dept.money, 5, "and into the vendor account")
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/pen).get_amount(), 2, "the pen was taken")
	p2v_ui(H, V, "vend", list("vend" = key))
	p2v_settle(0)
	test_answer(H, mine.remote_access_pin + 1)
	p2v_settle()
	TEST_ASSERT_EQUAL(mine.money, 95, "a wrong PIN pays nothing")
	TEST_ASSERT(p2v_ready(V), "and leaves the machine free")
	p2v_ui(H, V, "vend", list("vend" = key))
	p2v_settle(0)
	test_answer(H, null, REQ_CANCELLED)
	p2v_settle()
	TEST_ASSERT_EQUAL(mine.money, 95, "a cancelled prompt pays nothing")
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/pen).get_amount(), 2, "and takes nothing")

/// A customer the vendor turns away (no access) is not asked for a PIN.
/datum/unit_test/dq_p2_vending/vend_does_not_ask_the_pin_of_a_stranger
/datum/unit_test/dq_p2_vending/vend_does_not_ask_the_pin_of_a_stranger/run_gate()
	p2v_own_vendor_account(0)
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/p2v_test/priced)
	V.req_access = list(ACCESS_SECURITY)
	var/mob/living/carbon/human/H = p2v_actor()
	var/obj/item/card/id/C = p2v_id(H, list(ACCESS_ENGINE), 100)
	p2v_account(C).security_level = 1
	p2v_ui(H, V, "vend", list("vend" = p2v_key(V, /obj/item/pen)))
	p2v_settle(0)
	test_answer(H, p2v_account(C).remote_access_pin)
	p2v_settle()
	TEST_ASSERT_EQUAL(p2v_account(C).money, 100, "nothing is paid by someone without access")
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/pen).get_amount(), 3, "and nothing is taken")

/// A machine whose vendor account is gone or suspended takes no payment.
/datum/unit_test/dq_p2_vending/vend_refuses_without_a_vendor_account
/datum/unit_test/dq_p2_vending/vend_refuses_without_a_vendor_account/run_gate()
	var/datum/money_account/dept = p2v_own_vendor_account(0)
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/p2v_test/priced)
	var/mob/living/carbon/human/H = p2v_actor()
	var/obj/item/card/id/C = p2v_id(H, null, 100)
	dept.suspended = TRUE
	press(H, V, "vend", list("vend" = p2v_key(V, /obj/item/pen)))
	dept.suspended = FALSE
	TEST_ASSERT_EQUAL(p2v_account(C).money, 100, "the customer paid nothing")
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/pen).get_amount(), 3, "and took nothing")
	TEST_ASSERT(p2v_ready(V), "the machine is free")

/// A machine of the law buys nothing that costs money (a cyborg), but takes a free product.
/datum/unit_test/dq_p2_vending/vend_silicon_takes_only_free_products
/datum/unit_test/dq_p2_vending/vend_silicon_takes_only_free_products/run_gate()
	p2v_own_vendor_account(0)
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/p2v_test/priced)
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, p2v_side_spot())
	press(R, V, "vend", list("vend" = p2v_key(V, /obj/item/pen)))
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/pen).get_amount(), 3, "a priced product is refused")
	var/obj/machinery/vending/F = p2v_vendor()
	F.forceMove(get_step(p2v_spot(), EAST))
	press(R, F, "vend", list("vend" = p2v_key(F, /obj/item/pen)))
	TEST_ASSERT_EQUAL(p2v_record(F, /obj/item/pen).get_amount(), 2, "a free one is taken")

// ---------------------------------------------------------------------------------------------------------------------
// The coin slot
// ---------------------------------------------------------------------------------------------------------------------

/// A real coin goes in by click and unlocks the premium products; the window gives it back.
/datum/unit_test/dq_p2_vending/coin_goes_in_and_comes_out
/datum/unit_test/dq_p2_vending/coin_goes_in_and_comes_out/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	var/obj/item/coin/gold/coin = allocate(/obj/item/coin/gold, p2v_side_spot())
	touch(H, V, coin)
	TEST_ASSERT_EQUAL(p2v_coin(V), coin, "the coin is in the slot")
	TEST_ASSERT_EQUAL(coin.loc, V, "inside the machine")
	TEST_ASSERT(p2v_categories(V) & CAT_COIN, "premium products are shown")
	press(H, V, "remove_coin")
	TEST_ASSERT_NULL(p2v_coin(V), "the slot is empty")
	TEST_ASSERT_EQUAL(coin.loc, H, "the coin is back with the customer")
	TEST_ASSERT(!(p2v_categories(V) & CAT_COIN), "premium products are hidden again")
	press(H, V, "remove_coin")
	TEST_ASSERT_NULL(p2v_coin(V), "an empty slot gives nothing")

/// A second coin is refused while one is in.
/datum/unit_test/dq_p2_vending/coin_slot_takes_one
/datum/unit_test/dq_p2_vending/coin_slot_takes_one/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	var/obj/item/coin/gold/first = allocate(/obj/item/coin/gold, p2v_side_spot())
	var/obj/item/coin/gold/second = allocate(/obj/item/coin/gold, p2v_side_spot())
	touch(H, V, first)
	touch(H, V, second)
	TEST_ASSERT_EQUAL(p2v_coin(V), first, "the first coin stays")
	TEST_ASSERT_NOTEQUAL(second.loc, V, "the second is not taken")

/// A vendor with no premium stock has no coin slot; a fake coin is never taken.
/datum/unit_test/dq_p2_vending/coin_slot_absent_or_fooled
/datum/unit_test/dq_p2_vending/coin_slot_absent_or_fooled/run_gate()
	var/obj/machinery/vending/P = p2v_vendor(/obj/machinery/vending/p2v_test/plain)
	var/mob/living/carbon/human/H = p2v_actor()
	var/obj/item/coin/gold/coin = allocate(/obj/item/coin/gold, p2v_side_spot())
	touch(H, P, coin)
	TEST_ASSERT_NULL(p2v_coin(P), "no slot, no coin")
	TEST_ASSERT_NOTEQUAL(coin.loc, P, "the coin is not taken")
	var/obj/machinery/vending/V = p2v_vendor()
	V.forceMove(get_step(p2v_spot(), EAST))
	var/obj/item/fake_coin/gold/fake = allocate(/obj/item/fake_coin/gold, p2v_side_spot())
	touch(H, V, fake)
	TEST_ASSERT_NULL(p2v_coin(V), "a fake coin is never taken")

/// A premium product needs the coin, and the purchase swallows it.
/datum/unit_test/dq_p2_vending/coin_is_swallowed_by_a_premium_vend
/datum/unit_test/dq_p2_vending/coin_is_swallowed_by_a_premium_vend/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	var/obj/item/coin/gold/coin = allocate(/obj/item/coin/gold, p2v_side_spot())
	var/key = p2v_key(V, /obj/item/flame/lighter)
	press(H, V, "vend", list("vend" = key))
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/flame/lighter).get_amount(), 1, "no coin, no premium product")
	touch(H, V, coin)
	press(H, V, "vend", list("vend" = key))
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/flame/lighter).get_amount(), 0, "the premium product was taken")
	TEST_ASSERT_NULL(p2v_coin(V), "the coin was swallowed")
	TEST_ASSERT(QDELETED(coin), "and is gone")
	TEST_ASSERT(!(p2v_categories(V) & CAT_COIN), "the premium products are hidden again")
	TEST_ASSERT_EQUAL(p2v_count_on_floor(V, /obj/item/flame/lighter), 1, "the lighter came out")

// ---------------------------------------------------------------------------------------------------------------------
// Stocking, refilling, logs
// ---------------------------------------------------------------------------------------------------------------------

/// An item that matches a record (by type and name) is stocked by click; one that does not is not.
/datum/unit_test/dq_p2_vending/stock_by_click
/datum/unit_test/dq_p2_vending/stock_by_click/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	var/datum/stored_item/vending_product/R = p2v_record(V, /obj/item/pen)
	var/obj/item/pen/pen = allocate(/obj/item/pen, p2v_side_spot())
	touch(H, V, pen)
	TEST_ASSERT_EQUAL(R.get_amount(), 4, "the pen is in stock")
	TEST_ASSERT(QDELETED(pen) || pen.loc == V, "and gone from the hand")
	var/obj/item/pen/named = allocate(/obj/item/pen, p2v_side_spot())
	named.name = "a different pen"
	touch(H, V, named)
	TEST_ASSERT_EQUAL(R.get_amount(), 4, "a pen with another name is not stocked")
	TEST_ASSERT_NOTEQUAL(named.loc, V, "and stays out")
	var/obj/item/flashlight/torch = allocate(/obj/item/flashlight, p2v_side_spot())
	touch(H, V, torch)
	TEST_ASSERT_NOTEQUAL(torch.loc, V, "a thing the vendor does not stock stays out")

/// A vendor that keeps logs writes a line for each product vended and stocked, with the card's name.
/datum/unit_test/dq_p2_vending/vend_and_stock_are_logged
/datum/unit_test/dq_p2_vending/vend_and_stock_are_logged/run_gate()
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/p2v_test/logged)
	var/mob/living/carbon/human/H = p2v_actor()
	p2v_id(H, null)
	press(H, V, "vend", list("vend" = p2v_key(V, /obj/item/pen)))
	TEST_ASSERT_EQUAL(length(V.log), 1, "the vend is logged")
	var/list/line = V.log[1]
	TEST_ASSERT_EQUAL(line[1], "vend", "as a vend")
	TEST_ASSERT_EQUAL(line[2], H.real_name, "by the card's name")
	TEST_ASSERT_EQUAL(line[4], initial(/obj/item/pen::name), "of the product")
	var/obj/item/pen/pen = allocate(/obj/item/pen, p2v_side_spot())
	touch(H, V, pen)
	TEST_ASSERT_EQUAL(length(V.log), 2, "the stocking is logged")
	var/list/second = V.log[2]
	TEST_ASSERT_EQUAL(second[1], "stock", "as a stock")
	var/obj/machinery/vending/Q = p2v_vendor()
	Q.forceMove(get_step(p2v_spot(), EAST))
	press(H, Q, "vend", list("vend" = p2v_key(Q, /obj/item/pen)))
	TEST_ASSERT_EQUAL(length(Q.log), 0, "a vendor that keeps no logs writes none")

/// The log is shown to someone whose card has the log access, from the menu, and refused to anyone else.
/datum/unit_test/dq_p2_vending/logs_need_the_log_access
/datum/unit_test/dq_p2_vending/logs_need_the_log_access/run_gate()
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/p2v_test/logged)
	var/mob/living/carbon/human/H = p2v_actor()
	p2v_check_logs(H, V)
	p2v_settle()
	TEST_ASSERT_EQUAL(length(GLOB.p2v_log_windows), 0, "no card, no log")
	var/obj/item/card/id/C = p2v_id(H, list(ACCESS_CARGO))
	p2v_check_logs(H, V)
	p2v_settle()
	TEST_ASSERT_EQUAL(length(GLOB.p2v_log_windows), 0, "the wrong access gets no log")
	C.access = list(ACCESS_ARMORY)
	p2v_check_logs(H, V)
	p2v_settle()
	TEST_ASSERT_EQUAL(length(GLOB.p2v_log_windows), 1, "the log access opens the log")

/// A cartridge of the vendor's kind adds every product's starting count and is used up; it needs a bolted vendor with its panel shut.
/datum/unit_test/dq_p2_vending/refill_with_a_cartridge
/datum/unit_test/dq_p2_vending/refill_with_a_cartridge/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	var/datum/stored_item/vending_product/R = p2v_record(V, /obj/item/pen)
	R.amount = 0
	var/obj/item/refill_cartridge/p2v/cart = allocate(/obj/item/refill_cartridge/p2v, p2v_side_spot())
	toggle_panel(H, V)
	touch(H, V, cart)
	TEST_ASSERT_EQUAL(R.get_amount(), 0, "an open panel refuses the refill")
	TEST_ASSERT(!QDELETED(cart), "and keeps the cartridge")
	toggle_panel(H, V)
	V.set_anchored(FALSE)
	touch(H, V, cart)
	TEST_ASSERT_EQUAL(R.get_amount(), 0, "an unbolted vendor refuses it")
	V.set_anchored(TRUE)
	touch(H, V, cart)
	TEST_ASSERT_EQUAL(R.get_amount(), 3, "a bolted, closed vendor takes it")
	TEST_ASSERT(QDELETED(cart), "the cartridge is used up")
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/paper).get_amount(), 4, "and every other shelf gained its starting count too (a refill adds, it does not top up)")

/// A cartridge made for another kind of vendor is refused.
/datum/unit_test/dq_p2_vending/refill_refuses_the_wrong_cartridge
/datum/unit_test/dq_p2_vending/refill_refuses_the_wrong_cartridge/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	var/datum/stored_item/vending_product/R = p2v_record(V, /obj/item/pen)
	R.amount = 0
	var/obj/item/refill_cartridge/wrong = allocate(/obj/item/refill_cartridge, p2v_side_spot())
	touch(H, V, wrong)
	TEST_ASSERT_EQUAL(R.get_amount(), 0, "nothing was refilled")
	TEST_ASSERT(!QDELETED(wrong), "and the cartridge is kept")

/// A universal cartridge refills any vendor.
/datum/unit_test/dq_p2_vending/refill_with_the_universal_cartridge
/datum/unit_test/dq_p2_vending/refill_with_the_universal_cartridge/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	var/datum/stored_item/vending_product/R = p2v_record(V, /obj/item/paper)
	R.amount = 0
	var/obj/item/refill_cartridge/universal/cart = allocate(/obj/item/refill_cartridge/universal, p2v_side_spot())
	touch(H, V, cart)
	TEST_ASSERT_EQUAL(R.get_amount(), 2, "the paper shelf is full again")

// ---------------------------------------------------------------------------------------------------------------------
// The panel, the wires, the emag, the bolts
// ---------------------------------------------------------------------------------------------------------------------

/// A screwdriver opens and shuts the service panel.
/datum/unit_test/dq_p2_vending/screwdriver_toggles_the_panel
/datum/unit_test/dq_p2_vending/screwdriver_toggles_the_panel/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	TEST_ASSERT(!p2v_panel_open(V), "shut to begin with")
	toggle_panel(H, V)
	TEST_ASSERT(p2v_panel_open(V), "the screwdriver opens it")
	toggle_panel(H, V)
	TEST_ASSERT(!p2v_panel_open(V), "and shuts it")

/// A cut wire and a pulsed wire change the vendor as they always did: contraband, shooting, electrifying, the ID scan.
/datum/unit_test/dq_p2_vending/wires_drive_the_vendor
/datum/unit_test/dq_p2_vending/wires_drive_the_vendor/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	p2v_wires_pulse(H, V, WIRE_CONTRABAND)
	TEST_ASSERT(p2v_categories(V) & CAT_HIDDEN, "the contraband wire pulsed shows the hidden products")
	p2v_wires_pulse(H, V, WIRE_CONTRABAND)
	TEST_ASSERT(!(p2v_categories(V) & CAT_HIDDEN), "and pulsed again hides them")
	p2v_wires_pulse(H, V, WIRE_CONTRABAND)
	p2v_wires_cut(H, V, WIRE_CONTRABAND)
	TEST_ASSERT(!(p2v_categories(V) & CAT_HIDDEN), "cutting it hides them for good")
	TEST_ASSERT(!p2v_shoot(V), "the vendor does not shoot")
	p2v_wires_pulse(H, V, WIRE_THROW_ITEM)
	TEST_ASSERT(p2v_shoot(V), "the shooting wire pulsed makes it shoot")
	p2v_wires_pulse(H, V, WIRE_THROW_ITEM)
	TEST_ASSERT(!p2v_shoot(V), "and pulsed again stops it")
	p2v_wires_cut(H, V, WIRE_THROW_ITEM)
	TEST_ASSERT(p2v_shoot(V), "cutting it makes it shoot")
	p2v_wires_mend(H, V, WIRE_THROW_ITEM)
	TEST_ASSERT(!p2v_shoot(V), "and mending it stops it")
	TEST_ASSERT_EQUAL(p2v_electrified(V), 0, "not electrified")
	p2v_wires_pulse(H, V, WIRE_ELECTRIFY)
	TEST_ASSERT_EQUAL(p2v_electrified(V), 1, "the electrify wire pulsed shocks (for thirty seconds)")
	p2v_wires_cut(H, V, WIRE_ELECTRIFY)
	TEST_ASSERT_EQUAL(p2v_electrified(V), 1, "cut, it shocks for good")
	p2v_wires_mend(H, V, WIRE_ELECTRIFY)
	TEST_ASSERT_EQUAL(p2v_electrified(V), 0, "mended, it stops")

/// The wire window opens for a multitool or wirecutters with the panel open, and not with it shut.
/datum/unit_test/dq_p2_vending/wire_window_needs_the_panel
/datum/unit_test/dq_p2_vending/wire_window_needs_the_panel/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	touch(H, V, tool(/obj/item/multitool))
	TEST_ASSERT_EQUAL(length(GLOB.p2v_wire_windows), 0, "a multitool on a closed panel opens no wires")
	toggle_panel(H, V)
	touch(H, V, tool(/obj/item/multitool))
	TEST_ASSERT(H in GLOB.p2v_wire_windows, "with the panel open it does")
	GLOB.p2v_wire_windows = null
	touch(H, V, tool(/obj/item/tool/wirecutters))
	TEST_ASSERT(H in GLOB.p2v_wire_windows, "and so do wirecutters")

/// A cryptographic sequencer shorts out the product lock, again and again, and each swipe spends a charge.
/datum/unit_test/dq_p2_vending/emag_is_repeatable
/datum/unit_test/dq_p2_vending/emag_is_repeatable/run_gate()
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/p2v_test/locked)
	var/mob/living/carbon/human/H = p2v_actor()
	var/obj/item/card/emag/card = allocate(/obj/item/card/emag, p2v_side_spot())
	card.uses = 5
	TEST_ASSERT(!p2v_emagged(V), "not emagged yet")
	touch(H, V, card)
	TEST_ASSERT(p2v_emagged(V), "the product lock is shorted")
	TEST_ASSERT_EQUAL(card.uses, 4, "one charge spent")
	touch(H, V, card)
	TEST_ASSERT_EQUAL(card.uses, 3, "a second swipe runs too and spends another")

/// A wrench bolts and unbolts the vendor after a short wait, and not with the panel open.
/datum/unit_test/dq_p2_vending/wrench_toggles_the_bolts
/datum/unit_test/dq_p2_vending/wrench_toggles_the_bolts/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	toggle_panel(H, V)
	touch(H, V, tool(/obj/item/tool/wrench))
	TEST_ASSERT(V.anchored, "an open panel refuses the wrench")
	toggle_panel(H, V)
	touch(H, V, tool(/obj/item/tool/wrench), 5 SECONDS)
	TEST_ASSERT(!V.anchored, "a wrench unbolts it")
	touch(H, V, tool(/obj/item/tool/wrench), 5 SECONDS)
	TEST_ASSERT(V.anchored, "and bolts it again")

// ---------------------------------------------------------------------------------------------------------------------
// Using it: the hand, an ID, cash, shocks
// ---------------------------------------------------------------------------------------------------------------------

/// An empty hand opens the window; with the panel open the wires open beside it.
/datum/unit_test/dq_p2_vending/hand_opens_the_window
/datum/unit_test/dq_p2_vending/hand_opens_the_window/run_gate()
	var/obj/machinery/vending/p2v_test/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	touch(H, V, null)
	TEST_ASSERT(H in V.p2v_opened, "the window opened")
	TEST_ASSERT_EQUAL(length(GLOB.p2v_wire_windows), 0, "and no wires with the panel shut")
	V.p2v_opened = null
	toggle_panel(H, V)
	touch(H, V, null)
	TEST_ASSERT(H in V.p2v_opened, "the window opens with the panel open too")
	TEST_ASSERT(H in GLOB.p2v_wire_windows, "and the wires open beside it")

/// An ID or cash held to the machine opens the window; any other item does not.
/datum/unit_test/dq_p2_vending/id_or_cash_opens_the_window
/datum/unit_test/dq_p2_vending/id_or_cash_opens_the_window/run_gate()
	var/obj/machinery/vending/p2v_test/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	var/obj/item/card/id/card = allocate(/obj/item/card/id, p2v_side_spot())
	touch(H, V, card)
	TEST_ASSERT(H in V.p2v_opened, "an ID opens it")
	V.p2v_opened = null
	var/obj/item/spacecash/c50/cash = allocate(/obj/item/spacecash/c50, p2v_side_spot())
	touch(H, V, cash)
	TEST_ASSERT(H in V.p2v_opened, "cash opens it")
	V.p2v_opened = null
	var/obj/item/flashlight/torch = allocate(/obj/item/flashlight, p2v_side_spot())
	touch(H, V, torch)
	TEST_ASSERT(!(H in V.p2v_opened), "a flashlight does not")

/// An unpowered or broken vendor opens no window to a hand.
/datum/unit_test/dq_p2_vending/inoperable_vendor_opens_no_window
/datum/unit_test/dq_p2_vending/inoperable_vendor_opens_no_window/run_gate()
	var/obj/machinery/vending/p2v_test/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	dq_machine_clear(V)
	V.set_grid_power(FALSE)
	touch(H, V, null)
	TEST_ASSERT(!(H in V.p2v_opened), "an unpowered vendor opens no window")
	dq_machine_clear(V)
	V.atom_break()
	touch(H, V, null)
	TEST_ASSERT(!(H in V.p2v_opened), "a broken vendor opens no window")

/// An electrified vendor shocks whoever touches it (the whole hit is a shock of certain chance); when the shock lands the window does not open, when it
/// does not (insulation) the window opens.
/datum/unit_test/dq_p2_vending/electrified_vendor_shocks_the_touch
/datum/unit_test/dq_p2_vending/electrified_vendor_shocks_the_touch/run_gate()
	var/obj/machinery/vending/p2v_test/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	touch(H, V, null)
	TEST_ASSERT_EQUAL(V.p2v_shocks, 0, "a vendor that is not electrified does not shock")
	TEST_ASSERT(H in V.p2v_opened, "and opens")
	V.p2v_opened = null
	p2v_set_electrified(V, 30 SECONDS)
	V.p2v_shock_result = 1
	touch(H, V, null)
	TEST_ASSERT_EQUAL(V.p2v_shocks, 1, "an electrified vendor shocks the touch")
	TEST_ASSERT(!(H in V.p2v_opened), "and a shock that lands opens nothing")
	V.p2v_shock_result = 0
	touch(H, V, null)
	TEST_ASSERT(V.p2v_shocks > 1, "it shocks again")
	TEST_ASSERT(H in V.p2v_opened, "and a shock that misses opens the window")

/// The shock wire pulsed electrifies the vendor for exactly thirty seconds (a timed hold); cut, until mended; an event's hold beside the wire's
/// is not overwritten by it; and an inoperable vendor is not live (the hold's clock still runs while it is down).
/datum/unit_test/dq_p2_vending/electrified_counts_down
/datum/unit_test/dq_p2_vending/electrified_counts_down/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	wires_pulse(V, WIRE_ELECTRIFY)
	TEST_ASSERT(p2v_electrified(V), "a pulse electrifies it")
	p2v_settle(29 SECONDS)
	TEST_ASSERT(p2v_electrified(V), "still live at 29 seconds")
	p2v_settle(2 SECONDS)
	TEST_ASSERT(!p2v_electrified(V), "and safe after 30")
	wires_cut(V, WIRE_ELECTRIFY)
	p2v_settle(60 SECONDS)
	TEST_ASSERT(p2v_electrified(V), "cut, it stays live")
	p2v_set_electrified(V, null)
	wires_mend(V, WIRE_ELECTRIFY)
	TEST_ASSERT(p2v_electrified(V), "mending the wire leaves the event's hold")
	release(V, STAT_ELECTRIFIED, SRC_ROUND_EVENT)
	TEST_ASSERT(!p2v_electrified(V), "released, it is safe")
	p2v_set_electrified(V, null)
	dq_machine_clear(V)
	V.set_grid_power(FALSE)
	TEST_ASSERT(!p2v_electrified(V), "an unpowered vendor shocks nobody")
	dq_machine_clear(V)
	TEST_ASSERT(p2v_electrified(V), "and is live again with power")

/// A vendor that shoots its stock throws a product at a living thing it can see, one frame in its chance.
/datum/unit_test/dq_p2_vending/shooting_vendor_throws_stock
/datum/unit_test/dq_p2_vending/shooting_vendor_throws_stock/run_gate()
	p2v_light_room()
	var/obj/machinery/vending/V = p2v_vendor()
	V.shoot_inventory_chance = 100
	p2v_actor(get_step(p2v_spot(), EAST))
	var/before = p2v_stock_total(V)
	p2v_set_shoot(V, TRUE)
	p2v_settle(10 SECONDS)
	var/after = p2v_stock_total(V)
	TEST_ASSERT(after < before, "stock was thrown")
	TEST_ASSERT(p2v_shoot(V), "and it goes on shooting")
	p2v_set_shoot(V, FALSE)
	var/stopped = after
	p2v_settle(10 SECONDS)
	TEST_ASSERT_EQUAL(p2v_stock_total(V), stopped, "until it is told to stop")

/// Throwing needs someone to throw at, and ignores one who is not there.
/datum/unit_test/dq_p2_vending/throw_item_needs_a_living_target
/datum/unit_test/dq_p2_vending/throw_item_needs_a_living_target/run_gate()
	p2v_light_room()
	var/obj/machinery/vending/V = p2v_vendor()
	var/before = p2v_stock_total(V)
	TEST_ASSERT(!V.throw_item(), "no one in view, nothing thrown")
	TEST_ASSERT_EQUAL(p2v_stock_total(V), before, "and nothing left the shelves")
	var/mob/living/carbon/human/H = p2v_actor(get_step(p2v_spot(), EAST))
	TEST_ASSERT(V.throw_item(H), "a named target is thrown at")
	TEST_ASSERT_EQUAL(p2v_stock_total(V), before - 1, "one product left the shelves")
	TEST_ASSERT(V.throw_item(), "someone in view is thrown at")
	TEST_ASSERT_EQUAL(p2v_stock_total(V), before - 2, "another product left the shelves")

/// A vendor that does not shoot, is not electrified and is quiet does not hold a timer's work (its frame does nothing to the stock).
/datum/unit_test/dq_p2_vending/quiet_vendor_leaves_its_stock_alone
/datum/unit_test/dq_p2_vending/quiet_vendor_leaves_its_stock_alone/run_gate()
	var/obj/machinery/vending/p2v_test/V = p2v_vendor()
	p2v_actor(get_step(p2v_spot(), EAST))
	var/datum/stored_item/vending_product/pen = p2v_record(V, /obj/item/pen)
	p2v_settle(30 SECONDS)
	TEST_ASSERT_EQUAL(pen.get_amount(), 3, "nothing was thrown")
	TEST_ASSERT_EQUAL(length(V.p2v_spoken), 0, "and nothing said")
	TEST_ASSERT_EQUAL(p2v_electrified(V), 0, "it is not electrified")

/// A talking vendor pitches its slogans (a frame in twenty), no more often than its delay, and not while it is quiet.
/datum/unit_test/dq_p2_vending/talker_pitches_its_slogans
/datum/unit_test/dq_p2_vending/talker_pitches_its_slogans/run_gate()
	var/obj/machinery/vending/p2v_test/V = p2v_vendor(/obj/machinery/vending/p2v_test/talker)
	COOLDOWN_RESET(V, slogan_cooldown)
	p2v_set_quiet(V, TRUE)
	p2v_settle(2 MINUTES)
	TEST_ASSERT_EQUAL(length(V.p2v_spoken), 0, "a quiet vendor says nothing")
	p2v_set_quiet(V, FALSE)
	p2v_settle(10 MINUTES)
	TEST_ASSERT(length(V.p2v_spoken) >= 1, "a loud one pitches")
	TEST_ASSERT(("Buy!" in V.p2v_spoken) || ("Buy more!" in V.p2v_spoken), "one of its slogans")

/// A vendor says its thank-you after a sale, at most once per delay and twenty seconds.
/datum/unit_test/dq_p2_vending/vend_says_thank_you
/datum/unit_test/dq_p2_vending/vend_says_thank_you/run_gate()
	var/obj/machinery/vending/p2v_test/V = p2v_vendor(/obj/machinery/vending/p2v_test/talker)
	p2v_set_quiet(V, TRUE)
	var/mob/living/carbon/human/H = p2v_actor()
	press(H, V, "vend", list("vend" = p2v_key(V, /obj/item/pen)))
	TEST_ASSERT_EQUAL(length(V.p2v_spoken), 1, "the thank-you was said")
	TEST_ASSERT_EQUAL(V.p2v_spoken[1], "Thanks!", "as set")
	press(H, V, "vend", list("vend" = p2v_key(V, /obj/item/pen)))
	TEST_ASSERT_EQUAL(length(V.p2v_spoken), 1, "and not again within its delay")

/// An unpowered vendor says nothing.
/datum/unit_test/dq_p2_vending/unpowered_vendor_is_silent
/datum/unit_test/dq_p2_vending/unpowered_vendor_is_silent/run_gate()
	var/obj/machinery/vending/p2v_test/V = p2v_vendor()
	dq_machine_clear(V)
	V.set_grid_power(FALSE)
	V.speak("hello")
	TEST_ASSERT_EQUAL(length(V.p2v_spoken), 0, "nothing was said")

// ---------------------------------------------------------------------------------------------------------------------
// Breaking, damage, looks
// ---------------------------------------------------------------------------------------------------------------------

/// Malfunctioning empties the first shelf onto the floor and breaks the vendor.
/datum/unit_test/dq_p2_vending/malfunction_dumps_a_shelf_and_breaks
/datum/unit_test/dq_p2_vending/malfunction_dumps_a_shelf_and_breaks/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	V.malfunction()
	TEST_ASSERT(p2v_broken(V), "it broke")
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/pen).get_amount(), 0, "the first shelf is empty")
	TEST_ASSERT_EQUAL(p2v_count_on_floor(V, /obj/item/pen), 3, "its stock is on the floor")
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/paper).get_amount(), 2, "the others are whole")

/// A welder does not repair a vendor's casing (the vendor has no repair tool).
/datum/unit_test/dq_p2_vending/welder_does_not_repair_the_vendor
/datum/unit_test/dq_p2_vending/welder_does_not_repair_the_vendor/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	V.atom_break()
	touch(H, V, dq_fueled_welder(p2v_side_spot()), 5 SECONDS)
	TEST_ASSERT(p2v_broken(V), "it is still broken")

/// A vendor shows its face; dark and broken faces replace it; an open panel lays its state over whichever.
/datum/unit_test/dq_p2_vending/look_follows_the_vendor_state
/datum/unit_test/dq_p2_vending/look_follows_the_vendor_state/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	var/datum/look/look = p2v_look(V)
	TEST_ASSERT(isnull(look.icon_state) || look.icon_state == "generic", "a working vendor shows its face")
	TEST_ASSERT(!("generic-panel" in look.overlays), "no panel state while shut")
	dq_machine_clear(V)
	V.set_grid_power(FALSE)
	look = p2v_look(V)
	TEST_ASSERT_EQUAL(look.icon_state, "generic-off", "no power: the dark face")
	dq_machine_clear(V)
	V.atom_break()
	look = p2v_look(V)
	TEST_ASSERT_EQUAL(look.icon_state, "generic-broken", "broken: the broken face")
	toggle_panel(H, V)
	look = p2v_look(V)
	TEST_ASSERT("generic-panel" in look.overlays, "an open panel lays its state over the face")

/// The brand intelligence event drives a vendor by its setters: loud and shooting, then quiet and not.
/datum/unit_test/dq_p2_vending/event_setters_drive_the_vendor
/datum/unit_test/dq_p2_vending/event_setters_drive_the_vendor/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	TEST_ASSERT(V.shut_up, "quiet to begin with")
	p2v_set_quiet(V, FALSE)
	p2v_set_shoot(V, TRUE)
	TEST_ASSERT(!V.shut_up && p2v_shoot(V), "loud and shooting")
	p2v_set_quiet(V, TRUE)
	p2v_set_shoot(V, FALSE)
	TEST_ASSERT(V.shut_up && !p2v_shoot(V), "quiet and not")

/// The speaker switch of the window flips with the panel open and does nothing with it shut.
/datum/unit_test/dq_p2_vending/speaker_switch_needs_the_panel
/datum/unit_test/dq_p2_vending/speaker_switch_needs_the_panel/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	press(H, V, "toggle_voice")
	TEST_ASSERT(V.shut_up, "the switch needs the panel")
	toggle_panel(H, V)
	press(H, V, "toggle_voice")
	TEST_ASSERT(!V.shut_up, "with the panel open it flips")
	press(H, V, "toggle_voice")
	TEST_ASSERT(V.shut_up, "and flips back")

/// A coin goes into a working vendor only: an unpowered or a broken one does not take it.
/datum/unit_test/dq_p2_vending/coin_needs_a_working_vendor
/datum/unit_test/dq_p2_vending/coin_needs_a_working_vendor/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	var/obj/item/coin/gold/coin = allocate(/obj/item/coin/gold, p2v_side_spot())
	dq_machine_clear(V)
	V.set_grid_power(FALSE)
	touch(H, V, coin)
	TEST_ASSERT_NULL(p2v_coin(V), "an unpowered vendor does not take a coin")
	dq_machine_clear(V)
	V.atom_break()
	touch(H, V, coin)
	TEST_ASSERT_NULL(p2v_coin(V), "a broken vendor does not take it")
	TEST_ASSERT_NOTEQUAL(coin.loc, V, "and the coin stays out")

/// A product is stocked into a vendor whatever its state: unpowered or broken, it takes what it sells.
/datum/unit_test/dq_p2_vending/stock_works_when_inoperable
/datum/unit_test/dq_p2_vending/stock_works_when_inoperable/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	var/datum/stored_item/vending_product/R = p2v_record(V, /obj/item/pen)
	dq_machine_clear(V)
	V.set_grid_power(FALSE)
	var/obj/item/pen/pen = allocate(/obj/item/pen, p2v_side_spot())
	touch(H, V, pen)
	TEST_ASSERT_EQUAL(R.get_amount(), 4, "an unpowered vendor is stocked")
	dq_machine_clear(V)
	V.atom_break()
	var/obj/item/pen/second = allocate(/obj/item/pen, p2v_side_spot())
	touch(H, V, second)
	TEST_ASSERT_EQUAL(R.get_amount(), 5, "a broken vendor is stocked too")

/// A cartridge refills only a vendor that works.
/datum/unit_test/dq_p2_vending/refill_needs_a_working_vendor
/datum/unit_test/dq_p2_vending/refill_needs_a_working_vendor/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	var/datum/stored_item/vending_product/R = p2v_record(V, /obj/item/pen)
	R.amount = 0
	var/obj/item/refill_cartridge/p2v/cart = allocate(/obj/item/refill_cartridge/p2v, p2v_side_spot())
	dq_machine_clear(V)
	V.set_grid_power(FALSE)
	touch(H, V, cart)
	TEST_ASSERT_EQUAL(R.get_amount(), 0, "an unpowered vendor is not refilled")
	dq_machine_clear(V)
	V.atom_break()
	touch(H, V, cart)
	TEST_ASSERT_EQUAL(R.get_amount(), 0, "a broken vendor is not refilled")
	TEST_ASSERT(!QDELETED(cart), "and the cartridge is kept")

/// A light blast (severity three) can jolt a vendor into malfunctioning; a stronger one does not make it malfunction (it damages it as it did).
/datum/unit_test/dq_p2_vending/light_blast_can_make_it_malfunction
/datum/unit_test/dq_p2_vending/light_blast_can_make_it_malfunction/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	for(var/i in 1 to 100)
		var/datum/damage_packet/packet = damage_packet(null, null, null, null, DAMAGE_PACKET_SILENT, 0, 0, null, DAMAGE_ENTRY_EXPLOSION, 2)
		V.receive_damage(packet)
		packet.release()
	TEST_ASSERT(!p2v_broken(V), "a blast of severity two never makes it malfunction")
	for(var/i in 1 to 100)
		if(p2v_broken(V))
			break
		var/datum/damage_packet/light = damage_packet(null, null, null, null, DAMAGE_PACKET_SILENT, 0, 0, null, DAMAGE_ENTRY_EXPLOSION, 3)
		V.receive_damage(light)
		light.release()
	TEST_ASSERT(p2v_broken(V), "a light blast, tried again and again, does")
	TEST_ASSERT_EQUAL(p2v_record(V, /obj/item/pen).get_amount(), 0, "and the malfunction dumped the first shelf")

/// A vendor deleted with a coin inside takes the coin with it.
/datum/unit_test/dq_p2_vending/deleted_vendor_takes_its_coin
/datum/unit_test/dq_p2_vending/deleted_vendor_takes_its_coin/run_gate()
	var/obj/machinery/vending/V = p2v_vendor()
	var/mob/living/carbon/human/H = p2v_actor()
	var/obj/item/coin/gold/coin = allocate(/obj/item/coin/gold, p2v_side_spot())
	touch(H, V, coin)
	TEST_ASSERT_EQUAL(p2v_coin(V), coin, "the coin is in")
	qdel(V)
	p2v_settle()
	TEST_ASSERT(QDELETED(coin), "the coin went with the vendor")

// ---------------------------------------------------------------------------------------------------------------------
// The NIFSoft shop: a vendor of its own kind
// ---------------------------------------------------------------------------------------------------------------------

/// The shop's contraband wire does nothing (the hidden stock needs an emag); its emag shows the hidden stock once.
/datum/unit_test/dq_p2_vending/nifsoft_shop_hides_its_contraband_from_wires
/datum/unit_test/dq_p2_vending/nifsoft_shop_hides_its_contraband_from_wires/run_gate()
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/nifsoft_shop)
	var/mob/living/carbon/human/H = p2v_actor()
	toggle_panel(H, V)
	p2v_wires_pulse(H, V, WIRE_CONTRABAND)
	TEST_ASSERT(!(p2v_categories(V) & CAT_HIDDEN), "pulsing the contraband wire shows nothing")
	var/obj/item/card/emag/card = allocate(/obj/item/card/emag, p2v_side_spot())
	card.uses = 5
	toggle_panel(H, V)
	touch(H, V, card)
	TEST_ASSERT(p2v_categories(V) & CAT_HIDDEN, "an emag shows the hidden software")
	TEST_ASSERT(p2v_emagged(V), "and shorts the lock")
	TEST_ASSERT_EQUAL(card.uses, 4, "at the cost of a charge")

/// The shop cannot throw software at anyone, and its malfunction breaks it without throwing stock.
/datum/unit_test/dq_p2_vending/nifsoft_shop_throws_nothing
/datum/unit_test/dq_p2_vending/nifsoft_shop_throws_nothing/run_gate()
	var/obj/machinery/vending/V = p2v_vendor(/obj/machinery/vending/nifsoft_shop)
	var/mob/living/carbon/human/H = p2v_actor(get_step(p2v_spot(), EAST))
	TEST_ASSERT(!V.throw_item(H), "nothing is thrown")
	V.malfunction()
	TEST_ASSERT(p2v_broken(V), "malfunctioning breaks it")

// ---------------------------------------------------------------------------------------------------------------------
// Wire helpers (they press the wire datum's own entry points: what the wire window's buttons call)
// ---------------------------------------------------------------------------------------------------------------------

/// The actor pulses a wire (the panel is opened first when it is shut; it is left as it was).
/datum/unit_test/dq_p2_vending/proc/p2v_wires_pulse(mob/living/carbon/human/H, obj/machinery/vending/V, wire)
	wires_pulse(V, wire, H)
	p2v_settle(0)

/datum/unit_test/dq_p2_vending/proc/p2v_wires_cut(mob/living/carbon/human/H, obj/machinery/vending/V, wire)
	wires_cut(V, wire, H)
	p2v_settle(0)

/datum/unit_test/dq_p2_vending/proc/p2v_wires_mend(mob/living/carbon/human/H, obj/machinery/vending/V, wire)
	wires_mend(V, wire, H)
	p2v_settle(0)
