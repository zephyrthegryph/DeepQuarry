// The draw sweep's last forms (lane draw-final): looks drawn from tracked state, slots and relations, with no redraw call. Each test changes the
// state a draw reads and checks the look follows after the next flush.

/// A bottle of nail polish draws its cap state and the colour and top layers beneath it from its tracked `open` and `colour`.
/datum/unit_test/dq_draw_final_nailpolish_follows_cap_and_colour

/datum/unit_test/dq_draw_final_nailpolish_follows_cap_and_colour/Run()
	var/turf/T = test_floor()
	var/obj/item/nailpolish/N = allocate(/obj/item/nailpolish, T)
	refresh_flush()
	TEST_ASSERT_EQUAL(N.icon_state, "nailpolish", "closed")
	TEST_ASSERT_EQUAL(length(N.underlays), 2, "the colour and the top layer sit beneath the bottle")
	var/list/under_states = list()
	for(var/entry in N.underlays)
		var/mutable_appearance/MA = new(entry)
		under_states += "[MA.icon_state]"
	TEST_ASSERT(("color" in under_states) && ("top" in under_states), "the layers are the colour and the top: [json_encode(under_states)]")
	var/closed_key = N.rx?.look_key
	N.set_open(TRUE)
	refresh_flush()
	TEST_ASSERT_EQUAL(N.icon_state, "nailpolish-open", "opening it is a state, no redraw call")
	TEST_ASSERT_EQUAL(length(N.underlays), 2, "still two layers beneath")
	var/open_key = N.rx?.look_key
	TEST_ASSERT(open_key != closed_key, "the look changed with the cap")
	N.set_colour("#ff0000")
	refresh_flush()
	TEST_ASSERT(N.rx?.look_key != open_key, "a new colour redraws the layers")
	TEST_ASSERT(findtext(N.desc, "#ff0000"), "and is named in its description: [N.desc]")
	var/obj/item/nailpolish_remover/R = allocate(/obj/item/nailpolish_remover, T)
	refresh_flush()
	var/shut = R.icon_state
	R.set_open(TRUE)
	refresh_flush()
	TEST_ASSERT(R.icon_state != shut, "the remover's cap follows its tracked state too: [shut] -> [R.icon_state]")

/// A hardsuit's worn sheet is the species' sheet or its own default (none for a protean rig); nothing is cached from a redraw.
/datum/unit_test/dq_draw_final_rig_worn_sheet_is_computed

/datum/unit_test/dq_draw_final_rig_worn_sheet_is_computed/Run()
	var/obj/item/rig/R = allocate(/obj/item/rig, run_loc_floor_bottom_left)
	TEST_ASSERT_EQUAL(R.get_worn_icon_file(SPECIES_HUMAN, slot_back_str, null, FALSE), R.default_mob_icon, "the default sheet on the back")
	TEST_ASSERT_NULL(R.get_worn_icon_file(SPECIES_TESHARI, slot_back_str, null, FALSE), "a teshari has no sprite of it")
	R.default_mob_icon = null
	TEST_ASSERT_NULL(R.get_worn_icon_file(SPECIES_HUMAN, slot_back_str, null, FALSE), "a rig without a default sheet forces no sprite")

/// The chestpiece of a deployed suit shows the overlay of each installed module, and follows the module's own state.
/datum/unit_test/dq_draw_final_rig_chest_shows_module_overlays

/datum/unit_test/dq_draw_final_rig_chest_shows_module_overlays/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/rig/R = allocate(/obj/item/rig, T)
	var/obj/item/rig_module/stealth_field/M = allocate(/obj/item/rig_module/stealth_field, T)
	TEST_ASSERT(R.chest, "the suit has a chestpiece")
	rel_add(R, nameof(R.installed_modules), M)
	rel_set(R.chest, nameof(R.chest.master_rig), R)
	refresh_flush()
	TEST_ASSERT(("stealth_inactive" in dq_overlay_states(R.chest)), "the idle module is drawn on the chest: [json_encode(dq_overlay_states(R.chest))]")
	M.set_suit_overlay("stealth_active")
	refresh_flush()
	TEST_ASSERT(("stealth_active" in dq_overlay_states(R.chest)), "its state follows, no call: [json_encode(dq_overlay_states(R.chest))]")
	TEST_ASSERT(!("stealth_inactive" in dq_overlay_states(R.chest)), "and the old one is gone")

