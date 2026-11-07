// The ability list and its Abilities tab (code/content/abilities/): that items and species abilities register and unregister, that using one from
// the tab and from a hotkey slot does what the old HUD button did, that a refusal greys the entry with its reason, and that the player's order is
// kept. Written against the data the tab is sent and the procs its messages call, not a connected client's window.

/datum/unit_test/dq_ability_panel
	abstract_type = /datum/unit_test/dq_ability_panel

/datum/unit_test/dq_ability_panel/Run()
	test_driver_begin()
	run_gate()
	test_driver_end()

/datum/unit_test/dq_ability_panel/proc/run_gate()
	return

/// The first ability of `user` of this type, or null.
/datum/unit_test/dq_ability_panel/proc/ability_of(mob/user, type)
	for(var/datum/action/entry as anything in ordered_abilities(user))
		if(istype(entry, type))
			return entry
	return null

/// The row of the tab's data for `entry`, or null.
/datum/unit_test/dq_ability_panel/proc/row_of(mob/user, datum/action/entry)
	for(var/list/row as anything in ability_panel_data(user)["abilities"])
		if(row["ref"] == handle_text(handle_of(entry)))
			return row
	return null

/// An item's ability is on the list while the mob holds the item, shows the item's toggle state, and leaves with it.
/datum/unit_test/dq_ability_panel/item_pickup_and_drop

/datum/unit_test/dq_ability_panel/item_pickup_and_drop/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/flashlight/F = allocate(/obj/item/flashlight, test_floor())
	TEST_ASSERT_NULL(ability_of(H, /datum/action/item_action/toggle_flashlight), "nothing is listed before the flashlight is held")
	TEST_ASSERT(H.put_in_r_hand(F), "the human takes the flashlight")
	var/datum/action/entry = ability_of(H, /datum/action/item_action/toggle_flashlight)
	TEST_ASSERT_NOTNULL(entry, "holding the flashlight adds its ability to the list")
	var/list/row = row_of(H, entry)
	TEST_ASSERT_EQUAL(row["name"], "Toggle Flashlight", "the tab names it")
	TEST_ASSERT_EQUAL(row["category"], ABILITY_CATEGORY_ITEMS, "an item's ability is in the Items category")
	TEST_ASSERT_EQUAL(row["toggled"], FALSE, "the flashlight is off")
	TEST_ASSERT_NULL(row["refusal"], "and it can be used")
	F.switch_light(H)
	TEST_ASSERT_EQUAL(row_of(H, entry)["toggled"], TRUE, "switching the flashlight on shows on the entry")
	H.drop_from_inventory(F, test_floor())
	TEST_ASSERT_NULL(ability_of(H, /datum/action/item_action/toggle_flashlight), "dropping it removes its ability from the list")
	TEST_ASSERT_NULL(row_of(H, entry), "and from the tab")

/// A species' ability op (the shadekin's phase shift) is on the list while the mob has it, with the species' resource beside it.
/datum/unit_test/dq_ability_panel/species_grant

