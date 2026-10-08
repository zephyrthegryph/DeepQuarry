/**
 * Ripped from /tg/ with modifications.
 * unlucky.dm: For when you want someone to have a really bad day
 *
 * An omen makes a mob run the risk of all sorts of bad environmental
 * injuries, like nearby vending machines randomly falling on it, or hitting its head really hard
 * when it slips and falls.
 *
 * Omens end once the victim has used up its incidents (or on remove_omen()).
 *
 * A capability the mob grants itself: the omen's numbers live on the mob (omen_*), and its hooks react
 * to the moved, carbon_slip, moved_down_stairs, stun_effect and picked_up_item notices. Dice
 * (omen_roll_override()) and catches (omen_blocks_catch()) ask the mob directly. Add with L.add_omen().
 */
CAPABILITY_TYPE(omen, CAP_OMEN, /datum/capability/omen, key = NONE)
/datum/capability/omen

/datum/capability/omen/entries()
	return list(
		on_notice(/datum/notice/moved, then(CAP_PROC(omen_moved))),
		on_notice(/datum/notice/carbon_slip, then(CAP_PROC(omen_slipped))),
		on_notice(/datum/notice/moved_down_stairs, then(CAP_PROC(omen_stairs))),
		on_notice(/datum/notice/stun_effect, then(CAP_PROC(omen_stunned))),
		on_notice(/datum/notice/picked_up_item, then(CAP_PROC(omen_picked_up))),
	)

#define OMEN_TRAIT_SOURCE "omen"

/mob/living
	/// How many incidents are left. If 0 exactly, the omen ends.
	var/omen_incidents = INFINITY
	/// Base probability of negative events. Cursed are half as unlucky.
	var/omen_luck = 1
	/// Base damage from negative events. Cursed take 25% of this damage.
	var/omen_damage = 1
	/// If we want to do more evil events, such as spontaneous combustion
	var/omen_evil = TRUE
	/// If our codebase has safe disposals or not
	var/omen_safe_disposals = FALSE
	/// If we have vore interactions or not
	var/omen_vorish = TRUE

/// TRUE while the mob carries an omen.
/mob/living/proc/has_omen()
	return granted(src, /datum/capability/omen)

/**
 * Curses the mob. A second omen on an already cursed mob: this is a omen eat omen world!
 * The stronger omen survives (weaker, longer lasting omens take priority, but keep some of
 * the strength of the original).
 */
/mob/living/proc/add_omen(incidents_left = INFINITY, luck_mod = 1, damage_mod = 1, evil = TRUE, safe_disposals = FALSE, vorish = TRUE)
	if(!has_omen())
		omen_incidents = incidents_left
		omen_luck = luck_mod
		omen_damage = damage_mod
		omen_evil = evil
		omen_safe_disposals = safe_disposals
		omen_vorish = vorish
		grant(src, /datum/capability/omen, src)
		return
	// If we have more incidents left the new one is dropped.
	if(omen_incidents > incidents_left)
		return
	omen_incidents = incidents_left
	// The new omen is weaker than our current omen? Let's split the difference.
	if(omen_luck > luck_mod)
		omen_luck += luck_mod * 0.5
	if(omen_damage > damage_mod)
		omen_damage += damage_mod * 0.5
	// If the new omen has special modifiers, we take them on forever!
	if(evil)
		omen_evil = TRUE
	if(safe_disposals)
		omen_safe_disposals = TRUE
	if(vorish)
		omen_vorish = TRUE

/mob/living/proc/remove_omen()
	revoke(src, /datum/capability/omen, src)

/datum/capability/omen/on_activate(datum/activation/A)
	add_trait(A.holder, TRAIT_UNLUCKY, OMEN_TRAIT_SOURCE)

// Lifts the unlucky trait and tells the person.
/datum/capability/omen/on_deactivate(datum/activation/A)
	var/mob/living/person = A.holder
	remove_trait(person, TRAIT_UNLUCKY, OMEN_TRAIT_SOURCE)
	if(!QDELETED(person))
		to_chat(person, span_warning(span_green("You feel a horrible omen lifted off your shoulders!")))