/// A mech shows its closed or open state with its pilot, and each piece of equipment adds its own layer, drawn from tracked state.
/datum/unit_test/dq_draw_final_mecha_follows_pilot_and_equipment

/datum/unit_test/dq_draw_final_mecha_follows_pilot_and_equipment/Run()
	var/turf/T = test_floor()
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	refresh_flush()
	var/base = mech.mecha_base_state()
	TEST_ASSERT_EQUAL(mech.icon_state, "[base]-open", "an empty mech is open")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(move_into(mech, MECHA_SLOT_PILOT, H), "the pilot gets in")
	refresh_flush()
	TEST_ASSERT_EQUAL(mech.icon_state, base, "a piloted mech is closed, with no update_icon() call")
	var/obj/item/mecha_parts/mecha_equipment/repair_droid/droid = allocate(/obj/item/mecha_parts/mecha_equipment/repair_droid, T)
	TEST_ASSERT(droid.can_attach(mech), "a repair droid fits")
	droid.attach(mech)
	refresh_flush()
	TEST_ASSERT(("repair_droid" in dq_overlay_states(mech)), "the droid is drawn on the hull: [json_encode(dq_overlay_states(mech))]")
	droid.set_repairing(TRUE)
	refresh_flush()
	TEST_ASSERT(("repair_droid_a" in dq_overlay_states(mech)), "it shows when it works: [json_encode(dq_overlay_states(mech))]")
	droid.detach()
	refresh_flush()
	TEST_ASSERT(!("repair_droid_a" in dq_overlay_states(mech)) && !("repair_droid" in dq_overlay_states(mech)), "and is gone with it: [json_encode(dq_overlay_states(mech))]")

// ---- the rock and the sand: the mineral turf draws from its masks (dq_turf_edges, code/game/turfs/turf_edges.dm) ----

/// A rock's lip toward an open side is drawn from the adjacency index's mask: opening the neighbour adds it, no call.
/datum/unit_test/dq_turf_edges/mineral_rock_lip_follows_the_open_side/Run()
	take_tiles()
	var/turf/simulated/mineral/A = make_first(/turf/simulated/mineral)
	make_second(/turf/simulated/mineral)
	TEST_ASSERT(!(A.rock_edges & EAST), "rock beside rock has no lip toward it: [A.rock_edges]")
	var/lips_before = overlays_showing(A, A.rock_side_icon_state)
	make_second(/turf/simulated/floor/plating)
	A = first_tile()
	TEST_ASSERT(A.rock_edges & EAST, "an open neighbour sets the side: [A.rock_edges]")
	TEST_ASSERT(overlays_showing(A, A.rock_side_icon_state) > lips_before, "and the lip is drawn on the rock")
	put_tiles_back()

/// Sand draws its edge against the rock beside it, and rock that is dug out becomes sand with its own name and sprite.
/datum/unit_test/dq_turf_edges/mineral_sand_follows_its_rock_and_the_dig/Run()
	take_tiles()
	var/turf/simulated/mineral/A = make_first(/turf/simulated/mineral/floor)
	make_second(/turf/simulated/mineral)
	A = first_tile()
	TEST_ASSERT(A.rock_edges & (EAST << ROCK_EDGE_DENSE_SHIFT), "the rock beside the sand is marked: [A.rock_edges]")
	TEST_ASSERT(overlays_showing(A, A.rock_side_icon_state) >= 1, "and its edge is drawn on the sand")
	TEST_ASSERT_EQUAL(A.name, A.floor_name, "sand is named sand")
	var/turf/simulated/mineral/B = make_first(/turf/simulated/mineral)
	TEST_ASSERT_EQUAL(B.icon_state, B.rock_icon_state, "rock draws the rock sprite")
	B.make_floor()
	settle()
	TEST_ASSERT_EQUAL(B.icon_state, B.sand_icon_state, "a dug-out rock draws the sand sprite, no update_icon() call")
	put_tiles_back()