/datum/unit_test/dq_ability_panel/species_grant/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/action/op_ability/before = null
	for(var/datum/action/op_ability/entry in H.actions)
		if(entry.op_key == ABILITY_ID_SHADEKIN_PHASE_SHIFT)
			before = entry
	TEST_ASSERT_NULL(before, "a plain human has no phase shift")
	var/datum/shadekin/SK = H.add_shadekin(/datum/shadekin/full)
	TEST_ASSERT_NOTNULL(SK, "the human becomes a shadekin")
	var/datum/action/op_ability/phase = null
	for(var/datum/action/op_ability/entry in H.actions)
		if(entry.op_key == ABILITY_ID_SHADEKIN_PHASE_SHIFT)
			phase = entry
	TEST_ASSERT_NOTNULL(phase, "the granted phase shift joined the ability list")
	var/list/row = row_of(H, phase)
	TEST_ASSERT_EQUAL(row["name"], "Phase shift", "it carries the name of its button")
	TEST_ASSERT_EQUAL(row["category"], ABILITY_CATEGORY_SPECIES, "a species' ability is in the Species category")
	var/found_energy = FALSE
	for(var/list/resource as anything in ability_panel_data(H)["resources"])
		if(resource["name"] == "Energy")
			found_energy = TRUE
			TEST_ASSERT_EQUAL(resource["max"], round(SK.shadekin_get_max_energy()), "the energy bar is as large as the shadekin's energy")
	TEST_ASSERT(found_energy, "the shadekin's energy is shown with its abilities")
	H.remove_shadekin()
	var/still_there = FALSE
	for(var/datum/action/op_ability/entry in H.actions)
		if(entry.op_key == ABILITY_ID_SHADEKIN_PHASE_SHIFT)
			still_there = TRUE
	TEST_ASSERT(!still_there, "losing the shadekin state removes the ability")

/// Using an ability from the tab does what the old button did; a hotkey slot uses the ability standing in that place of the list.
/datum/unit_test/dq_ability_panel/trigger_from_tab_and_slot

/datum/unit_test/dq_ability_panel/trigger_from_tab_and_slot/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/flashlight/F = allocate(/obj/item/flashlight, test_floor())
	H.put_in_r_hand(F)
	var/datum/action/entry = ability_of(H, /datum/action/item_action/toggle_flashlight)
	TEST_ASSERT_NOTNULL(entry, "the flashlight gives its ability")
	TEST_ASSERT(H.use_ability_entry(entry, "tab"), "using the entry from the tab succeeds")
	TEST_ASSERT_EQUAL(F.on, TRUE, "the tab's button switched the light on")
	STATE_SET(H, cooldowns, next_click, 0) // the next press comes a click later
	var/slot = ordered_abilities(H).Find(entry)
	TEST_ASSERT(slot >= 1 && slot <= ABILITY_HOTKEY_SLOTS, "the flashlight stands in a hotkey slot")
	TEST_ASSERT_EQUAL(ability_in_slot(H, slot), entry, "the slot names the ability standing there")
	TEST_ASSERT(H.use_ability_slot(slot), "the slot's hotkey uses it")
	TEST_ASSERT_EQUAL(F.on, FALSE, "the hotkey switched the light off again")
	STATE_SET(H, cooldowns, next_click, 0)
	TEST_ASSERT_NULL(ability_in_slot(H, ABILITY_HOTKEY_SLOTS + 1), "there is no tenth slot")
	TEST_ASSERT_NULL(ability_in_slot(H, 0), "and no slot zero")
	var/emptied = ordered_abilities(H).len + 1
	if(emptied <= ABILITY_HOTKEY_SLOTS)
		TEST_ASSERT(!H.use_ability_slot(emptied), "a key for an empty slot does nothing")

/// An ability that cannot be used is greyed with the reason, and neither the tab nor a hotkey runs it.
/datum/unit_test/dq_ability_panel/refusal_is_shown_and_enforced

/datum/unit_test/dq_ability_panel/refusal_is_shown_and_enforced/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/flashlight/F = allocate(/obj/item/flashlight, test_floor())
	H.put_in_r_hand(F)
	var/datum/action/entry = ability_of(H, /datum/action/item_action/toggle_flashlight)
	TEST_ASSERT_NULL(row_of(H, entry)["refusal"], "a conscious human can use it")
	H.set_stat(UNCONSCIOUS)
	var/list/row = row_of(H, entry)
	TEST_ASSERT(istext(row["refusal"]) && length(row["refusal"]), "an unconscious human's entry carries the reason it cannot be used")
	TEST_ASSERT(!H.use_ability_entry(entry, "tab"), "the tab cannot use it")
	STATE_SET(H, cooldowns, next_click, 0)
	TEST_ASSERT(!H.use_ability_slot(ordered_abilities(H).Find(entry)), "and neither can the hotkey")
	TEST_ASSERT_EQUAL(F.on, FALSE, "so the light stayed off")

