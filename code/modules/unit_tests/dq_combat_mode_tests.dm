// Combat mode (roadmap I6, doc/rewrite/interactions.md §12): the toggle, the
// resolver's hostile priority, stance-declared interactions, and parity: every
// former intent outcome (help, disarm, grab, harm) is reached through the new
// controls, on humans and on simple mobs.

// ---- Fixtures ----

/// Ops of a probe, to show combat mode ordering and stance: a neutral hand op, a hostile one, and menu ops declared for one stance each.
/obj/dq_combat_probe
	name = "combat probe"
	var/list/done = list()

CAPABILITIES(/obj/dq_combat_probe)
	op("dq_combat_friendly", hand(), priority(OP_PRIORITY_DEFAULT + 1), label("Pat"), then(PROC_REF(note_friendly)))
	op("dq_combat_hostile", hand(), hostile(), label("Kick"), then(PROC_REF(note_hostile)))
	op("dq_combat_needs_combat", menu(), stance(I_HURT), label("Smash"), then(PROC_REF(note_needs_combat)))
	op("dq_combat_needs_peace", menu(), stance(I_HELP), label("Polish"), then(PROC_REF(note_needs_peace)))

/obj/dq_combat_probe/proc/note_friendly(datum/act/op/A)
	LAZYADD(done, "dq_combat_friendly")
	return OP_OK

/obj/dq_combat_probe/proc/note_hostile(datum/act/op/A)
	LAZYADD(done, "dq_combat_hostile")
	return OP_OK

/obj/dq_combat_probe/proc/note_needs_combat(datum/act/op/A)
	LAZYADD(done, "dq_combat_needs_combat")
	return OP_OK

/obj/dq_combat_probe/proc/note_needs_peace(datum/act/op/A)
	LAZYADD(done, "dq_combat_needs_peace")
	return OP_OK

/// Test mobs have no HUD; unarmed attacks read the targeted zone from one.
/datum/unit_test/proc/dq_give_zone_sel(mob/M)
	if(!M.zone_sel)
		rel_set(M, nameof(/mob::zone_sel), new /atom/movable/screen/zone_sel())
		M.zone_sel.set_selecting(BP_TORSO)

/// An attacker and a target on adjacent open tiles, the attacker facing it.
/datum/unit_test/proc/dq_combat_pair(target_type)
	var/turf/base = _swing_arena()
	var/mob/living/carbon/human/attacker = allocate(/mob/living/carbon/human, base)
	var/mob/living/target = allocate(target_type, get_step(base, NORTH))
	dq_give_zone_sel(attacker)
	dq_give_zone_sel(target)
	attacker.set_dir(NORTH)
	attacker.next_click = 0
	return list(attacker, target)

// ---- The toggle ----

/datum/unit_test/dq_combat_mode_toggle

/datum/unit_test/dq_combat_mode_toggle/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT(!H.combat_mode, "mobs start with combat mode off")
	TEST_ASSERT_EQUAL(H.input_stance(), I_HELP, "combat mode off is the help outcome")

	H.combat_mode_key("toggle")
	TEST_ASSERT(H.combat_mode, "the toggle key turns combat mode on")
	TEST_ASSERT_EQUAL(H.input_stance(), I_HURT, "combat mode on is the harm outcome")
	H.combat_mode_key("on")
	TEST_ASSERT(H.combat_mode, "the on key keeps it on")
	H.combat_mode_key("off")
	TEST_ASSERT(!H.combat_mode, "the off key turns it off")

	H.set_combat_mode(TRUE)
	H.set_attack_variant(ATTACK_VARIANT_DISARM)
	TEST_ASSERT_EQUAL(H.input_stance(), I_DISARM, "a Disarm variant wins over combat mode")
	H.set_attack_variant(ATTACK_VARIANT_GRAB)
	TEST_ASSERT_EQUAL(H.input_stance(), I_GRAB, "so does a Grab variant")
	H.set_attack_variant(null)

	for(var/stance in list(I_HELP, I_DISARM, I_GRAB, I_HURT))
		H.set_use_stance(stance)
		TEST_ASSERT_EQUAL(H.input_stance(), stance, "set_use_stance([stance]) round-trips")
	H.set_use_stance(I_HELP)
	TEST_ASSERT(!H.combat_mode && !H.attack_variant, "the help stance clears both")

	// The HUD button shows the mode, and clicking it toggles.
	var/atom/movable/screen/combat_mode/button = new
	button.update_for(H)
	TEST_ASSERT_EQUAL(button.icon_state, "intent_help", "the button shows combat mode off")
	H.set_combat_mode(TRUE)
	button.update_for(H)
	TEST_ASSERT_EQUAL(button.icon_state, "intent_harm", "the button shows combat mode on")
	qdel(button)