/datum/capability/omen/proc/omen_moved(datum/act/A)
	var/mob/living/L = A.holder
	L.omen_check_accident(L)

/datum/capability/omen/proc/omen_slipped(datum/notice/carbon_slip/A)
	var/mob/living/L = A.holder
	L.omen_check_slip(L, A.stun_duration)

/datum/capability/omen/proc/omen_stairs(datum/act/A)
	var/mob/living/L = A.holder
	L.omen_check_stairs(L)

/datum/capability/omen/proc/omen_stunned(datum/notice/stun_effect/A)
	var/mob/living/L = A.holder
	L.omen_check_taser(L, A.stun_amount, A.agony_amount, A.def_zone, A.used_weapon, A.electric)

/datum/capability/omen/proc/omen_picked_up(datum/notice/picked_up_item/A)
	var/mob/living/L = A.holder
	L.omen_check_pickup(L, A.item)

/// The result an omen forces on a dice roll by this mob, or null (no omen, or luck held).
/mob/living/proc/omen_roll_override(obj/item/dice/the_dice, silent, result)
	if(!has_omen())
		return null
	return omen_check_roll(src, the_dice, silent, result)

/// TRUE when an omen makes this mob fumble a catch (the throw lands instead).
/mob/living/proc/omen_blocks_catch(source, speed)
	return has_omen() && omen_check_throw(src, source, speed)

/mob/living/proc/omen_consume()
	omen_incidents--
	if(omen_incidents < 1)
		remove_omen()

/**
 * check_accident() is called each step we take
 *
 * While we're walking around, roll to see if there's any environmental hazards on one of the adjacent tiles we can trigger.
 * We do the prob() at the beginning to A. add some tension for /when/ it will strike, and B. (more importantly) ameliorate the fact that we're checking up to 5 turfs's contents each time
 */