/// Only an ability the mob has can be used or reordered: a stranger's entry is refused.
/datum/unit_test/dq_ability_panel/strangers_ability_is_refused

/datum/unit_test/dq_ability_panel/strangers_ability_is_refused/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/flashlight/F = allocate(/obj/item/flashlight, test_floor())
	other.put_in_r_hand(F)
	var/datum/action/entry = ability_of(other, /datum/action/item_action/toggle_flashlight)
	TEST_ASSERT(!H.use_ability_entry(entry, "tab"), "someone else's ability cannot be used")
	TEST_ASSERT_EQUAL(F.on, FALSE, "so the light stayed off")
	TEST_ASSERT_NULL(ability_order_from_refs(H, list(handle_text(handle_of(entry)))), "and cannot be part of an order")

/// The saved order places the abilities it names first, in its order, and the rest by category.
/datum/unit_test/dq_ability_panel/order_follows_saved_list

/datum/unit_test/dq_ability_panel/order_follows_saved_list/run_gate()
	var/datum/action/item_action/toggle_flashlight/light = allocate(/datum/action/item_action/toggle_flashlight)
	var/datum/action/item_action/toggle_jetpack/pack = allocate(/datum/action/item_action/toggle_jetpack)
	var/datum/action/innate/mecha/mech_toggle_lights/species_power = allocate(/datum/action/innate/mecha/mech_toggle_lights)
	species_power.ability_category = ABILITY_CATEGORY_SPECIES
	var/list/gained = list(species_power, light, pack)
	var/list/by_default = ability_order_sorted(gained, null)
	TEST_ASSERT_EQUAL(by_default[1], light, "by default the items come first, in the order they were gained")
	TEST_ASSERT_EQUAL(by_default[2], pack, "the second item after the first")
	TEST_ASSERT_EQUAL(by_default[3], species_power, "and the species' abilities after the items")
	var/list/saved = list(pack.ability_id(), species_power.ability_id())
	var/list/by_saved = ability_order_sorted(gained, saved)
	TEST_ASSERT_EQUAL(by_saved[1], pack, "an ability the saved order names first is first")
	TEST_ASSERT_EQUAL(by_saved[2], species_power, "the next named is next, whatever its category")
	TEST_ASSERT_EQUAL(by_saved[3], light, "what is not named follows")
	var/list/stale = ability_order_sorted(gained, list("Items/something/gone", light.ability_id()))
	TEST_ASSERT_EQUAL(stale[1], light, "an id of an ability the mob no longer has is ignored")

/// Reordering saves the new order by id, keeps the ids of abilities not held now, survives the preference's round trip, and gives the same list again.
/datum/unit_test/dq_ability_panel/order_persists