// ---- The resolver and the requirement ----

/datum/unit_test/dq_combat_mode_resolver

/datum/unit_test/dq_combat_mode_resolver/Run()
	var/turf/T = test_floor()
	var/obj/dq_combat_probe/probe = allocate(/obj/dq_combat_probe, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	H.set_combat_mode(FALSE)
	var/datum/op_result/result = test_click(H, probe, null)
	TEST_ASSERT_EQUAL(result?.outcome, ACT_COMMITTED, "Use runs an op")
	TEST_ASSERT_EQUAL(probe.done[length(probe.done)], "dq_combat_friendly", "with combat mode off the neutral op wins Use")

	H.set_combat_mode(TRUE)
	H.next_click = 0
	result = test_click(H, probe, null)
	TEST_ASSERT_EQUAL(result?.outcome, ACT_COMMITTED, "Use runs an op")
	TEST_ASSERT_EQUAL(probe.done[length(probe.done)], "dq_combat_hostile", "with combat mode on the hostile op wins Use, though the other has the higher priority")

	TEST_ASSERT(dq_combat_menu_has(H, probe, "dq_combat_needs_combat"), "a harm-stance op is offered in combat mode")
	TEST_ASSERT(!dq_combat_menu_has(H, probe, "dq_combat_needs_peace"), "a help-stance op is not offered in combat mode")
	H.set_combat_mode(FALSE)
	TEST_ASSERT(!dq_combat_menu_has(H, probe, "dq_combat_needs_combat"), "a harm-stance op is not offered out of combat mode")
	TEST_ASSERT(dq_combat_menu_has(H, probe, "dq_combat_needs_peace"), "a help-stance op is offered out of combat mode")

	// Disarm and Grab are ops of a living target (attack_variants, combat_mode.dm); you can't Disarm or Grab yourself, and an object has neither.
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, T)
	var/datum/op_result/on_self = dq_attack_variant_result(H, H, ATTACK_VARIANT_DISARM)
	TEST_ASSERT_EQUAL(on_self?.outcome, ACT_REFUSED, "you can't Disarm yourself")
	on_self = dq_attack_variant_result(H, H, ATTACK_VARIANT_GRAB)
	TEST_ASSERT_EQUAL(on_self?.outcome, ACT_REFUSED, "you can't Grab yourself")
	TEST_ASSERT_NOTNULL(other, "a second living mob exists")
	var/datum/op_result/on_probe = dq_attack_variant_result(H, probe, ATTACK_VARIANT_DISARM)
	TEST_ASSERT_EQUAL(on_probe?.outcome, ACT_REFUSED, "Disarm isn't offered on objects")

/// Runs the Disarm or Grab op of `target` for `actor`, as the Menu does. TRUE if it committed.
/proc/dq_attack_variant_op(mob/actor, atom/target, variant)
	var/datum/op_result/result = dq_attack_variant_result(actor, target, variant)
	return result?.outcome == ACT_COMMITTED

/// The result of the Disarm or Grab op of `target` for `actor`, from the Menu.
/proc/dq_attack_variant_result(mob/actor, atom/target, variant)
	return perform_op(actor, target, variant == ATTACK_VARIANT_GRAB ? "attack_variants.grab" : "attack_variants.disarm", null, ORIGIN_MENU)

/// Is the op `key` in the menu `actor` gets for `target` (holding `held`), enabled? Stance-declared ops are listed only in their stance.
/datum/unit_test/proc/dq_combat_menu_has(mob/actor, atom/target, key, obj/item/held)
	for(var/list/row as anything in op_menu(actor, target, held))
		if(row["key"] == key)
			return row["enabled"] ? TRUE : FALSE
	return FALSE