/mob/living/proc/omen_check_accident(atom/movable/our_guy)

	if(!isliving(our_guy) || isbelly(our_guy.loc))
		return

	var/mob/living/living_guy = our_guy
	if(living_guy.is_incorporeal()) //no being unlucky if you don't even exist on the same plane.
		return

	if(omen_evil && prob(0.0001) && (living_guy.stat != DEAD)) // 1 in a million
		act_message(living_guy, null, MSG_SELF(span_danger("You suddenly burst into flames!")), MSG_OTHERS(span_danger("%U% suddenly bursts into flames!")))
		living_guy.emote("scream")
		living_guy.adjust_fire_stacks(20)
		living_guy.ignite_mob()
		omen_consume()
		return

	var/effective_luck = omen_luck

	// If there's nobody to witness the misfortune, make it less likely.
	// This way, we allow for people to be able to get into hilarious situations without making the game nigh unplayable most of the time.

	var/has_watchers = FALSE
	for(var/mob/viewer in viewers(our_guy, world.view))
		if(viewer.client && !viewer.client.is_afk())
			has_watchers = TRUE
			break
	if(!has_watchers)
		effective_luck *= 0.5

	if(!prob(2 * effective_luck))
		return

	var/turf/our_guy_pos = get_turf(our_guy)
	if(!our_guy_pos)
		return
	if(omen_evil)
		for(var/obj/machinery/door/airlock/darth_airlock in turf_contents_of_type(our_guy_pos, /obj/machinery/door/airlock))
			if(is_bolted(darth_airlock) || !darth_airlock.power_systems_on())
				continue
			to_chat(living_guy, span_warning("The airlock suddenly closes on you!"))
			living_guy.status_at_least(STAT_PARALYZED, 5)
			living_guy.status_at_least(STAT_SLEEPING, 5)
			omen_slam_airlock(darth_airlock)
			omen_consume()
			return

	for(var/turf/the_turf as anything in our_guy_pos.AdjacentTurfs(check_blockage = FALSE)) //need false so we can check disposal units
		if(iswall(the_turf))
			continue
		if(the_turf.CanZPass(our_guy, DOWN) && !isspace(the_turf))
			to_chat(living_guy, span_warning("You lose your balance and slip towards the edge!"))
			living_guy.status_at_least(STAT_WEAKENED, 5)
			living_guy.throw_at(the_turf, 1, 20)
			omen_consume()
			return

		if(omen_vorish)
			for(var/mob/living/living_mob in the_turf)
				if(living_mob == our_guy || (living_mob.vore_selected == living_guy.vore_selected))
					continue //Don't do anything to ourselves.
				if(living_mob.stat)
					continue
				if(!can_stumble_vore(living_guy, living_mob) && !can_stumble_vore(living_mob, living_guy)) //Works both ways! Either way, someone's getting eaten!
					continue
				living_mob.stumble_into(living_guy) //logic reversed here because the game is DUMB. This means that living_guy is stumbling into the target!
				act_message(living_guy, living_mob, MSG_SELF(span_boldwarning("You lose your balance, slipping into %T%!")), \
					MSG_OTHERS(span_danger("%U% loses their balance and slips into %T%!")))
				omen_consume()
				return

		for(var/obj/machinery/washing_machine/evil_washer in the_turf)
			if(evil_washer.state == 1) //Empty and open door
				our_guy.visible_message(span_danger("[our_guy] slips near the [evil_washer] and falls in, the door shutting!"), span_boldwarning("You slip on a wet spot near the [evil_washer] and fall in, the door shutting! You're stuck!"))
				move_into(evil_washer, nameof(evil_washer.washing), our_guy)
				evil_washer.set_state(4)
				evil_washer.visible_message(span_danger("[evil_washer] begins its spin cycle!"))
				evil_washer.start(TRUE, omen_damage)
				omen_consume()
				return

		if((omen_evil || omen_safe_disposals) && living_guy.m_intent == I_RUN) //On servers without safe disposals, this is a death sentence. With servers with safe disposals, it's just funny. Either way, walk near disposals.
			for(var/obj/machinery/disposal/evil_disposal in the_turf)
				if(!evil_disposal.operable())
					continue
				if(evil_disposal.loc == living_guy.loc) //Let's not do a continual loop of them falling into it as soon as they climb out, as funny as that is.
					continue
				our_guy.visible_message(span_danger("[our_guy] slips on a spill near the [evil_disposal] and falls in!"), span_boldwarning("You slip on a spill near the [evil_disposal] and fall in!"))
				living_guy.forceMove(evil_disposal)
				evil_disposal.set_flush(TRUE)
				living_guy.status_at_least(STAT_STUNNED, 5)
				omen_consume()
				return

		if(omen_evil && prob(33)) //This has an additional 2 in 3 chance to not happen as there's a LOT of lights on stations. This should be rarer.
			for(var/obj/machinery/light/evil_light in the_turf)
				if((evil_light.status == LIGHT_BURNED || evil_light.status == LIGHT_BROKEN) || (living_guy.get_shock_protection() == 1)) // we can't do anything :(
					to_chat(living_guy, span_warning("[evil_light] sparks weakly for a second."))
					fx_sparks(evil_light, 4, FALSE)
					//We don't clear the omen as nothing really happened.
					break

				to_chat(living_guy, span_warning("[evil_light] glows ominously...")) // ominously
				evil_light.visible_message(span_boldwarning("[evil_light] suddenly flares brightly and sparks!"))
				//evil_light.broken(skip_sound_and_sparks = FALSE) //Let's not break it actually.
				evil_light.Beam(living_guy, icon_state = "lightning[rand(1,12)]", time = 0.5 SECONDS)
				living_guy.electrocute_act(35 * (omen_damage * 0.5), evil_light, stun = TRUE) //Stun is binary and scales on damage..Lame.
				living_guy.emote("scream")
				omen_consume()
				return

		for(var/obj/machinery/vending/darth_vendor in the_turf)
			if(!darth_vendor.operable())
				continue
			darth_vendor.visible_message(span_warning("[darth_vendor] suddenly clunks and the delivery chute raises up!"))
			darth_vendor.throw_item(living_guy)
			omen_consume()
			return

		for(var/obj/structure/mirror/evil_mirror in the_turf)
			to_chat(living_guy, span_warning("You pass by the mirror and glance at it..."))
			if(evil_mirror.shattered)
				to_chat(living_guy, span_notice("You feel lucky, somehow."))
				return
			var/mirror_rand
			if(omen_evil)
				mirror_rand = rand(1,5)
			else
				mirror_rand = rand(1,3)
			switch(mirror_rand)
				if(1)
					to_chat(living_guy, span_boldwarning("You see your reflection, but it is grinning malevolently and staring directly at you!"))
					living_guy.emote("scream")
				if(2 to 3)
					to_chat(living_guy, span_large(span_cult("Oh god, you can't see your reflection!!")))
					living_guy.emote("scream")
				if(4 to 5)
					to_chat(living_guy, span_warning("The mirror explodes into a million pieces! Wait, does that mean you're even more unlucky?"))
					evil_mirror.shatter()
					if(prob(50 * effective_luck)) // sometimes
						omen_luck += 0.25
						omen_damage += 0.25
					var/max_health_coefficient = (living_guy.get_endurance() * 0.06)
					for(var/obj/item/organ/external/limb in living_guy.organs)
						living_guy.injure(INJURY_CUT, max_health_coefficient * omen_damage, limb.organ_tag, evil_mirror)

			living_guy.status_adjust(STAT_JITTERY, 250)
			if(omen_evil && prob(7 * effective_luck))
				to_chat(living_guy, span_warning("You are completely shocked by this turn of events!"))
				if(ishuman(living_guy))
					var/mob/living/carbon/human/human_guy = living_guy
					if(human_guy.should_have_organ(O_HEART))
						for(var/obj/item/organ/internal/heart/heart in human_guy.internal_organ_list())
							heart.bruise() //Closest thing we have to a heart attack.
						to_chat(living_guy, span_boldwarning("You clutch at your heart!"))

			omen_consume()
			return
		if(omen_evil)
			for(var/obj/item/reagent_containers/glass/beaker/evil_beaker in the_turf)
				if(!evil_beaker.is_open_container() && (evil_beaker.reagents.total_volume > 0)) //A closed beaker is a safe beaker!
					continue
				act_message(living_guy, null, MSG_SELF(span_bolddanger("[evil_beaker] spills all over you!")), \
					MSG_OTHERS(span_danger("[evil_beaker] tilts, spilling its contents on %U%!")))
				evil_beaker.balloon_alert_visible("[evil_beaker]'s contents splashes onto [living_guy]!")
				evil_beaker.reagents.splash(living_guy, evil_beaker.reagents.total_volume)
				omen_consume()
				return

		for(var/obj/structure/table/evil_table in the_turf)
			if(!evil_table.material()) //We only want tables, not just table frames.
				continue
			if(!prob(10)) //Reduce the chance further, due to the number of tables that are passed in normal play.
				continue
			act_message(living_guy, evil_table, MSG_SELF(span_bolddanger("You stub your toe on %T%!")), \
				MSG_OTHERS(span_danger("%U% stubs %THEIR% toe on %T%!")))
			living_guy.injure(INJURY_BLUNT, 2 * omen_damage, pick(BP_L_FOOT, BP_R_FOOT), evil_table)
			living_guy.injure(INJURY_PAIN, 25) //It REALLY hurts.
			living_guy.status_at_least(STAT_WEAKENED, 3)
			omen_consume()
			return
	//Ran out of turf options. Let's do more generic options.

	if(prob(omen_luck * 5))
		// In complete darkness
		if(our_guy_pos.get_lumcount() <= LIGHTING_SOFT_THRESHOLD)
			living_guy.status_at_least(STAT_BLINDED, 5) //10 seconds of 'OH GOD WHAT'S HAPPENING'
			living_guy.status_at_least(STAT_MUTED, 5)
			living_guy.status_at_least(STAT_PARALYZED, 5)
			to_chat(living_guy, span_bolddanger("You feel the ground buckle underneath you, falling down, your vision going dark as you feel paralyzed in place!"))
			omen_consume()
			return

