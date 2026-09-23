// Combat mode (roadmap I6, doc/rewrite/interactions.md §12): the toggle, the
// resolver's hostile priority, the combat-mode requirement, and parity: every
// former intent outcome (help, disarm, grab, harm) is reached through the new
// controls, on humans and on simple mobs.

// ---- Fixtures ----

/datum/interaction/dq_combat_test
	category = INTERACTION_CAT_ATTACK
	default_action = INPUT_ACTION_USE
	effect = /obj/dq_combat_probe/proc/note_interaction

/datum/interaction/dq_combat_test/friendly
	id = "dq_combat_friendly"
	name = "Pat"
	priority = 10

/datum/interaction/dq_combat_test/hostile
	id = "dq_combat_hostile"
	name = "Kick"
	priority = 5
	tags = list(INTERACTION_TAG_HOSTILE)

/datum/interaction/dq_combat_test/needs_combat
	id = "dq_combat_needs_combat"
	name = "Smash"
	priority = 1
	default_action = null
	requires = list(REQ_COMBAT_MODE)

/datum/interaction/dq_combat_test/needs_peace
	id = "dq_combat_needs_peace"
	name = "Polish"
	priority = 1
	default_action = null
	requires = list(REQ_NO_COMBAT_MODE)

/obj/dq_combat_probe
	name = "combat probe"
	var/list/done = list()

/obj/dq_combat_probe/declare_interactions(list/into)
	..()
	into += list(
		/datum/interaction/dq_combat_test/friendly,
		/datum/interaction/dq_combat_test/hostile,
		/datum/interaction/dq_combat_test/needs_combat,
		/datum/interaction/dq_combat_test/needs_peace,
	)

/obj/dq_combat_probe/proc/note_interaction(mob/actor, obj/item/held, datum/interaction/interaction)
	done += interaction.id
	return TRUE

/// Test mobs have no HUD; unarmed attacks read the targeted zone from one.
/datum/unit_test/proc/dq_give_zone_sel(mob/M)
	if(!M.zone_sel)
		M.zone_sel = new /atom/movable/screen/zone_sel()
		M.zone_sel.selecting = BP_TORSO

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
	TEST_ASSERT_EQUAL(H.use_stance(), I_HELP, "combat mode off is the help outcome")

	H.combat_mode_key("toggle")
	TEST_ASSERT(H.combat_mode, "the toggle key turns combat mode on")
	TEST_ASSERT_EQUAL(H.use_stance(), I_HURT, "combat mode on is the harm outcome")
	H.combat_mode_key("on")
	TEST_ASSERT(H.combat_mode, "the on key keeps it on")
	H.combat_mode_key("off")
	TEST_ASSERT(!H.combat_mode, "the off key turns it off")

	H.set_combat_mode(TRUE)
	H.set_attack_variant(ATTACK_VARIANT_DISARM)
	TEST_ASSERT_EQUAL(H.use_stance(), I_DISARM, "a Disarm variant wins over combat mode")
	TEST_ASSERT(IS_DISARMING(H) && !IS_HARMING(H) && !IS_HELPING(H), "exactly one outcome holds")
	H.set_attack_variant(ATTACK_VARIANT_GRAB)
	TEST_ASSERT_EQUAL(H.use_stance(), I_GRAB, "so does a Grab variant")
	H.set_attack_variant(null)

	for(var/stance in list(I_HELP, I_DISARM, I_GRAB, I_HURT))
		H.set_use_stance(stance)
		TEST_ASSERT_EQUAL(H.use_stance(), stance, "set_use_stance([stance]) round-trips")
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
	TEST_ASSERT_EQUAL(try_interaction(H, probe, null, INPUT_ACTION_USE), INTERACTION_TRY_RAN, "Use runs an interaction")
	TEST_ASSERT_EQUAL(probe.done[length(probe.done)], "dq_combat_friendly", "with combat mode off the neutral interaction wins Use")

	H.set_combat_mode(TRUE)
	TEST_ASSERT_EQUAL(try_interaction(H, probe, null, INPUT_ACTION_USE), INTERACTION_TRY_RAN, "Use runs an interaction")
	TEST_ASSERT_EQUAL(probe.done[length(probe.done)], "dq_combat_hostile", "with combat mode on the hostile interaction wins Use, though its base priority is lower")

	var/datum/interaction_resolution/resolution = interactions_for(H, probe, null)
	TEST_ASSERT(INTERACTION(/datum/interaction/dq_combat_test/needs_combat) in resolution.available, "REQ_COMBAT_MODE passes in combat mode")
	TEST_ASSERT_EQUAL(resolution.blocked[INTERACTION(/datum/interaction/dq_combat_test/needs_peace)], "combat mode is on", "REQ_NO_COMBAT_MODE fails with a reason")
	H.set_combat_mode(FALSE)
	resolution = interactions_for(H, probe, null)
	TEST_ASSERT_EQUAL(resolution.blocked[INTERACTION(/datum/interaction/dq_combat_test/needs_combat)], "combat mode is off", "REQ_COMBAT_MODE fails with a reason")
	TEST_ASSERT(INTERACTION(/datum/interaction/dq_combat_test/needs_peace) in resolution.available, "REQ_NO_COMBAT_MODE passes out of combat mode")

	// Disarm and Grab are listed on living targets; combat mode orders them.
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, T)
	var/datum/interaction/disarm = INTERACTION(/datum/interaction/attack_variant/disarm)
	var/datum/interaction/grab = INTERACTION(/datum/interaction/attack_variant/grab)
	resolution = interactions_for(H, other, null)
	TEST_ASSERT((disarm in resolution.available) && (grab in resolution.available), "Disarm and Grab are offered on a living target")
	TEST_ASSERT(resolution.available.Find(grab) < resolution.available.Find(disarm), "out of combat mode Grab comes before the hostile Disarm")
	H.set_combat_mode(TRUE)
	resolution = interactions_for(H, other, null)
	TEST_ASSERT(resolution.available.Find(disarm) < resolution.available.Find(grab), "in combat mode the hostile Disarm comes first")
	resolution = interactions_for(H, H, null)
	TEST_ASSERT(!(disarm in resolution.available) && !(grab in resolution.available), "you can't Disarm or Grab yourself")

	var/datum/interaction_resolution/on_probe = interactions_for(H, probe, null)
	TEST_ASSERT(!(disarm in on_probe.available) && !(disarm in on_probe.blocked), "Disarm isn't offered on objects")