/// The label of the op `key` in the menu `actor` gets for `target`, or null when it is not listed.
/datum/unit_test/proc/dq_combat_menu_label(mob/actor, atom/target, key, obj/item/held)
	for(var/list/row as anything in op_menu(actor, target, held))
		if(row["key"] == key)
			return row["label"]
	return null

/// A living target offers its defaults per stance (CAPABILITIES(/mob/living), combat_ai/integration/mob_living.dm): only the op
/// declared for the actor's stance is offered, the others are not listed.
/datum/unit_test/dq_combat_mode_living_stance_defaults

/datum/unit_test/dq_combat_mode_living_stance_defaults/Run()
	var/list/pair = dq_combat_pair(/mob/living/carbon/human)
	var/mob/living/carbon/human/attacker = pair[1]
	var/mob/living/target = pair[2]
	var/list/hand_names = list(I_HELP = "Help", I_DISARM = "Shove", I_GRAB = "Take hold", I_HURT = "Punch")
	var/list/item_names = list(I_HELP = "Use on", I_DISARM = "Shove with", I_GRAB = "Hold with", I_HURT = "Hit")
	var/list/hand_keys = list(I_HELP = "touch_help", I_DISARM = "touch_disarm", I_GRAB = "touch_grab", I_HURT = "touch_hurt")
	var/list/item_keys = list(I_HELP = "hit_help", I_DISARM = "hit_disarm", I_GRAB = "hit_grab", I_HURT = "hit_hurt")

	for(var/pass in 1 to 2)
		var/obj/item/held = null
		var/list/names = hand_names
		var/list/keys = hand_keys
		if(pass == 2)
			held = allocate(/obj/item, attacker.loc)
			TEST_ASSERT(attacker.put_in_active_hand(held), "the attacker holds an item")
			names = item_names
			keys = item_keys

		// Out of combat mode: the help default is offered, the others are not.
		attacker.set_use_stance(I_HELP)
		for(var/stance in names)
			if(stance == I_HELP)
				TEST_ASSERT(dq_combat_menu_has(attacker, target, keys[stance], held), "out of combat mode '[names[stance]]' is offered")
				TEST_ASSERT_EQUAL(dq_combat_menu_label(attacker, target, keys[stance], held), names[stance], "'[names[stance]]' is the label of the help default")
			else
				TEST_ASSERT_NULL(dq_combat_menu_label(attacker, target, keys[stance], held), "out of combat mode '[names[stance]]' is not offered")

		// In combat mode only the harm default is offered.
		attacker.set_combat_mode(TRUE)
		for(var/stance in names)
			if(stance == I_HURT)
				TEST_ASSERT(dq_combat_menu_has(attacker, target, keys[stance], held), "in combat mode '[names[stance]]' is offered")
				TEST_ASSERT_EQUAL(dq_combat_menu_label(attacker, target, keys[stance], held), names[stance], "'[names[stance]]' is the label of the harm default")
			else
				TEST_ASSERT_NULL(dq_combat_menu_label(attacker, target, keys[stance], held), "in combat mode '[names[stance]]' is not offered")
		attacker.set_use_stance(I_HELP)
		if(held)
			qdel(held)

/// The Disarm and Grab keys are held: the variant lasts until release. The interactions are one Use.
/datum/unit_test/dq_combat_mode_variant_keys

/datum/unit_test/dq_combat_mode_variant_keys/Run()
	var/list/pair = dq_combat_pair(/mob/living/simple_mob/animal/passive/cow)
	var/mob/living/carbon/human/attacker = pair[1]
	var/mob/living/simple_mob/animal/passive/cow/cow = pair[2]
	attacker.attack_variant_key(ATTACK_VARIANT_DISARM)
	test_click(attacker, cow) // the inbox, as a player's click arrives: the cow's op answers it (route_click() is the resolver's fallback for what no op takes)
	TEST_ASSERT_EQUAL(attacker.attack_variant, ATTACK_VARIANT_DISARM, "the variant holds while the key is down")
	TEST_ASSERT(cow.status_units(STAT_WEAKENED) > 0, "the click arrived as a disarm (the cow is tipped)")
	attacker.attack_variant_key_release(ATTACK_VARIANT_GRAB)
	TEST_ASSERT_EQUAL(attacker.attack_variant, ATTACK_VARIANT_DISARM, "releasing the other key changes nothing")
	attacker.attack_variant_key_release(ATTACK_VARIANT_DISARM)
	TEST_ASSERT_NULL(attacker.attack_variant, "releasing the key clears the variant")

	var/list/pair2 = dq_combat_pair(/mob/living/carbon/human)
	var/mob/living/carbon/human/grabber = pair2[1]
	var/mob/living/target = pair2[2]
	TEST_ASSERT(dq_attack_variant_op(grabber, target, ATTACK_VARIANT_GRAB), "the Grab interaction runs")
	TEST_ASSERT_NULL(grabber.attack_variant, "the interaction is one Use: no variant afterwards")
	TEST_ASSERT(istype(grabber.get_active_hand(), /obj/item/grab), "and it arrived as a grab")
	qdel(grabber.get_active_hand())

