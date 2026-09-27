/client/proc/smite(mob/living/carbon/human/target in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
	set name = "Smite"
	set desc = "Abuse a player with various 'special treatments' from a list."
	set category = "Fun.Do Not"
	if(!check_rights(R_FUN))
		return

	if(!istype(target))
		return

	var/list/smite_types = list(SMITE_BREAKLEGS,SMITE_BLUESPACEARTILLERY,SMITE_SPONTANEOUSCOMBUSTION,SMITE_LIGHTNINGBOLT,
								SMITE_SHADEKIN_ATTACK,SMITE_SHADEKIN_NOMF,SMITE_AD_SPAM,SMITE_REDSPACE_ABDUCT,SMITE_AUTOSAVE,SMITE_AUTOSAVE_WIDE,SMITE_SPICEREQUEST,SMITE_PEPPERNADE,SMITE_TERROR,
								SMITE_PIE, SMITE_SPICE, SMITE_HOTDOG) //pie, spicy air and hot dog

	var/smite_choice = client_prompt("a1", list("kind" = "list", "message" = "Select the type of SMITE for [target]", "title" = "SMITE Type Choice", "choices" = smite_types), PROC_REF(smite), args, R_FUN)
	if(isnull(smite_choice))
		return
	if(!smite_choice)
		return

	if(length(om_answers) <= 1) // Once: later questions of a smite re-run this.
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
			target.visible_message(span_danger("[target] bursts into flames!"))

		if(SMITE_LIGHTNINGBOLT)
			var/turf/T = get_step(get_step(target, NORTH), NORTH)
			T.Beam(target, icon_state="lightning[rand(1,12)]", time = 5)
			target.electrocute_act(75,def_zone = BP_HEAD)
			target.visible_message(span_danger("[target] is struck by lightning!"))

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
			om_run_frame_now(shadekin, /datum/om/pipeline/life)
			//Remove when done
			spawn(10 SECONDS) // S7 keeps: admin verb (allowlist)
				if(shadekin)
					shadekin.death()

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
			var/kin_type = client_prompt("a2", list("kind" = "list", "message" = "Select the type of shadekin for [target] nomf", "title" = "Shadekin Type Choice", "choices" = kin_types), PROC_REF(smite), args, R_FUN)
			if(isnull(kin_type))
				return
			if(!kin_type || !target)
				return


			kin_type = kin_types[kin_type]

			var/myself = client_prompt("a3", list("message" = "Control the shadekin yourself or delete pred and prey after?", "title" = "Control Shadekin?", "choices" = list("Control","Cancel","Delete")), PROC_REF(smite), args, R_FUN)
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
			shadekin.dir = SOUTH
			shadekin.ability_flags |= 0x1
			shadekin.phase_out(get_turf(shadekin)) //Homf
			shadekin.comp.dark_energy = initial(shadekin.comp.dark_energy)
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
			grenade.loc = target.loc
			to_chat(target,span_warning("GRENADE?!"))
			grenade.detonate()

		if(SMITE_SPICEREQUEST)
			var/obj/item/reagent_containers/food/condiment/spacespice/spice = new /obj/item/reagent_containers/food/condiment/spacespice
			spice.loc = target.loc
			to_chat(target,"A bottle of spices appears at your feet... be careful what you wish for!")

		if(SMITE_PIE)
			new/obj/effect/decal/cleanable/pie_smudge(get_turf(target))
			playsound(target, 'sound/effects/slime_squish.ogg', 100, 1, get_rand_frequency(), falloff = 5)
			target.status_at_least(EFFECT_WEAKENED, 1)
			target.visible_message(span_danger("[target] is struck by pie!"))

		if(SMITE_SPICE)
			to_chat(target, span_warning("Spice spice baby!"))
			target.status_at_least(EFFECT_BLURRY, 25)
			target.status_at_least(EFFECT_BLINDED, 10)
			target.status_at_least(EFFECT_STUNNED, 5)
			target.status_at_least(EFFECT_WEAKENED, 5)
			playsound(target, 'sound/effects/spray2.ogg', 100, 1, get_rand_frequency(), falloff = 5)

		if(SMITE_HOTDOG)
			hotdog_smite(target)
		else
			return //Injection? Don't print any messages.

/proc/bluespace_artillery(mob/living/target, user)
	if(!istype(target))
		return

	var/real_user = user ? user : usr
	var/user_name = real_user ? key_name(real_user) : "Remotely (Discord)"

	to_chat(target,"You've been hit by bluespace artillery!")
	log_and_message_admins("has been hit by Bluespace Artillery fired by [user_name]", target)

	target.setMoveCooldown(2 SECONDS)

	var/turf/simulated/floor/T = get_turf(target)
	if(istype(T))
		if(prob(80))	T.break_tile_to_plating()
		else			T.break_tile()

	playsound(T, get_sfx("explosion"), 100, 1, get_rand_frequency(), falloff = 5) // get_sfx() is so that everyone gets the same sound

	if(target.vitality() < 0.1)
		target.gib()
	else
		target.injure(INJURY_BLUNT, max(99, target.get_endurance() * target.vitality() - 1), flags = INJURE_IGNORE_RESISTANCE)
		target.status_at_least(EFFECT_STUNNED, 20)
		target.status_at_least(EFFECT_WEAKENED, 20)
		target.status_set(EFFECT_STUTTERING, 20)

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
	target.transforming = TRUE
	to_chat(target,span_danger("You feel a strange tug, deep inside. You're frozen in momentarily..."))
	to_chat(user,span_notice("Beginning vis_contents copy to abduction site, player mob is frozen."))
	om_after(target, 1 SECOND, GLOBAL_PROC_REF(redspace_abduction_copy), target, user, size_of_square, halfbox)

/// redspace_abduction() a second after the target freezes.
/proc/redspace_abduction_copy(mob/living/target, client/user, size_of_square, halfbox)
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
			T_dest.density = T_src.density
			T_dest.opacity = T_src.opacity
			CHECK_TICK

	//Feather the edges
	for(var/x = llc_x to llc_x+1) //Left
		for(var/y = llc_y to llc_y+size_of_square)
			if(prob(50))
				var/turf/T = locate(x,y,GLOB.redspace_abduction_z)
				T.density = FALSE
				T.opacity = FALSE
				T.vis_contents.Cut()

	for(var/x = llc_x+size_of_square-1 to llc_x+size_of_square) //Right
		for(var/y = llc_y to llc_y+size_of_square)
			if(prob(50))
				var/turf/T = locate(x,y,GLOB.redspace_abduction_z)
				T.density = FALSE
				T.opacity = FALSE
				T.vis_contents.Cut()

	for(var/x = llc_x to llc_x+size_of_square) //Top
		for(var/y = llc_y+size_of_square-1 to llc_y+size_of_square)
			if(prob(50))
				var/turf/T = locate(x,y,GLOB.redspace_abduction_z)
				T.density = FALSE
				T.opacity = FALSE
				T.vis_contents.Cut()

	for(var/x = llc_x to llc_x+size_of_square) //Bottom
		for(var/y = llc_y to llc_y+1)
			if(prob(50))
				var/turf/T = locate(x,y,GLOB.redspace_abduction_z)
				T.density = FALSE
				T.opacity = FALSE
				T.vis_contents.Cut()

	target.forceMove(locate(target.x,target.y,GLOB.redspace_abduction_z))
	to_chat(target,span_danger("The tug relaxes, but everything around you looks... slightly off."))
	to_chat(user, span_notice("The mob has been moved. ([admin_jump_link(target, check_rights_for(usr.client, R_HOLDER))])"))

	target.transforming = FALSE

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

	spawn(10 SECONDS) // S7 keeps: admin verb (allowlist)
		if(target)
			to_chat(target, "<span class='notice' style='font: small-caps bold large monospace!important'>Autosave complete!</span>")
			if(target.client)
				target.client.screen -= loader

/// The shadekin smite's show, a step per timer: turn, turn, turn, belch, then phase back in and
/// either hand the shadekin to `controller_ckey` or take both away.
/proc/shadekin_smite_step(mob/living/simple_mob/shadekin/shadekin, mob/living/target, controller_ckey, step)
	if(QDELETED(shadekin))
		if(target)
			target.transforming = FALSE
		return
	switch(step)
		if(2)
			shadekin.dir = WEST
		if(3)
			shadekin.dir = EAST
		if(4)
			shadekin.dir = SOUTH
		if(5)
			shadekin.audible_message(span_vwarning(span_bold("[shadekin]") + " belches loudly!"), runemessage = "URRRRRP")
		if(6)
			shadekin.phase_in(get_turf(shadekin), shadekin.get_shadekin_component())
			if(target)
				target.transforming = FALSE //Undo cheap hack
			if(controller_ckey) //Put admin in mob
				shadekin.ckey = controller_ckey
			else //Permakin'd
				if(target)
					to_chat(target,span_danger("You're carried off into The Dark by the [shadekin]. Who knows if you'll find your way back?"))
					target.ghostize()
					qdel(target)
				qdel(shadekin)
			return
	om_after(shadekin, step == 5 ? 2 SECONDS : 1 SECOND, GLOBAL_PROC_REF(shadekin_smite_step), shadekin, target, controller_ckey, step + 1)

/// The hot dog smite: a whistle, then two seconds later the costume, gone again after five.
/proc/hotdog_smite(mob/living/target)
	playsound(target, 'sound/effects/whistle.ogg', 50, 1, get_rand_frequency(), falloff = 5)
	om_after(target, 2 SECONDS, GLOBAL_PROC_REF(hotdog_smite_dress), target)

/proc/hotdog_smite_dress(mob/living/target)
	target.status_at_least(EFFECT_STUNNED, 10)
	if(!ishuman(target))
		return
	var/mob/living/carbon/human/H = target
	if(H.get_equipped_item(SLOT_ID_HEAD))
		H.unEquip(H.get_equipped_item(SLOT_ID_HEAD))
	if(H.get_equipped_item(SLOT_ID_SUIT))
		H.unEquip(H.get_equipped_item(SLOT_ID_SUIT))
	var/obj/item/clothing/suit = new /obj/item/clothing/suit/storage/hooded/foodcostume/hotdog
	var/obj/item/clothing/hood = new /obj/item/clothing/head/hood_vr/hotdog_hood
	H.equip_to_slot_if_possible(suit, slot_wear_suit, 0, 0, 1)
	H.equip_to_slot_if_possible(hood, slot_head, 0, 0, 1)
	om_qdel_after(suit, 5 SECONDS)
	om_qdel_after(hood, 5 SECONDS)