/// The Disarm and Grab keys are held: the variant lasts until release. The interactions are one Use.
/datum/unit_test/dq_combat_mode_variant_keys

/datum/unit_test/dq_combat_mode_variant_keys/Run()
	var/list/pair = dq_combat_pair(/mob/living/simple_mob/animal/passive/cow)
	var/mob/living/carbon/human/attacker = pair[1]
	var/mob/living/simple_mob/animal/passive/cow/cow = pair[2]
	attacker.attack_variant_key(ATTACK_VARIANT_DISARM)
	GLOB.input_router.route_click(attacker, cow, "left=1")
	TEST_ASSERT_EQUAL(attacker.attack_variant, ATTACK_VARIANT_DISARM, "the variant holds while the key is down")
	TEST_ASSERT(cow.weakened > 0, "the click arrived as a disarm (the cow is tipped)")
	attacker.attack_variant_key_release(ATTACK_VARIANT_GRAB)
	TEST_ASSERT_EQUAL(attacker.attack_variant, ATTACK_VARIANT_DISARM, "releasing the other key changes nothing")
	attacker.attack_variant_key_release(ATTACK_VARIANT_DISARM)
	TEST_ASSERT_NULL(attacker.attack_variant, "releasing the key clears the variant")

	var/list/pair2 = dq_combat_pair(/mob/living/carbon/human)
	var/mob/living/carbon/human/grabber = pair2[1]
	var/mob/living/target = pair2[2]
	TEST_ASSERT(run_chosen_interaction(grabber, target, "grab"), "the Grab interaction runs")
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
		TEST_ASSERT_EQUAL(attacker.use_stance(), I_HELP, "[target_type]: Use out of combat mode is the help outcome")
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
		TEST_ASSERT_EQUAL(G?.affecting, target, "[target_type]: the grab holds the target")
		TEST_ASSERT_NULL(attacker.attack_variant, "[target_type]: the variant is gone after the grab")
		qdel(G)

	// The Grab interaction from the Menu does the same.
	var/list/pair = dq_combat_pair(/mob/living/carbon/human)
	var/mob/living/carbon/human/attacker = pair[1]
	var/mob/living/target = pair[2]
	TEST_ASSERT(run_chosen_interaction(attacker, target, "grab"), "the Grab interaction runs from the Menu")
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
		victim.last_push_time = 0
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
	GLOB.input_router.route_click(attacker, cow, "left=1")
	attacker.attack_variant_key_release(ATTACK_VARIANT_DISARM)
	TEST_ASSERT(cow.weakened > 0, "the Disarm key tips a cow over")

	// The Disarm interaction from the Menu does the same.
	pair = dq_combat_pair(/mob/living/simple_mob/animal/passive/cow)
	attacker = pair[1]
	cow = pair[2]
	TEST_ASSERT(run_chosen_interaction(attacker, cow, "disarm"), "the Disarm interaction runs from the Menu")
	TEST_ASSERT(cow.weakened > 0, "and tips the cow over")

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