// ---- Parity: every intent outcome through the new controls ----

/// Help: combat mode off, Use. Reaches the help branch and neither hurts nor grabs.
/datum/unit_test/dq_combat_parity_help

/datum/unit_test/dq_combat_parity_help/Run()
	for(var/target_type in list(/mob/living/carbon/human, /mob/living/simple_mob/animal/passive/cow))
		var/list/pair = dq_combat_pair(target_type)
		var/mob/living/carbon/human/attacker = pair[1]
		var/mob/living/target = pair[2]
		var/before = target.injury_load(INJURY_CATEGORY_PHYSICAL)
		GLOB.input_router.route_click(attacker, target, "left=1")
		TEST_ASSERT_EQUAL(attacker.input_stance(), I_HELP, "[target_type]: Use out of combat mode is the help outcome")
		TEST_ASSERT_EQUAL(target.injury_load(INJURY_CATEGORY_PHYSICAL), before, "[target_type]: help does no harm")
		TEST_ASSERT(!istype(attacker.get_active_hand(), /obj/item/grab), "[target_type]: help does not grab")

/// Harm: combat mode on, Use. The target is hurt.
/datum/unit_test/dq_combat_parity_harm

/datum/unit_test/dq_combat_parity_harm/Run()
	for(var/target_type in list(/mob/living/carbon/human, /mob/living/simple_mob/animal/passive/cow))
		var/list/pair = dq_combat_pair(target_type)
		var/mob/living/carbon/human/attacker = pair[1]
		var/mob/living/target = pair[2]
		attacker.combat_mode_key("on")
		var/before = target.injury_load(INJURY_CATEGORY_PHYSICAL)
		// Unarmed blows can be blocked; a few tries make a hit certain.
		for(var/i in 1 to 10)
			attacker.next_click = 0
			GLOB.input_router.route_click(attacker, target, "left=1")
			if(target.injury_load(INJURY_CATEGORY_PHYSICAL) > before)
				break
		TEST_ASSERT(target.injury_load(INJURY_CATEGORY_PHYSICAL) > before, "[target_type]: Use in combat mode reaches the harm outcome")

/// Grab: the Grab key. The attacker holds a grab on the target.
/datum/unit_test/dq_combat_parity_grab

/datum/unit_test/dq_combat_parity_grab/Run()
	for(var/target_type in list(/mob/living/carbon/human, /mob/living/simple_mob/animal/passive/cow))
		var/list/pair = dq_combat_pair(target_type)
		var/mob/living/carbon/human/attacker = pair[1]
		var/mob/living/target = pair[2]
		attacker.attack_variant_key(ATTACK_VARIANT_GRAB)
		GLOB.input_router.route_click(attacker, target, "left=1")
		attacker.attack_variant_key_release(ATTACK_VARIANT_GRAB)
		var/obj/item/grab/G = attacker.get_active_hand()
		TEST_ASSERT(istype(G), "[target_type]: the Grab key grabs")
		TEST_ASSERT_EQUAL(G ? G?.grab_target() : null, target, "[target_type]: the grab holds the target")
		TEST_ASSERT_NULL(attacker.attack_variant, "[target_type]: the variant is gone after the grab")
		qdel(G)

	// The Grab interaction from the Menu does the same.
	var/list/pair = dq_combat_pair(/mob/living/carbon/human)
	var/mob/living/carbon/human/attacker = pair[1]
	var/mob/living/target = pair[2]
	TEST_ASSERT(dq_attack_variant_op(attacker, target, ATTACK_VARIANT_GRAB), "the Grab interaction runs from the Menu")
	TEST_ASSERT(istype(attacker.get_active_hand(), /obj/item/grab), "and grabs")
	qdel(attacker.get_active_hand())

