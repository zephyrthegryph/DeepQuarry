/client/proc/smite(mob/living/carbon/human/target in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
	set name = "Smite"
	set desc = "Abuse a player with various 'special treatments' from a list."
	set category = VERB_CAT_FUN_DO_NOT
	// Only this client's actual ended request carries the original target and answers.
	var/list/smite_answers = list()
	if(length(args) >= 2)
		var/datum/request/resumed = args[2]
		if(istype(resumed, /datum/prompt/choice/client_smite) && resumed.owner == src && resumed.subject == target && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(smite_answered))
			var/list/previous = resumed.captured["answers"]
			smite_answers = previous.Copy()
			smite_answers[resumed.step_name] = resumed.value
	if(!admin_require(src, R_FUN, "smite", TRUE))
		return

	if(!istype(target))
		return

	var/static/list/smite_types = list(SMITE_BREAKLEGS,SMITE_BLUESPACEARTILLERY,SMITE_SPONTANEOUSCOMBUSTION,SMITE_LIGHTNINGBOLT,
								SMITE_SHADEKIN_ATTACK,SMITE_SHADEKIN_NOMF,SMITE_AD_SPAM,SMITE_REDSPACE_ABDUCT,SMITE_AUTOSAVE,SMITE_AUTOSAVE_WIDE,SMITE_SPICEREQUEST,SMITE_PEPPERNADE,SMITE_TERROR,
								SMITE_PIE, SMITE_SPICE, SMITE_HOTDOG) //pie, spicy air and hot dog

	var/question_a1 = "Select the type of SMITE for [target]"
	if(!("a1" in smite_answers))
		open_request(src, /datum/prompt/choice/client_smite, PROC_REF(smite_answered), answerer = mob, subject = target, captured = list("answers" = smite_answers.Copy()), step_name = "a1", question = question_a1, title = "SMITE Type Choice", choices = smite_types)
		return
	var/smite_choice = smite_answers["a1"]
	if(isnull(smite_choice))
		return
	if(!smite_choice)
		return

	if(length(smite_answers) <= 1) // Once: later questions of a smite re-run this.
		log_and_message_admins("has used SMITE ([smite_choice]) on [key_name(target)].", src)
		feedback_add_details("admin_verb","SMITE") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

	switch(smite_choice)
		if(SMITE_BREAKLEGS)
			var/broken_legs = 0
			var/obj/item/organ/external/left_leg = target.get_organ(BP_L_LEG)
			if(left_leg && left_leg.fracture())
				broken_legs++
			var/obj/item/organ/external/right_leg = target.get_organ(BP_R_LEG)
			if(right_leg && right_leg.fracture())
				broken_legs++
			if(!broken_legs)
				to_chat(src,"[target] didn't have any breakable legs, sorry.")

		if(SMITE_BLUESPACEARTILLERY)
			bluespace_artillery(target,src)

		if(SMITE_SPONTANEOUSCOMBUSTION)
			target.adjust_fire_stacks(10)
			target.ignite_mob()
			act_message(target, null, others = span_danger("%U% bursts into flames!"))

		if(SMITE_LIGHTNINGBOLT)
			var/turf/T = get_step(get_step(target, NORTH), NORTH)
			T.Beam(target, icon_state="lightning[rand(1,12)]", time = 5)
			target.electrocute_act(75,def_zone = BP_HEAD)
			act_message(target, null, others = span_danger("%U% is struck by lightning!"))

		if(SMITE_SHADEKIN_ATTACK)
			var/turf/Tt = get_turf(target) //Turf for target

			if(target.loc != Tt)
				return //Too hard to attack someone in something

			var/turf/Ts //Turf for shadekin

			//Try to find nondense turf
			for(var/direction in GLOB.cardinal)
				var/turf/T = get_step(target,direction)
				if(T && !T.density)
					Ts = T //Found shadekin spawn turf
			if(!Ts)
				return //Didn't find shadekin spawn turf

			var/mob/living/simple_mob/shadekin/red/shadekin = new(Ts)
			//Abuse of shadekin
			shadekin.real_name = shadekin.name
			shadekin.init_vore(TRUE)
			shadekin.ability_flags |= 0x1
			shadekin.phase_out(get_turf(shadekin))
			shadekin.ai_brain?.give_target(target, TRUE)
			shadekin.ai_brain?.set_hostile(FALSE)
			if(shadekin.ai_brain)
				shadekin.ai_brain.mauling = TRUE
			seq_run_frame_now(shadekin, /datum/sequence/life)
			//Remove when done
			after(shadekin, 10 SECONDS, TYPE_PROC_REF(/mob, death))

		if(SMITE_SHADEKIN_NOMF)
			var/static/list/kin_types = list(
				"Red Eyes (Dark)" =	/mob/living/simple_mob/shadekin/red/dark,
				"Red Eyes (Light)" = /mob/living/simple_mob/shadekin/red/white,
				"Red Eyes (Brown)" = /mob/living/simple_mob/shadekin/red/brown,
				"Blue Eyes (Dark)" = /mob/living/simple_mob/shadekin/blue/dark,
				"Blue Eyes (Light)" = /mob/living/simple_mob/shadekin/blue/white,
				"Blue Eyes (Brown)" = /mob/living/simple_mob/shadekin/blue/brown,
				"Purple Eyes (Dark)" = /mob/living/simple_mob/shadekin/purple/dark,
				"Purple Eyes (Light)" = /mob/living/simple_mob/shadekin/purple/white,
				"Purple Eyes (Brown)" = /mob/living/simple_mob/shadekin/purple/brown,
				"Yellow Eyes (Dark)" = /mob/living/simple_mob/shadekin/yellow/dark,
				"Yellow Eyes (Light)" = /mob/living/simple_mob/shadekin/yellow/white,
				"Yellow Eyes (Brown)" = /mob/living/simple_mob/shadekin/yellow/brown,
				"Green Eyes (Dark)" = /mob/living/simple_mob/shadekin/green/dark,
				"Green Eyes (Light)" = /mob/living/simple_mob/shadekin/green/white,
				"Green Eyes (Brown)" = /mob/living/simple_mob/shadekin/green/brown,
				"Orange Eyes (Dark)" = /mob/living/simple_mob/shadekin/orange/dark,
				"Orange Eyes (Light)" = /mob/living/simple_mob/shadekin/orange/white,
				"Orange Eyes (Brown)" = /mob/living/simple_mob/shadekin/orange/brown,
				"Rivyr (Unique)" = /mob/living/simple_mob/shadekin/blue/rivyr)
			var/question_a2 = "Select the type of shadekin for [target] nomf"
			if(!("a2" in smite_answers))
				open_request(src, /datum/prompt/choice/client_smite, PROC_REF(smite_answered), answerer = mob, subject = target, captured = list("answers" = smite_answers.Copy()), step_name = "a2", question = question_a2, title = "Shadekin Type Choice", choices = kin_types)
				return
			var/kin_type = smite_answers["a2"]
			if(isnull(kin_type))
				return
			if(!kin_type || !target)
				return


			kin_type = kin_types[kin_type]

			var/question_a3 = "Control the shadekin yourself or delete pred and prey after?"
			if(!("a3" in smite_answers))
				open_request(src, /datum/prompt/choice/client_smite, PROC_REF(smite_answered), answerer = mob, subject = target, captured = list("answers" = smite_answers.Copy()), step_name = "a3", question = question_a3, title = "Control Shadekin?", choices = list("Control","Cancel","Delete"), buttons = TRUE)
				return
			var/myself = smite_answers["a3"]
			if(isnull(myself))
				return
			if(!myself || myself == "Cancel" || !target)
				return

			var/turf/Tt = get_turf(target)

			if(target.loc != Tt)
				return //Can't nom when not exposed

			//Begin abuse
			target.transforming = TRUE //Cheap hack to stop them from moving
			var/mob/living/simple_mob/shadekin/shadekin = new kin_type(Tt)
			shadekin.real_name = shadekin.name
			shadekin.init_vore(TRUE)
			shadekin.can_be_drop_pred = TRUE
			shadekin.set_dir(SOUTH)
			shadekin.ability_flags |= 0x1
			shadekin.phase_out(get_turf(shadekin)) //Homf
			var/datum/shadekin/smite_SK = shadekin.get_shadekin_state()
			if(smite_SK)
				smite_SK.dark_energy = initial(smite_SK.dark_energy)
			//For fun: a timed sequence (shadekin_smite_step), nothing sleeps.
			shadekin_smite_step(shadekin, target, myself == "Control" ? ckey : null, 1)


		if(SMITE_REDSPACE_ABDUCT)
			redspace_abduction(target, src)

		if(SMITE_AUTOSAVE)
			fake_autosave(target, src)

		if(SMITE_AUTOSAVE_WIDE)
			fake_autosave(target, src, TRUE)

		if(SMITE_AD_SPAM)
			if(target.client)
				target.client.create_fake_ad_popup_multiple(/atom/movable/screen/popup/default, 15)

		if(SMITE_TERROR)
			if(ishuman(target))
				target.fear = 200

		if(SMITE_PEPPERNADE)
			var/obj/item/grenade/chem_grenade/teargas/grenade = new /obj/item/grenade/chem_grenade/teargas
			grenade.forceMove(target.loc)
			to_chat(target,span_warning("GRENADE?!"))
			grenade.detonate()

		if(SMITE_SPICEREQUEST)
			var/obj/item/reagent_containers/food/condiment/spacespice/spice = new /obj/item/reagent_containers/food/condiment/spacespice
			spice.forceMove(target.loc)
			to_chat(target,"A bottle of spices appears at your feet... be careful what you wish for!")

		if(SMITE_PIE)
			new/obj/effect/decal/cleanable/pie_smudge(get_turf(target))
			play_sfx(target, SFX_EFFECTS_SLIME_SQUISH, 2, extrarange = get_rand_frequency(), falloff = 5)
			target.status_at_least(STAT_WEAKENED, 1)
			act_message(target, null, others = span_danger("%U% is struck by pie!"))

		if(SMITE_SPICE)
			to_chat(target, span_warning("Spice spice baby!"))
			target.status_at_least(STAT_BLURRY, 25)
			target.status_at_least(STAT_BLINDED, 10)
			target.status_at_least(STAT_STUNNED, 5)
			target.status_at_least(STAT_WEAKENED, 5)
			play_sfx(target, SFX_EFFECTS_SPRAY2, extrarange = get_rand_frequency(), falloff = 5)

		if(SMITE_HOTDOG)
			hotdog_smite(target)
		else
			return //Injection? Don't print any messages.

/proc/bluespace_artillery(mob/living/target, user)
	if(!istype(target))
		return

	var/user_name = user ? key_name(user) : "Remotely (Discord)"

	to_chat(target,"You've been hit by bluespace artillery!")
	log_and_message_admins("has been hit by Bluespace Artillery fired by [user_name]", target)

	target.setMoveCooldown(2 SECONDS)

	var/turf/simulated/floor/T = get_turf(target)
	if(istype(T))
		if(prob(80))	T.break_tile_to_plating()
		else			T.break_tile()

	playsound(T, get_sfx(SFX_EXPLOSION), 100, 1, get_rand_frequency(), falloff = 5) // get_sfx() is so that everyone gets the same sound

	if(target.vitality() < 0.1)
		target.gib()
	else
		target.injure(INJURY_BLUNT, max(99, target.get_endurance() * target.vitality() - 1), flags = INJURE_IGNORE_RESISTANCE)
		target.status_at_least(STAT_STUNNED, 20)
		target.status_at_least(STAT_WEAKENED, 20)
		target.status_set(STAT_STUTTERING, 20)

GLOBAL_VAR(redspace_abduction_z)

/area/redspace_abduction
	name = "Another Time And Place"
	requires_power = FALSE
	dynamic_lighting = FALSE

/proc/redspace_abduction(mob/living/target, user)
	if(GLOB.redspace_abduction_z < 0)
		to_chat(user,span_warning("The abduction z-level is already being created. Please wait."))
		return
	if(!GLOB.redspace_abduction_z)
		GLOB.redspace_abduction_z = -1
		to_chat(user,span_warning("This is the first use of the verb this shift, it will take a minute to configure the abduction z-level. It will be z[world.maxz+1]."))
		var/z = ++world.maxz
		world.max_z_changed()
		for(var/x = 1 to world.maxx)
			for(var/y = 1 to world.maxy)
				var/turf/T = locate(x,y,z)
				new /area/redspace_abduction(T)
				T.ChangeTurf(/turf/unsimulated/fake_space)
				T.plane = -100
				CHECK_TICK
		GLOB.redspace_abduction_z = z

	if(!target || !user)
		return

	var/size_of_square = 26
	var/halfbox = round(size_of_square*0.5)
	target.set_transforming(TRUE)
	to_chat(target,span_danger("You feel a strange tug, deep inside. You're frozen in momentarily..."))
	to_chat(user,span_notice("Beginning vis_contents copy to abduction site, player mob is frozen."))
	after(target, 1 SECOND, GLOBAL_PROC_REF(redspace_abduction_copy), with = list(target, user, size_of_square, halfbox))

/// redspace_abduction() a second after the target freezes.
/proc/redspace_abduction_copy(mob/living/target, user, size_of_square, halfbox)
	//Lower left corner of a working box
	var/llc_x = max(0,halfbox-target.x) + min(target.x+halfbox, world.maxx) - size_of_square
	var/llc_y = max(0,halfbox-target.y) + min(target.y+halfbox, world.maxy) - size_of_square

	//Copy them all
	for(var/x = llc_x to llc_x+size_of_square)
		for(var/y = llc_y to llc_y+size_of_square)
			var/turf/T_src = locate(x,y,target.z)
			var/turf/T_dest = locate(x,y,GLOB.redspace_abduction_z)
			T_dest.vis_contents.Cut()
			T_dest.vis_contents += T_src
			T_dest.set_density(T_src.density)
			T_dest.set_opacity(T_src.opacity)
			CHECK_TICK

	//Feather the edges
	for(var/x = llc_x to llc_x+1) //Left
		for(var/y = llc_y to llc_y+size_of_square)
			if(prob(50))
				var/turf/T = locate(x,y,GLOB.redspace_abduction_z)
				T.set_density(FALSE)
				T.set_opacity(FALSE)
				T.vis_contents.Cut()

	for(var/x = llc_x+size_of_square-1 to llc_x+size_of_square) //Right
		for(var/y = llc_y to llc_y+size_of_square)
			if(prob(50))
				var/turf/T = locate(x,y,GLOB.redspace_abduction_z)
				T.set_density(FALSE)
				T.set_opacity(FALSE)
				T.vis_contents.Cut()

	for(var/x = llc_x to llc_x+size_of_square) //Top
		for(var/y = llc_y+size_of_square-1 to llc_y+size_of_square)
			if(prob(50))
				var/turf/T = locate(x,y,GLOB.redspace_abduction_z)
				T.set_density(FALSE)
				T.set_opacity(FALSE)
				T.vis_contents.Cut()

	for(var/x = llc_x to llc_x+size_of_square) //Bottom
		for(var/y = llc_y to llc_y+1)
			if(prob(50))
				var/turf/T = locate(x,y,GLOB.redspace_abduction_z)
				T.set_density(FALSE)
				T.set_opacity(FALSE)
				T.vis_contents.Cut()

	target.forceMove(locate(target.x,target.y,GLOB.redspace_abduction_z))
	to_chat(target,span_danger("The tug relaxes, but everything around you looks... slightly off."))
	var/client/acting_client
	if(ismob(user))
		var/mob/actor = user
		acting_client = actor.client
	else if(isclient(user))
		acting_client = user
	to_chat(user, span_notice("The mob has been moved. ([admin_jump_link(target, check_rights_for(acting_client, R_HOLDER))])"))

	target.set_transforming(FALSE)

/proc/fake_autosave(mob/living/target, client/user, wide)
	if(!istype(target) || !target.client)
		to_chat(user, span_warning("Skipping [target] because they are not a /mob/living or have no client."))
		return

	if(wide)
		for(var/mob/living/L in orange(user.view, user.mob))
			fake_autosave(L, user)
		return

	target.setMoveCooldown(10 SECONDS)

	to_chat(target, "<span class='notice' style='font: small-caps bold large monospace!important'>Autosaving your progress, please wait...</span>")
	target << 'sound/effects/ding.ogg'

	var/static/list/bad_tips = list(
		"Did you know that black shoes protect you from electrocution while hacking?",
		"Did you know that airlocks always have a wire that disables ID checks?",
		"You can always find at least 3 pairs of glowing purple gloves in maint!",
		"Phoron is not toxic if you've had a soda within 30 seconds of exposure!",
		"Space Mountain Wind makes you immune to damage from space for 30 seconds!",
		"A mask and air tank are all you need to be safe in space!",
		"When exploring maintenance, wearing no shoes makes you move faster!",
		"Did you know that the bartender's shotgun is loaded with harmless ammo?",
		"Did you know that the tesla and singulo only need containment for 5 minutes?")

	var/tip = pick(bad_tips)
	to_chat(target, "<span class='notice' style='font: small-caps bold large monospace!important'>Tip of the day:</span><br><span class='notice'>[tip]</span>")

	var/atom/movable/screen/loader = new(target)
	loader.name = "Autosaving..."
	loader.desc = "A disc icon that represents your game autosaving. Please wait."
	loader.icon = 'icons/obj/discs_vr.dmi'
	loader.icon_state = "quicksave"
	loader.screen_loc = "NORTH-1, EAST-1"
	target.client.screen += loader

	after(target, 10 SECONDS, GLOBAL_PROC_REF(smite_autosave_complete), with = list(target, loader))

/// The autosave smite's second half: tell the victim it finished and take the disc off their screen.
/proc/smite_autosave_complete(mob/target, atom/movable/screen/loader)
	if(!target)
		return
	to_chat(target, "<span class='notice' style='font: small-caps bold large monospace!important'>Autosave complete!</span>")
	if(target.client)
		target.client.screen -= loader

#define SHADEKIN_SMITE_STEP_PAUSE (1 SECOND)
#define SHADEKIN_SMITE_BELCH_PAUSE (2 SECONDS)
#define SHADEKIN_SMITE_RELEASE (8 SECONDS)

/// The shadekin smite's show, a step per timer: turn, turn, turn, belch, then phase back in and
/// either hand the shadekin to `controller_ckey` or take both away.
/proc/shadekin_smite_step(mob/living/simple_mob/shadekin/shadekin, mob/living/target, controller_ckey, step)
	if(QDELETED(shadekin))
		if(target)
			target.set_transforming(FALSE)
		return
	if(step == 1 && target)
		// The target's release does not ride on the shadekin's timers: if it dies mid-show they are dropped, and this one still frees the target.
		after(target, SHADEKIN_SMITE_RELEASE, GLOBAL_PROC_REF(shadekin_smite_release), key = "shadekin_smite_release", with = list(target))
		// The shadekin dying frees the target at once; the timer is the fallback for any other way the show ends.
		observe(shadekin, /datum/notice/mob_death, target, then(TYPE_PROC_REF(/mob/living, shadekin_smite_died)))
	switch(step)
		if(2)
			shadekin.set_dir(WEST)
		if(3)
			shadekin.set_dir(EAST)
		if(4)
			shadekin.set_dir(SOUTH)
		if(5)
			shadekin.audible_message(span_vwarning(span_bold("[shadekin]") + " belches loudly!"), runemessage = "URRRRRP")
		if(6)
			shadekin.phase_in(get_turf(shadekin), shadekin.get_shadekin_state())
			if(target)
				target.set_transforming(FALSE) //Undo cheap hack
			if(controller_ckey) //Put admin in mob
				shadekin.ckey = controller_ckey
			else //Permakin'd
				if(target)
					to_chat(target,span_danger("You're carried off into The Dark by the [shadekin]. Who knows if you'll find your way back?"))
					target.ghostize()
					spent(target)
				spent(shadekin)
			return
	var/next_delay = (step == 5) ? SHADEKIN_SMITE_BELCH_PAUSE : SHADEKIN_SMITE_STEP_PAUSE
	after(shadekin, next_delay, GLOBAL_PROC_REF(shadekin_smite_step), with = list(shadekin, target, controller_ckey, step + 1))

/// The shadekin smite's safety net: whatever became of the shadekin, the target moves again.
/proc/shadekin_smite_release(mob/living/target)
	target.set_transforming(FALSE)

/// The shadekin the smite made died mid-show: the target it was carrying moves again now, and the fallback timer is spent.
/mob/living/proc/shadekin_smite_died(datum/act/notice/A)
	set_transforming(FALSE)
	cancel_after(src, "shadekin_smite_release")

/// The hot dog smite: a whistle, then two seconds later the costume, gone again after five.
/proc/hotdog_smite(mob/living/target)
	play_sfx(target, SFX_EFFECTS_WHISTLE, extrarange = get_rand_frequency())
	after(target, 2 SECONDS, GLOBAL_PROC_REF(hotdog_smite_dress), with = list(target))

/proc/hotdog_smite_dress(mob/living/target)
	target.status_at_least(STAT_STUNNED, 10)
	if(!ishuman(target))
		return
	var/mob/living/carbon/human/H = target
	if(H.get_equipped_item(SLOT_ID_HEAD))
		H.unEquip(H.get_equipped_item(SLOT_ID_HEAD))
	if(H.get_equipped_item(SLOT_ID_SUIT))
		H.unEquip(H.get_equipped_item(SLOT_ID_SUIT))
	var/obj/item/clothing/suit = new /obj/item/clothing/suit/storage/hooded/foodcostume/hotdog
	var/obj/item/clothing/hood = new /obj/item/clothing/head/hood_vr/hotdog_hood
	H.equip_to_slot_if_possible(suit, SLOT_ID_SUIT, 0, 0, 1)
	H.equip_to_slot_if_possible(hood, SLOT_ID_HEAD, 0, 0, 1)
	suit.expire(5 SECONDS)
	hood.expire(5 SECONDS)

/datum/prompt/choice/client_smite
	timeout = 0
	rights = R_FUN
	recheck_on_open = TRUE

/datum/prompt/choice/client_smite/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	var/mob/living/carbon/human/original_target = subject
	if(!istype(original_target) || QDELETED(original_target))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/prompt/choice/client_smite/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/client_smite/refusal(given)
	return null

/client/proc/smite_answered(datum/act/request/A)
	if(!A.answer)
		return
	world.push_usr(A.request.answerer, new /datum/callback(src, PROC_REF(smite)), A.request.subject, A.answer)