/datum/unit_test/dq_ability_panel/order_persists/run_gate()
	var/datum/action/item_action/toggle_flashlight/light = allocate(/datum/action/item_action/toggle_flashlight)
	var/datum/action/item_action/toggle_jetpack/pack = allocate(/datum/action/item_action/toggle_jetpack)
	var/datum/action/item_action/toggle_magboots/boots = allocate(/datum/action/item_action/toggle_magboots)
	var/list/previous = list(boots.ability_id(), "Items/gone")
	var/list/saved = ability_order_to_save(list(pack, light), previous)
	TEST_ASSERT_EQUAL(saved[1], pack.ability_id(), "the dropped order comes first")
	TEST_ASSERT_EQUAL(saved[2], light.ability_id(), "in the order the player made")
	TEST_ASSERT(boots.ability_id() in saved, "an ability the player has now but did not move keeps a place")
	TEST_ASSERT("Items/gone" in saved, "so does one they do not have now")
	var/datum/preference/ability_order/entry = GLOB.preference_entries[/datum/preference/ability_order]
	TEST_ASSERT_NOTNULL(entry, "the order is a preference, so it is saved with the player")
	TEST_ASSERT_EQUAL(entry.savefile_identifier, PREFERENCE_PLAYER, "for the player, not a character")
	TEST_ASSERT(entry.is_valid(saved), "a saved order is a valid value")
	var/list/restored = entry.pref_deserialize(entry.pref_serialize(saved), null)
	TEST_ASSERT_EQUAL(jointext(restored, "|"), jointext(saved, "|"), "the order comes back from the savefile as it went in")
	TEST_ASSERT(!entry.is_valid("not a list"), "something that is not a list is refused")
	TEST_ASSERT_EQUAL(length(entry.pref_deserialize(list("a", "a", 5, ""), null)), 1, "junk and repeats are dropped when it is read")
	var/list/again = ability_order_sorted(list(light, pack, boots), restored)
	TEST_ASSERT_EQUAL(again[1], pack, "so the list comes out in the saved order again")
	TEST_ASSERT_EQUAL(again[2], light, "second")
	TEST_ASSERT_EQUAL(again[3], boots, "and the held ability that was not moved last")

/// A reorder message must name exactly the mob's abilities, each once; anything else is refused and changes nothing.
/datum/unit_test/dq_ability_panel/reorder_must_be_a_permutation

/datum/unit_test/dq_ability_panel/reorder_must_be_a_permutation/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/flashlight/F = allocate(/obj/item/flashlight, test_floor())
	H.put_in_r_hand(F)
	var/list/refs = list()
	for(var/datum/action/entry as anything in ordered_abilities(H))
		refs += handle_text(handle_of(entry))
	TEST_ASSERT(length(refs) >= 1, "the human has an ability")
	TEST_ASSERT_NOTNULL(ability_order_from_refs(H, refs), "the abilities it has are a valid order")
	var/list/reversed = list()
	for(var/ref in refs)
		reversed.Insert(1, ref)
	var/list/picked = ability_order_from_refs(H, reversed)
	TEST_ASSERT_EQUAL(handle_text(handle_of(picked[1])), refs[length(refs)], "the order the tab sent is the order that comes back")
	TEST_ASSERT_NULL(ability_order_from_refs(H, list()), "naming none is refused")
	TEST_ASSERT_NULL(ability_order_from_refs(H, refs + refs), "naming too many is refused")
	var/list/repeated = refs.Copy()
	repeated[length(repeated)] = refs[1]
	if(length(refs) > 1)
		TEST_ASSERT_NULL(ability_order_from_refs(H, repeated), "naming one twice is refused")
	TEST_ASSERT_NULL(ability_order_from_refs(H, "not a list"), "something that is not a list is refused")

/// The slot keybindings exist for slots one to nine, are rebindable like any other, and do not take a key another binding already has.
/datum/unit_test/dq_ability_panel/slot_keybindings

/datum/unit_test/dq_ability_panel/slot_keybindings/run_gate()
	for(var/slot in 1 to ABILITY_HOTKEY_SLOTS)
		var/datum/keybinding/binding = GLOB.keybindings[ABILITY_SLOT_KEYBIND(slot)]
		TEST_ASSERT_NOTNULL(binding, "slot [slot] has a keybinding the player can rebind")
		TEST_ASSERT_EQUAL(binding.command, ".use-ability-slot [slot]", "slot [slot]'s key uses the ability in slot [slot]")
		TEST_ASSERT_EQUAL(jointext(keybinding_keys(binding, KEYBIND_PROFILE_DEFAULT, null), ","), "ALT+[slot]", "slot [slot] is on ALT+[slot] by default")
	TEST_ASSERT_NULL(GLOB.keybindings[ABILITY_SLOT_KEYBIND(ABILITY_HOTKEY_SLOTS + 1)], "there is no tenth slot")