/// Sand shows its dug mark only once it is dug, and the detail it rolled is a state of the decals file.
/datum/unit_test/dq_turf_edges/mineral_sand_shows_the_dug_mark_only_when_dug/Run()
	take_tiles()
	var/turf/simulated/mineral/A = make_first(/turf/simulated/mineral/floor)
	TEST_ASSERT(!A.sand_dug, "fresh sand is not dug: [A.sand_dug]")
	TEST_ASSERT_EQUAL(overlays_showing(A, "dug_overlay"), 0, "no dug mark: [json_encode(dq_overlay_states(A))]")
	A.set_sand_dug(1)
	settle()
	TEST_ASSERT_EQUAL(overlays_showing(A, "dug_overlay"), 1, "the dug mark follows, no call: [json_encode(dq_overlay_states(A))]")
	A.set_overlay_detail("asteroid3")
	settle()
	TEST_ASSERT_EQUAL(overlays_showing(A, "asteroid3"), 1, "the rolled detail is drawn from the decals file: [json_encode(dq_overlay_states(A))]")
	put_tiles_back()

/// A net or a jar draws what is in its slot: a creature entering or leaving redraws it, with no call.
/datum/unit_test/dq_draw_final_net_and_jar_follow_their_slot

/datum/unit_test/dq_draw_final_net_and_jar_follow_their_slot/Run()
	var/turf/T = test_floor()
	var/obj/item/material/fishing_net/N = allocate(/obj/item/material/fishing_net, T)
	var/mob/living/simple_mob/animal/passive/fish/F = allocate(/mob/living/simple_mob/animal/passive/fish, T)
	refresh_flush()
	TEST_ASSERT_EQUAL(N.icon_state, N.empty_state, "an empty net")
	F.forceMove(N)
	refresh_flush()
	TEST_ASSERT_EQUAL(N.icon_state, N.contain_state, "the net draws its catch from its slot")
	TEST_ASSERT(length(look_things_of(N)) == 1, "the slot holds the fish")
	F.forceMove(T)
	refresh_flush()
	TEST_ASSERT_EQUAL(N.icon_state, N.empty_state, "and lets it go")
	var/obj/item/glass_jar/J = allocate(/obj/item/glass_jar, T)
	var/obj/item/spacecash/C = allocate(/obj/item/spacecash, T)
	refresh_flush()
	C.forceMove(J)
	J.set_contains(JAR_MONEY)
	refresh_flush()
	TEST_ASSERT_EQUAL(length(J.underlays), 1, "the coin shows through the glass")
	C.forceMove(T)
	J.set_contains(JAR_NOTHING)
	refresh_flush()
	TEST_ASSERT_EQUAL(length(J.underlays), 0, "and is gone with it")

/// What the slot of a net or a jar holds, as the draw reads it.
/datum/unit_test/proc/look_things_of(atom/holder)
	var/slot = istype(holder, /obj/item/glass_jar) ? CONTAINER_SLOT_JAR : CONTAINER_SLOT_NET
	return holder.slot_contents(slot)

/// A pill bottle's wrapper follows its tracked colour (a chem master recolours it).
/datum/unit_test/dq_draw_final_pill_bottle_wrapper_follows_its_colour

/datum/unit_test/dq_draw_final_pill_bottle_wrapper_follows_its_colour/Run()
	var/turf/T = test_floor()
	var/obj/item/storage/pill_bottle/B = allocate(/obj/item/storage/pill_bottle, T)
	refresh_flush()
	TEST_ASSERT(!("pillbottle_wrap" in dq_overlay_states(B)), "a plain bottle has no wrapper")
	B.set_wrapper_color("#ff0000")
	refresh_flush()
	TEST_ASSERT(("pillbottle_wrap" in dq_overlay_states(B)), "a recoloured bottle shows it: [json_encode(dq_overlay_states(B))]")
	B.set_wrapper_color(null)
	refresh_flush()
	TEST_ASSERT(!("pillbottle_wrap" in dq_overlay_states(B)), "and clearing it takes it off")

/// A capture crystal shows its recharge as a state and the bound creature by where it is.
/datum/unit_test/dq_draw_final_capture_crystal_follows_recharge_and_contents

/datum/unit_test/dq_draw_final_capture_crystal_follows_recharge_and_contents/Run()
	var/turf/T = test_floor()
	var/obj/item/capture_crystal/C = allocate(/obj/item/capture_crystal, T)
	refresh_flush()
	TEST_ASSERT_EQUAL(C.icon_state, "inactive", "a crystal with nothing in it")
	C.set_recharging(TRUE)
	refresh_flush()
	TEST_ASSERT_EQUAL(C.icon_state, "inactive-busy", "recharging shows, with no call")
	C.set_recharging(FALSE)
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, T)
	rel_set(C, nameof(C.bound_mob), M)
	refresh_flush()
	TEST_ASSERT_EQUAL(C.icon_state, C.empty_icon, "a bound creature outside is an empty crystal")
	M.forceMove(C)
	refresh_flush()
	TEST_ASSERT_EQUAL(C.icon_state, C.full_icon, "inside it is a full one, no call: the crystal watches it")