/mob/living/proc/omen_slam_airlock(obj/machinery/door/airlock/darth_airlock)
	. = darth_airlock.close(forced = TRUE, ignore_safties = TRUE, crush_damage = 15) //Not enough to cause any IB or massively injured organs.
	if(.)
		omen_consume()

/// If we get knocked down, see if we have a really bad slip and bash our head hard
/mob/living/proc/omen_check_slip(mob/living/our_guy, amount)

	if(prob(30)) // AAAA
		our_guy.emote("scream")
		to_chat(our_guy, span_cult("What a horrible night... To have a curse!"))

	if(prob(30 * omen_luck) && our_guy.get_bodypart_name(BP_HEAD)) /// Bonk!
		play_sfx(our_guy, SFX_EFFECTS_TABLEHEADSMASH)
		act_message(our_guy, null, MSG_SELF(span_bolddanger("You hit your head really badly falling down!")), \
			MSG_OTHERS(span_danger("%U% hits %THEIR% head really badly falling down!")))
		var/max_health_coefficient = (our_guy.get_endurance() * 0.5)
		our_guy.injure(INJURY_BLUNT, max_health_coefficient * omen_damage, BP_HEAD)
		if(ishuman(our_guy))
			var/mob/living/carbon/human/human_guy = our_guy
			if(human_guy.should_have_organ(O_BRAIN))
				for(var/obj/item/organ/internal/brain/brain in human_guy.internal_organ_list())
					human_guy.injure(INJURY_NEURAL, 30 * omen_damage, brain, src) //60 damage kills.
			if(human_guy.get_equipped_item(SLOT_ID_EYES) && human_guy.canUnEquip(human_guy.get_equipped_item(SLOT_ID_EYES)))
				var/turf/T = get_turf(human_guy)
				if(T)
					var/obj/item/our_glasses = human_guy.get_equipped_item(SLOT_ID_EYES)
					human_guy.unEquip(human_guy.get_equipped_item(SLOT_ID_EYES), target = T)
					to_chat(human_guy, span_warning("Your glasses fly off as you hit the ground!"))
					our_glasses.throw_at_random(FALSE, 3, 2)
		omen_consume()

	return