/// Disarm: the Disarm key. A human drops what it holds; a cow is tipped over.
/datum/unit_test/dq_combat_parity_disarm

/datum/unit_test/dq_combat_parity_disarm/Run()
	var/list/pair = dq_combat_pair(/mob/living/carbon/human)
	var/mob/living/carbon/human/attacker = pair[1]
	var/mob/living/carbon/human/victim = pair[2]
	var/obj/item/held = allocate(/obj/item, victim.loc)
	TEST_ASSERT(victim.put_in_active_hand(held), "the victim holds something")
	// Each disarm knocks the item loose 60% of the time.
	for(var/i in 1 to 20)
		attacker.next_click = 0
		COOLDOWN_RESET(victim, push_lying_cooldown)
		COOLDOWN_RESET(victim, disarm_cooldown)
		attacker.attack_variant_key(ATTACK_VARIANT_DISARM)
		GLOB.input_router.route_click(attacker, victim, "left=1")
		attacker.attack_variant_key_release(ATTACK_VARIANT_DISARM)
		if(held.loc != victim)
			break
	TEST_ASSERT(held.loc != victim, "the Disarm key disarms a human")
	TEST_ASSERT_NULL(attacker.attack_variant, "the variant is gone after the disarm")

	pair = dq_combat_pair(/mob/living/simple_mob/animal/passive/cow)
	attacker = pair[1]
	var/mob/living/simple_mob/animal/passive/cow/cow = pair[2]
	attacker.attack_variant_key(ATTACK_VARIANT_DISARM)
	test_click(attacker, cow) // the inbox, as a player's click arrives: the cow's op answers it
	attacker.attack_variant_key_release(ATTACK_VARIANT_DISARM)
	TEST_ASSERT(cow.status_units(STAT_WEAKENED) > 0, "the Disarm key tips a cow over")

	// The Disarm interaction from the Menu does the same.
	pair = dq_combat_pair(/mob/living/simple_mob/animal/passive/cow)
	attacker = pair[1]
	cow = pair[2]
	TEST_ASSERT(dq_attack_variant_op(attacker, cow, ATTACK_VARIANT_DISARM), "the Disarm interaction runs from the Menu")
	TEST_ASSERT(cow.status_units(STAT_WEAKENED) > 0, "and tips the cow over")

/// Simple mobs use the same controls: combat mode on is the harm outcome for their own attacks.
/datum/unit_test/dq_combat_parity_simple_mob_attacker

/datum/unit_test/dq_combat_parity_simple_mob_attacker/Run()
	var/turf/base = _swing_arena()
	var/mob/living/simple_mob/animal/passive/mouse/mouse = allocate(/mob/living/simple_mob/animal/passive/mouse, get_step(base, NORTH))
	var/mob/living/simple_mob/animal/passive/cow/cow = allocate(/mob/living/simple_mob/animal/passive/cow, base)
	cow.melee_damage_lower = 5
	cow.melee_damage_upper = 5
	dq_give_zone_sel(cow)
	cow.set_dir(NORTH)
	cow.next_click = 0
	var/before = mouse.injury_load(INJURY_CATEGORY_PHYSICAL)
	GLOB.input_router.route_click(cow, mouse, "left=1")
	sleep(cow.melee_attack_delay + 2)
	TEST_ASSERT_EQUAL(mouse.injury_load(INJURY_CATEGORY_PHYSICAL), before, "a simple mob out of combat mode doesn't attack")
	cow.set_combat_mode(TRUE)
	for(var/i in 1 to 10)
		cow.next_click = 0
		GLOB.input_router.route_click(cow, mouse, "left=1")
		sleep(cow.melee_attack_delay + 2) // attack_target winds up asynchronously
		if(mouse.injury_load(INJURY_CATEGORY_PHYSICAL) > before)
			break
	TEST_ASSERT(mouse.injury_load(INJURY_CATEGORY_PHYSICAL) > before, "a simple mob in combat mode attacks")