/// A smartfridge's fill follows the amounts of its stock records, which publish their own changes.
/datum/unit_test/dq_draw_final_smartfridge_follows_its_records

/datum/unit_test/dq_draw_final_smartfridge_follows_its_records/Run()
	var/turf/T = test_floor()
	var/obj/machinery/smartfridge/F = allocate(/obj/machinery/smartfridge, T)
	refresh_flush()
	var/datum/stored_item/I = new /datum/stored_item(F, /obj/item/reagent_containers/food/snacks/candy, "candy", 0)
	rel_add(F, nameof(F.item_records), I)
	refresh_flush()
	var/empty_key = F.rx?.look_key
	I.set_amount(5)
	refresh_flush()
	TEST_ASSERT(F.rx?.look_key != empty_key, "a record's amount redraws the fridge with no call")
	I.set_amount(0) // nothing is left to be made when the fridge goes

/// The plain vars these draws read are tracked: a write redraws, and none of them asks.
/datum/unit_test/dq_draw_final_small_draws_follow_their_state

/datum/unit_test/dq_draw_final_small_draws_follow_their_state/Run()
	var/turf/T = test_floor()
	var/obj/item/sticky_pad/pad = allocate(/obj/item/sticky_pad, T)
	refresh_flush()
	var/full = pad.icon_state
	pad.set_papers(5)
	refresh_flush()
	TEST_ASSERT(pad.icon_state != full && pad.icon_state == "pad_empty", "a pad running out of notes: [full] -> [pad.icon_state]")
	var/obj/item/nif/N = allocate(/obj/item/nif, T)
	refresh_flush()
	var/before = N.icon_state
	N.set_stat(NIF_WORKING)
	refresh_flush()
	TEST_ASSERT(N.icon_state != before && N.icon_state == "nif_0", "a working NIF: [before] -> [N.icon_state]")
	var/obj/item/oldtwohanded/spear/S = allocate(/obj/item/oldtwohanded/spear, T)
	refresh_flush()
	var/unwielded = S.icon_state
	S.wield()
	refresh_flush()
	TEST_ASSERT(S.icon_state != unwielded, "a wielded spear: [unwielded] -> [S.icon_state]")
	var/obj/structure/panic_button/P = allocate(/obj/structure/panic_button, T)
	refresh_flush()
	var/intact = P.icon_state
	P.set_glass(FALSE)
	refresh_flush()
	TEST_ASSERT(P.icon_state != intact, "a smashed panic button: [intact] -> [P.icon_state]")
	var/obj/item/spaceflare/flare = allocate(/obj/item/spaceflare, T)
	refresh_flush()
	var/dark = flare.icon_state
	flare.set_active(1)
	refresh_flush()
	TEST_ASSERT(flare.icon_state != dark, "a lit flare: [dark] -> [flare.icon_state]")
	var/obj/structure/grille/G = allocate(/obj/structure/grille, T)
	refresh_flush()
	var/whole = G.icon_state
	G.set_destroyed(TRUE)
	refresh_flush()
	TEST_ASSERT(G.icon_state != whole, "a broken grille: [whole] -> [G.icon_state]")
	var/obj/machinery/readybutton/B = allocate(/obj/machinery/readybutton, T)
	refresh_flush()
	var/off = B.icon_state
	B.set_ready(1)
	refresh_flush()
	TEST_ASSERT(B.icon_state != off, "a pressed ready button: [off] -> [B.icon_state]")

/// A state called "color" beside a named `color =` is passed by name: BYOND reads the positional string "color" there as a key and the image comes out with no state.
/datum/unit_test/dq_draw_final_overlay_image_keeps_a_state_named_color

/datum/unit_test/dq_draw_final_overlay_image_keeps_a_state_named_color/Run()
	var/image/named = look_overlay_image(icon = 'icons/obj/nailpolish_vr.dmi', icon_state = "color", color = "#ff0000")
	TEST_ASSERT_EQUAL(named.icon_state, "color", "named state with a tint")