/mob/living/proc/omen_check_roll(mob/living/unlucky_soul, obj/item/dice/the_dice, silent, result)
	if(prob(20 * omen_luck))
		//unlucky_soul.visible_message(span_danger("[unlucky_soul] rolls [the_dice] with it landing on the edge of [result] before tilting over!"), span_boldwarning("You feel dreadfully unlucky as you roll the dice!"))
		//I had thought about making this have a notice that it happened.
		//However, gaslighting the user by providing no visible notice is MUCH funnier.
		return 1 // We override the roll to a 1.

///Returns TRUE and stops us from catching
/mob/living/proc/omen_check_throw(mob/living/unlucky_soul, source, speed)
	if(prob(30 * omen_luck)) //~9% chance
		if(istype(source, /obj/item/grenade))
			var/obj/item/grenade/bad_grenade = source
			if(bad_grenade.active)
				unlucky_soul.put_in_active_hand(bad_grenade)
				act_message(unlucky_soul, src, MSG_SELF(span_bolddanger("You catch [source] and it goes off in your hand!")), \
					MSG_OTHERS(span_warning("%T% catches [source] as it goes off in their hand!")))
				unlucky_soul.throw_mode_off()
				bad_grenade.detonate()
				return TRUE
		else
			act_message(unlucky_soul, null, others = span_attack("%U% tries to catch [source] and fumbles it, getting thrown back!"))
			unlucky_soul.status_at_least(STAT_WEAKENED, 5)
			return TRUE

