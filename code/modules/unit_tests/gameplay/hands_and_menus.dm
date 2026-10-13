// Hands and the right-click menu: a player picks an item up with a click and drops it with the drop key; a wall's menu lists each
// choice once, and every choice it offers does something the player can see.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Click to pick up, swap hands, drop: the item follows.
/datum/unit_test/dq_gameplay/pick_up_and_drop

/datum/unit_test/dq_gameplay/pick_up_and_drop/play()
	var/mob/living/carbon/human/H = spawn_player(tile(2, 2))
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, tile(2, 3))
	TEST_ASSERT_NULL(H.get_active_hand(), "the player starts empty-handed")
	click(H, wrench)
	TEST_ASSERT_EQUAL(H.get_active_hand(), wrench, "clicking an item next to the player picks it up")
	TEST_ASSERT_EQUAL(wrench.loc, H, "the item is carried")
	var/image/in_hand = H.look_layers()[H.hand ? L_HAND_LAYER : R_HAND_LAYER]
	TEST_ASSERT(in_hand && draws_icon(H, in_hand.icon), "the held item is drawn in the player's hand")
	key_drop(H)
	TEST_ASSERT_NULL(H.get_active_hand(), "the drop key empties the hand")
	TEST_ASSERT_EQUAL(wrench.loc, H.loc, "the item lies at the player's feet")
	// Out of reach: a click two tiles away picks nothing up.
	var/obj/item/tool/crowbar/far = allocate(/obj/item/tool/crowbar, tile(2, 4))
	click(H, far)
	TEST_ASSERT_NULL(H.get_active_hand(), "an item two tiles away is out of reach")
	TEST_ASSERT_EQUAL(far.loc, tile(2, 4), "and stays where it is")

/// A wall's right-click menu: each line once, and each available line, picked, does something the player can observe (a message,
/// a question, a timed action, a change to the wall). A line that does nothing is a broken op.
/datum/unit_test/dq_gameplay/wall_menu

/datum/unit_test/dq_gameplay/wall_menu/play()
	var/list/spot = room_wall()
	TEST_ASSERT_NOTNULL(spot, "the test room has a wall beside its floor")
	var/turf/simulated/wall/W = spot[1]
	var/mob/living/carbon/human/H = spawn_player(spot[2])
	var/list/lines = menu_lines(H, W)
	TEST_ASSERT(length(lines), "the wall has a right-click menu")
	var/list/names = list()
	var/list/seen = list()
	for(var/list/line as anything in lines)
		names += line["name"]
		TEST_ASSERT(!seen[line["name"]], "the wall's menu lists \"[line["name"]]\" once: [json_encode(names)]")
		seen[line["name"]] = TRUE
	var/list/dead = list()
	for(var/list/line as anything in lines)
		if(!line["enabled"])
			continue
		var/what = did_something(H, W, line["id"])
		if(!what)
			dead += "[line["name"]] ([line["id"]])"
		else
			log_world("gameplay wall menu: [line["name"]] -> [what]")
	TEST_ASSERT(!length(dead), "menu lines that did nothing when picked: [jointext(dead, ", ")] (menu: [json_encode(names)])")

/// Picks `op_key` on `target` and returns what observably happened, or null for nothing.
/datum/unit_test/dq_gameplay/wall_menu/proc/did_something(mob/living/carbon/human/H, turf/target, op_key)
	var/chat_before = length(chat(H))
	var/prompts_before = length(GLOB.test_prompts)
	var/look_before = target.appearance
	var/type_before = target.type
	var/datum/op_result/R = menu_pick(H, target, op_key, wait = 0)
	var/busy = test_actor_busy(H)
	pass_time(1)
	cancel_open_prompts()
	if(!R)
		return null
	if(R.outcome == ACT_REFUSED)
		return length(chat(H)) > chat_before ? "refused with a message" : null
	if(length(chat(H)) > chat_before)
		return "a message: [chat(H)[length(chat(H))]]"
	if(length(GLOB.test_prompts) > prompts_before)
		return "a question"
	if(busy)
		return "a timed action"
	if(target.type != type_before || target.appearance != look_before)
		return "the wall changed"
	return null

#endif
