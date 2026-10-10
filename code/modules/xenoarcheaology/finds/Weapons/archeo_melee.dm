/// Our summonables
#define SOULSTONE /obj/item/soulstone
#define SHELL /obj/structure/constructshell
#define ARTIFACT /obj/machinery/artifact

/// Modified version of the cultblade that xenoarch spawned.
/// This is a usuable version that isn't just a trap if you find it and try to use it on a mob.
/// Has some spooky effects, damages you as you use it (which fuels the sword) and can really hurt if overused.
/// And if you feed it enough, it allows the sword to do some special spawns.
/// Melee has always been a VERY underused thing and guns are EXTREMELY strong comparitively.
/// Thus, this gives the xenoarch a few choices when finding this:
/// Give it to R&D to deconstruct, use it to fight mobs off near artifact sites, give it to people exploring space, or keep it to summon more artifacts.
/// If you DO decide to use it and then give it to R&D...Well...Either you or whoever puts it into the deconstructor is going to have a BAD time.
/obj/item/melee/artifact_blade
	name = "artifact blade"
	desc = "A mysterious blade that emanates terrifying power"
	icon_state = "cultblade"
	w_class = ITEMSIZE_LARGE
	force = 30
	throwforce = 10
	toolspeed = 5 //Syncs perfectly with the animation time.
	hitsound = SFX_WEAPONS_BLADESLICE
	drop_sound = SFX_ITEMS_DROP_SWORD
	pickup_sound = SFX_ITEMS_PICKUP_SWORD
	attack_verb = list("attacked", "slashed", "stabbed", "sliced", "torn", "ripped", "diced", "cut")
	edge = TRUE
	sharp = TRUE
	injury_kind = INJURY_CUT
	embed_chance = 0
	var/stored_blood = 0 //How much energy we have!
	COOLDOWN_DECLARE(special_cooldown) //When our powers may next be used. Can be admin-set to a high number to keep the mode from being changed.
	var/static/list/abilities = list("Consecrate", "Summon")
	var/static/list/summonables = list("Soulstone" = SOULSTONE, "Shell" = SHELL, "Cultic Artifact" = ARTIFACT)
	var/consecrating = FALSE //If we are consecrating or not!
	var/consecration_cost = 10 //Ten stored_blood per use!
	var/empowered = FALSE //If our next atack is empowered (2x damage)

//The last human that touched us (an OM handle): the blade works on them while it has one.
/obj/item/melee/artifact_blade/var/tmp/mob/living/carbon/human/last_touched