/*
 * Dynamic injury system for when you pick up objects!
 * Some objects might cut, burn, or otherwise injure you if you pick them up!
 * Genenerally more of an annoyance than anything.
 * Variables that can be changed:
 * damage_to_inflict, damage_type, injury_verb, is_sharp, is_edge.
*/
/mob/living/proc/omen_check_pickup(mob/living/unlucky_soul, obj/item/item)
	if(prob(3 * omen_luck) && ishuman(unlucky_soul)) // ~3% chance
		var/mob/living/carbon/human/unlucky_human = unlucky_soul

		///How much damage we'll inflect.
		var/damage_to_inflict = 0

		///What we'll inflict (a paper cut by default).
		var/injury_kind = INJURY_CUT

		///What verb we use to describe the injury.
		var/injury_verb = "cuts"

		///What hand we are currently using, so we injure the correct one.
		var/current_hand = BP_R_HAND
		if(unlucky_human.hand)
			current_hand = BP_L_HAND

		if(istype(item, /obj/item/paper))
			injury_verb = "cuts"
			damage_to_inflict = 2

		else if(istype(item, /obj/item/material/knife))
			var/obj/item/material/knife = item

			injury_verb = "cuts"
			injury_kind = knife.injury_kind
			damage_to_inflict = knife.force

		else if(istype(item, /obj/item/material/shard))
			var/obj/item/material/shard/shard = item

			injury_verb = "cuts"
			injury_kind = shard.injury_kind
			damage_to_inflict = shard.force

		else if(istype(item, /obj/item/flame/lighter))
			var/obj/item/flame/lighter/lighter = item
			if(!lighter.lit)
				return

			injury_verb = "burns"
			injury_kind = INJURY_BURN
			damage_to_inflict = 5

		else if(istype(item, /obj/item/tool/transforming/jawsoflife))
			var/obj/item/tool/transforming/jawsoflife/jaws = item

			injury_verb = "clamps"
			injury_kind = jaws.injury_kind
			damage_to_inflict = jaws.force

		else if(istype(item, /obj/item/tool/screwdriver))
			var/obj/item/tool/screwdriver/screwdriver = item

			injury_verb = "stabs"
			injury_kind = screwdriver.injury_kind
			damage_to_inflict = screwdriver.force

		else if(istype(item, /obj/item/tool/wirecutters))
			var/obj/item/tool/wirecutters/wirecutters = item

			injury_verb = "nips"
			injury_kind = wirecutters.injury_kind
			damage_to_inflict = wirecutters.force

		if(!damage_to_inflict)
			return

		act_message(unlucky_human, null, others = span_danger("%U% accidentally [injury_verb] %THEIR% hand on [item]!"))
		unlucky_human.injure(injury_kind, damage_to_inflict * omen_damage, current_hand, item)

/mob/living/proc/omen_check_stairs(mob/living/unlucky_soul)
	if(prob(3 * omen_luck)) /// Bonk!
		play_sfx(unlucky_soul, SFX_EFFECTS_TABLEHEADSMASH)
		act_message(unlucky_soul, null, MSG_SELF(span_bolddanger("A stair gives way and you trip to the bottom!")), \
			MSG_OTHERS(span_danger("One of the stairs give way as %U% steps onto it, tumbling them down to the bottom!")))
		var/max_health_coefficient = (unlucky_soul.get_endurance() * 0.09)
		for(var/obj/item/organ/external/limb in unlucky_soul.organs) //In total, you should have 11 limbs (generally, unless you have an amputation). The full omen variant we want to leave you at 1 hp, the trait version less. As of writing, the trait version is 25% of the damage, so you take 24.75 across all limbs.
			unlucky_soul.injure(INJURY_BLUNT, max_health_coefficient * omen_damage, limb.organ_tag)
		unlucky_soul.status_at_least(STAT_WEAKENED, 5)
		omen_consume()

/mob/living/proc/omen_check_taser(mob/living/unlucky_soul, stun_amount, agony_amount, def_zone, used_weapon, electric)
	if(!electric || !omen_evil) //If it's not electric we don't care! Likewise, if we don't have the omen_evil variant, don't care!
		return
	if(!ishuman(unlucky_soul))
		return
	if(prob(3 * omen_luck))
		var/mob/living/carbon/human/human_guy = unlucky_soul
		if(human_guy.should_have_organ(O_HEART))
			for(var/obj/item/organ/internal/heart/heart in human_guy.internal_organ_list())
				if(heart.robotic)
					continue //Robotic hearts are immune to this.
				human_guy.injure(INJURY_BLUNT, 10 * stun_amount * omen_damage, heart, src)
				human_guy.injure(INJURY_BLUNT, 0.25 * agony_amount * omen_damage, heart, src)
			play_sfx(src, SFX_EFFECTS_SINGLEBEAT)
			to_chat(unlucky_soul, span_bolddanger("You feel as though your heart stopped"))
			human_guy.status_at_least(STAT_STUNNED, 5)
			omen_consume()
			return

#undef OMEN_TRAIT_SOURCE