CAPABILITIES(/obj/item/melee/artifact_blade)
	op("convert_turf", ai(), takes("turf"), wait(PROC_REF(convert_time)), then(PROC_REF(convert_turf_done)))
	ref_one(nameof(last_touched))
	every(2 SECONDS, then(PROC_REF(artifact_blade_step)), when = nameof(last_touched))
	op("blade_self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))

/obj/item/melee/artifact_blade/examine(mob/user)
	. = ..()
	if(stored_blood && user == last_touched())
		. += span_cult("You can sense the blade has about " + span_bold("[stored_blood]") + " lifeforce contained within it.")

/obj/item/melee/artifact_blade/proc/artifact_blade_step(datum/act/timer/A)
	if(!last_touched() || !stored_blood) //Nobody has touched us yet or we have no energy...For now.
		return
	if(!last_touched() || last_touched().stat == DEAD) //If our user doesn't exist or is dead, stop processing until the next unlucky sod touches us.
		rel_clear(src, nameof(last_touched))
		return
	if(loc == last_touched() && (last_touched().life_tick % 30 == 0)) //We are currently being wielded by our owner. One proc every minute.
		/// First and foremost, the sword passively takes some blood from you when you hold it.
		/// This doesn't INJURE you like using it but does take blood. And a LOT of it. If you just carry the sword around, it's going to drain you.
		to_chat(last_touched(), span_cult("You feel weaker as the sword drains your lifeforce, imbuing itself with power."))
		var/blood_to_remove = rand(10,30)
		if(last_touched().remove_blood(blood_to_remove))
			stored_blood += blood_to_remove*3
			empowered = 1
			return //We are done with our effects.
		else
			return

// a charged blade punishes its wielder.
DESTROY_EFFECTS(/obj/item/melee/artifact_blade, new /datum/destroy_effects_data(message = "%SRC% screeches as it's destroyed", message_class = "cult"))

/obj/item/melee/artifact_blade/on_destroy(force)
	if(stored_blood && last_touched() && last_touched().stat != DEAD) //We have been activated (have some energy), an owner and they are alive. They are going to feel pain.
		to_chat(last_touched(), span_cult("You feel as though your mind is suddenly being torn apart at the seams as the [src] is destroyed!"))
		last_touched().status_at_least(STAT_PARALYZED, 10)
		last_touched().status_at_least(STAT_SLEEPING, 10)
		last_touched().status_adjust(STAT_JITTERY, 1000)
		last_touched().status_adjust(STAT_BLURRY, 10)
		last_touched().apply_body_effect(/datum/body_effect/agonize, 30 SECONDS)
		blood_splatter(last_touched(), last_touched(), 1)
		if(last_touched().loc)
			conjure_animation(last_touched().loc)
	var/turf/T = get_turf(last_touched())
	if(istype(T))
		lightning_strike(T, TRUE)
	play_sfx(src, SFX_GOONSTATION_SPOOKY_CREEPYSHRIEK) //It plays VERY far.
	..()

/obj/item/melee/artifact_blade/cultify()
	return

/obj/item/melee/artifact_blade/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(M == user) //No accidentally hitting yourself and exploding.
		return
	var/zone = (user.hand ? BP_L_ARM:BP_R_ARM) //Which arm we're in!
	var/prior_force = force
	if(empowered)
		force = force*2
		empowered = 0
	/// First, we check a few things.
	/// Check 1: We aren't a cultist and they're a human AND they're not AI controlled
	/// OR
	/// Check 2: (We're a cultist AND they're a cultist) OR (Our factions align)
	/// If these are true, we get hurt.
	if((!iscultist(user) && (ishuman(M) && !istype(M, /mob/living/carbon/human/ai_controlled))  || ((iscultist(user) && iscultist(M)) || M.faction == user.faction)))
		act_message(user, null, others = span_cult("%U%'s arm is engulfed in dark flames!"))
		to_chat(user, span_cult("An inexplicable force rips through your arm as it's engulfed in flames, tearing the sword from your grasp!"))
		user.drop_from_inventory(src, user.loc)
		user.status_at_least(STAT_WEAKENED, 5)
		throw_at(get_edge_target_turf(src,pick(GLOB.alldirs)),rand(1,10),5)
		user.injure(INJURY_BURN, rand(force/2, force), zone, src)
		return ITEM_INTERACT_SUCCESS

	..() //We hit them!

	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		var/obj/item/organ/external/affecting = H.get_organ(zone)

		to_chat(user, span_cult("You feel your [affecting.name] tearing from the inside out as the sword takes its blood price!"))

		var/damage_to_apply = rand(1,3)
		H.injure(INJURY_BLUNT, damage_to_apply, affecting, src) //Careful...Too much use and you might break your arm! This doesn't make you bleed because the sword is slurping that up.
		if(((affecting.get_trauma() + affecting.get_burn()) >= affecting.max_damage) && prob((affecting.get_trauma() + affecting.get_burn()))) //Don't just splint  your arm and keep using it, because you'll lose it!
			user.visible_message(span_cult("[H]'s arm is engulfed in dark flames!"))
			affecting.droplimb(TRUE, DROPLIMB_BURN) //And by hacked off, we mean melted into ashes... It's fire, so it's a clean loss.

		var/blood_loss = damage_to_apply*3
		if(H.remove_blood(blood_loss)) //Non insignificant amount if we keep using it. 3 to 15 blood lost per swing. Blood volume base is 560. Anything above 476 is safe. This means we get 28 to 5 swings. Average being 9 swings.
			stored_blood += blood_loss //We add the damage dealt to our owner to our stored blood.

		/// If the thing we're hitting is dead, our faction, friendly, or synthetic, we get no blood.
		if(M.stat < DEAD && M.faction != user.faction && !ispassive(M) && !issilicon(M) && !isbot(M) && !isslime(M))
			stored_blood += force

	//If the user isn't 'worthy' they get a single swing before the sword THROWS itself away from them. Possibly even off-screen!
	else if(istype(user, /mob/living/simple_mob/construct))
		to_chat(user, span_cult("An inexplicable force rips through you, tearing the sword from your grasp!"))
		user.drop_from_inventory(src, user.loc)
		throw_at(get_edge_target_turf(src,pick(GLOB.alldirs)),rand(1,10),5)

	else
		to_chat(user, span_cult("The blade hisses, forcing itself from your manipulators. \The [src] will only allow mortals to wield it against foes, not kin."))
		user.drop_from_inventory(src, user.loc)
		throw_at(get_edge_target_turf(src,pick(GLOB.alldirs)),rand(1,10),5)

	if(prob(10)) //During testing, this was set to 100% of the time to make sure it works... It went  from spooky to 'dear god make it stop'
		var/spooky = SFX_EFFECTS_GHOST_MIX //It's just a cursed, talking sword. Nothing to fear!
		playsound(src, spooky, 50, 1)

	force = prior_force //Return our force back.
	return ITEM_INTERACT_SUCCESS

/obj/item/melee/artifact_blade/pickup(mob/living/user as mob)
	// We check to see if the person picking us up isn't our owner, not a cultist, and they're human.
	// Yes. This means you can hand off the sword to someone else to make them the newfound owner of the cursed sword.
	if((user != last_touched()) && !iscultist(user) && ishuman(user))
		to_chat(user, span_cult("An overwhelming feeling of dread comes over you as you pick up the sword. You feel as though it has become attached to you."))
		rel_set(src, nameof(last_touched), user)


/// Old attack_self. The blade rests between actions (a cooldown is no tracked state, so it is refused here rather than by a requirement).
/obj/item/melee/artifact_blade/proc/interaction_self(datum/act/op/A)
	if(!COOLDOWN_FINISHED(src, special_cooldown))
		to_chat(A.actor, span_warning("the blade does not respond to your attempts, having recently performed an action"))
		return OP_OK
	blade_action_stage(A.actor, A.held, list())
	return OP_OK

/obj/item/melee/artifact_blade/proc/blade_action_stage(mob/user, obj/item/held, list/answers)
	COOLDOWN_START(src, special_cooldown, 12 SECONDS)
	if(stored_blood < 10)
		to_chat(user, span_cult("The blade does not respond to your attempts, seeming to have not enough blood to perform any actions!"))
		return TRUE
	if(stored_blood >= 10)
		var/choice = answers["k176"]
		if(!("k176" in answers))
			open_request(src, /datum/prompt/choice/artifact_blade_action, PROC_REF(blade_action_answered), answerer = user, held_item = held, answers = answers, answer_key = "k176", question = "What action do you wish to have the blade perform?", title = "Download", choices = abilities)
			return TRUE
		if(isnull(choice))
			return TRUE
		if(choice && loc == user)
			switch(choice)
				if("Consecrate")
					var/decision2 = answers["k180"]
					if(!("k180" in answers))
						open_request(src, /datum/prompt/choice/artifact_blade_action, PROC_REF(blade_action_answered), answerer = user, held_item = held, answers = answers, answer_key = "k180", question = "Do you wish to toggle the sword's 'consecrate' mode? If enabled, this will allow the sword to turn floors and walls into a more cult-like appearance! It requires [consecration_cost] per use!", title = "Consecrate!", choices = list("Toggle on", "Toggle off"), buttons = TRUE)
						return TRUE
					if(isnull(decision2))
						return TRUE
					consecrate_toggle(user, decision2)
					return TRUE
				/// Spawning logic. Checks the 'summonables' list.
				if("Summon")
					var/summoned_item = answers["k185"]
					if(!("k185" in answers))
						open_request(src, /datum/prompt/choice/artifact_blade_action, PROC_REF(blade_action_answered), answerer = user, held_item = held, answers = answers, answer_key = "k185", question = "What do you wish to summon?", title = "Summon", choices = summonables)
						return TRUE
					if(isnull(summoned_item))
						return TRUE
					summon_item(user, summoned_item)
					return TRUE
	return TRUE

/// Replay keeps the original borrowed invocation arguments and answers for each branch.
/datum/prompt/choice/artifact_blade_action
	timeout = 0
	var/obj/item/held_item
	var/held_expected = FALSE
	var/list/answers
	var/answer_key

CAPABILITIES(/datum/prompt/choice/artifact_blade_action)
	ref_one(nameof(held_item), /obj/item)

/datum/prompt/choice/artifact_blade_action/prepare(datum/act/A)
	. = ..()
	var/obj/item/captured_held = held_item
	held_expected = !isnull(captured_held)
	rel_clear(src, nameof(held_item))
	if(captured_held && !QDELETED(captured_held))
		rel_set(src, nameof(held_item), captured_held)

/datum/prompt/choice/artifact_blade_action/recheck_extra()
	if((held_expected && QDELETED(held_item)))
		return "gone"

/obj/item/melee/artifact_blade/proc/blade_action_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = blade_action_apply(A)
	SStgui.update_uis(src)

/obj/item/melee/artifact_blade/proc/blade_action_apply(datum/act/request/A)
	var/datum/prompt/choice/artifact_blade_action/ask = A.answer
	ask.answers[ask.answer_key] = ask.value
	return blade_action_stage(ask.answerer, ask.held_item, ask.answers)

/obj/item/melee/artifact_blade/proc/consecrate_toggle(mob/user as mob, toggle)
	switch(toggle)
		if("Toggle on")
			consecrating = TRUE
			to_chat(user, span_cult("The blade will now transform walls and tiles!"))
			return
		if("Toggle off")
			consecrating = FALSE
			to_chat(user, span_cult("The blade will " + span_bold("NOT") +" transform walls and tiles!"))
			return
		else
			return

/// It lets them select it, gives them a small blurb on it (w/ cost), then checks to see if they have enough blood.
/// The summonables list can be VV'd by admins to allow for adminbus.
/// To add to the list: Add-Item, Multi-line text (Front-facing name), Associated value = yes, Atom Typepath = whatever you want.
/// This should appear something like " Paper = /obj/item/paper " if you did it right, and will let them summon paper!
/obj/item/melee/artifact_blade/proc/summon_item(mob/user as mob, selected_item)
	return summon_item_stage(user, selected_item, null)

/obj/item/melee/artifact_blade/proc/summon_item_stage(mob/user, selected_item, decision2)
	if(selected_item)
		if(selected_item == "Soulstone")
			if(isnull(decision2))
				open_request(src, /datum/prompt/choice/artifact_blade_summon, PROC_REF(summon_item_answered), answerer = user, selected_item = selected_item, question = "Do you wish to create a redspace gem? This will take 200 lifeforce from the sword.", title = "Generate Gem")
				return
			if(stored_blood < 200)
				to_chat(user, span_cult("The blade does not have enough lifeforce!"))
				return
			if(decision2 == "YES")
				var/obj/item/soulstone/our_stone = new SOULSTONE(user.loc)
				our_stone.desc = "A glowing stone made of what appears to be a pure chunk of redspace. It seems to have the power to transfer the consciousness of dead or nearly-dead humanoids into it."
				our_stone.name  = "Redspace Gem"
				stored_blood -= 200
				to_chat(user, span_cult("You have summoned a redspace gem!"))
				return
			else
				return
		if(selected_item == "Shell")
			if(isnull(decision2))
				open_request(src, /datum/prompt/choice/artifact_blade_summon, PROC_REF(summon_item_answered), answerer = user, selected_item = selected_item, question = "Do you wish to create a shell? This will take 500 lifeforce from the sword.", title = "Generate Shell")
				return
			if(stored_blood < 500)
				to_chat(user, span_cult("The blade does not have enough lifeforce!"))
				return
			if(decision2 == "YES")
				var/obj/structure/constructshell/shell = new SHELL(user.loc)
				shell.desc = "A strange collection of stone carved out in a vague, humanoid shape. Red, pulsing lines travel down its entirety."
				stored_blood -= 500 //This is VERY costly.
				return

		/// This is one of the ways for xenoarch to obtain more artifacts in case you have depleted all the large artifacts in the available world.
		/// While the artifact cap is relatively high, the more Z-levels that spawn any mineral turf, the less artifacts xenoarch can reliably find.
		/// In some cases, if a xenoarch was REALLY unlucky, they could only find 3-4 large artifacts in the (readily) available Z levels without scouring the entire universe.
		/// So this acts as a "You sacrifice a LOT to get a random artifact"
		if(selected_item == "Cultic Artifact")
			if(isnull(decision2))
				open_request(src, /datum/prompt/choice/artifact_blade_summon, PROC_REF(summon_item_answered), answerer = user, selected_item = selected_item, question = "Do you wish to create an artifact? This will take 1000 lifeforce from the sword.", title = "Generate Artifact")
				return
			if(stored_blood < 1000)
				to_chat(user, span_cult("The blade does not have enough lifeforce!"))
				return
			if(decision2 == "YES")
				var/obj/machinery/artifact/artifact = new ARTIFACT(user.loc)
				artifact.desc = "A strange artifact. Red, pulsing lines travel down its entirety. It appears as though it has been brought into this reality through abnormal means."
				stored_blood -= 500 //This is VERY costly.
				return
			else
				return

		if(selected_item in summonables) //If admins modify the list, let's spawn it!
			//This one doesn't have a blood requirement, barring the 100 required to GET to this menu. If an admin VV'd the list, there's a reason!
			var/thing_to_spawn = summonables[selected_item]
			new thing_to_spawn(user.loc)
			stored_blood = max(0,stored_blood-250) //Subtract 250 stored blood, down to a minimum of 0. No negative numbers here!
			return
		else // You're trying to href hack it! (Or an admin put in the wrong thing). I'm going to assume if you know how to href hack, you're looking at this beforehand.
			message_admins("[key_name_admin(user)] attempted to spawn an object not in the artifact blade's spawnlist! This is either a HREF hack, the list was improperly VV'd by an admin, or something went wrong!")
			log_game("[key_name_admin(user)] attempted to spawn an object not in the artifact blade's spawnlist!")
			return
	else
		return

/datum/prompt/choice/artifact_blade_summon
	timeout = 0
	choices = list("YES", "NO")
	buttons = TRUE
	var/selected_item

/obj/item/melee/artifact_blade/proc/summon_item_answered(datum/act/request/context)
	if(!context.answer)
		return
	. = summon_item_apply(context)
	SStgui.update_uis(src)
	return .

/obj/item/melee/artifact_blade/proc/summon_item_apply(datum/act/request/context)
	var/datum/prompt/choice/artifact_blade_summon/request = context.answer
	return summon_item_stage(request.answerer, request.selected_item, request.value)

/// While this COULD just use the cultify() proc ultimately, I decided against that as this isn't meant to be
/// Some sort of weapon of mass destruction. It's supposed to be a funny, spooky artifact that you find.
/// Thus, it uses the 'occult_act' proc, which does a HEAVILY watered down version of the cultify() proc.
/// Only affects simulated turf, simulated walls, and girders. Nothing else. This shouldn't be desturctive, simply gimmicky.
/obj/item/melee/artifact_blade/afterattack(atom/A, mob/living/user, proximity)
	if(consecrating && proximity && !ismob(A))
		convert_turf(A, user)
	else
		..()

/// The fancy animation it plays when you hit something to convert it!
/obj/item/melee/artifact_blade/proc/conjure_animation(turf/target) //Taken from occult wizard code.
	var/atom/movable/overlay/animation = new /atom/movable/overlay(target)
	animation.name = "conjure"
	animation.icon = 'icons/effects/effects.dmi'
	animation.plane = OBJ_PLANE
	animation.layer = ABOVE_JUNK_LAYER
	animation.icon_state = "cultwall"
	flick("cultwall",animation)
	animation.expire(1 SECOND)

/// When it actually, properly converts the turf.
/obj/item/melee/artifact_blade/proc/convert_turf(atom/A, mob/living/user) //Shamelessly taken from RCD code.
	if(stored_blood < consecration_cost)
		to_chat(user, span_cult("\The [src] lacks enough lifeforce to convert."))
		return FALSE
	conjure_animation(A, toolspeed)
	perform_op(user, src, "convert_turf", null, ORIGIN_SYSTEM, AUTH_PHYSICAL, with = list("turf" = A))
	return TRUE

/obj/item/melee/artifact_blade/proc/convert_time(datum/act/op/A)
	return toolspeed

/obj/item/melee/artifact_blade/proc/convert_turf_done(datum/act/op/op_act)
	var/atom/A = op_act.arg("turf")
	var/mob/living/user = op_act.actor
	if(stored_blood < consecration_cost)
		to_chat(user, span_cult("\The [src] lacks enough lifeforce to convert."))
		return
	if(A.occult_act(user))
		stored_blood -= consecration_cost
#undef SOULSTONE
#undef SHELL
#undef ARTIFACT

/// The last human that touched us
/obj/item/melee/artifact_blade/proc/last_touched() as /mob/living/carbon/human
	return last_touched
