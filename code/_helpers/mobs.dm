/atom/movable/proc/get_mob()
	var/list/mobs = src?.buckled_mob_list()
	if(mobs) return mobs.Copy()

/obj/mecha/get_mob()
	return src?.slot_item(MECHA_SLOT_PILOT)

/obj/vehicle_old/train/get_mob()
	return src?.buckled_mob_list()

/mob/get_mob()
	return src

/mob/living/bot/mulebot/get_mob()
	if(load && isliving(load))
		return list(src, load)
	return src

/proc/mobs_in_view(range, source)
	var/list/mobs = list()
	for(var/atom/movable/AM in view(range, source))
		var/M = AM.get_mob()
		if(M)
			mobs += M

	return mobs

/// This gets a list of mobs ALL around us as if we had xray vision and can see through walls.
/// Currently only used in portable_turret.dm if you wish to see an example of how to use it.
/proc/mobs_in_xray_view(range, source)
	var/list/mobs = list()
	for(var/atom/movable/AM in orange(range, source))
		var/M = AM.get_mob()
		if(M)
			mobs += M

	return mobs
/proc/random_hair_style(gender, species = SPECIES_HUMAN)
	var/h_style = "Bald"

	var/list/valid_hairstyles = list()
	for(var/hairstyle in GLOB.hair_styles_list)
		var/datum/sprite_accessory/S = GLOB.hair_styles_list[hairstyle]
		if(gender == MALE && S.gender == FEMALE)
			continue
		if(gender == FEMALE && S.gender == MALE)
			continue
		if(S.name == DEVELOPER_WARNING_NAME)
			continue
		if(!(species in S.species_allowed))
			continue
		if(!S.can_be_selected)
			continue
		valid_hairstyles[hairstyle] = GLOB.hair_styles_list[hairstyle]

	if(valid_hairstyles.len)
		h_style = pick(valid_hairstyles)

	return h_style

/proc/random_facial_hair_style(gender, species = SPECIES_HUMAN)
	var/f_style = "Shaved"

	var/list/valid_facialhairstyles = list()
	for(var/facialhairstyle in GLOB.facial_hair_styles_list)
		var/datum/sprite_accessory/S = GLOB.facial_hair_styles_list[facialhairstyle]
		if(gender == MALE && S.gender == FEMALE)
			continue
		if(gender == FEMALE && S.gender == MALE)
			continue
		if(S.name == DEVELOPER_WARNING_NAME)
			continue
		if(!(species in S.species_allowed))
			continue
		if(!S.can_be_selected)
			continue

		valid_facialhairstyles[facialhairstyle] = GLOB.facial_hair_styles_list[facialhairstyle]

	if(valid_facialhairstyles.len)
		f_style = pick(valid_facialhairstyles)

	return f_style

/proc/sanitize_name(name, species = SPECIES_HUMAN, robot = 0)
	var/datum/species/current_species
	if(species)
		current_species = GLOB.all_species[species]

	return current_species ? current_species.sanitize_name(name, robot) : sanitizeName(name, MAX_NAME_LEN, robot)

/proc/random_name(gender, species = SPECIES_HUMAN)

	var/datum/species/current_species
	if(species)
		current_species = GLOB.all_species[species]

	if(!current_species || current_species.name_language == null)
		if(gender==FEMALE)
			return capitalize(pick(GLOB.first_names_female)) + " " + capitalize(pick(GLOB.last_names))
		else
			return capitalize(pick(GLOB.first_names_male)) + " " + capitalize(pick(GLOB.last_names))
	else
		return current_species.get_random_name(gender)

/proc/skintone2racedescription(tone)
	switch (tone)
		if(30 to INFINITY)		return "albino"
		if(20 to 30)			return "pale"
		if(5 to 15)				return "light skinned"
		if(-10 to 5)			return "white"
		if(-25 to -10)			return "tan"
		if(-45 to -25)			return "darker skinned"
		if(-65 to -45)			return "brown"
		if(-INFINITY to -65)	return "black"
		else					return "unknown"

/proc/age2agedescription(age)
	switch(age)
		if(0 to 1)			return "infant"
		if(1 to 3)			return "toddler"
		if(3 to 13)			return "child"
		if(13 to 19)		return "teenager"
		if(19 to 30)		return "young adult"
		if(30 to 45)		return "adult"
		if(45 to 60)		return "middle-aged"
		if(60 to 70)		return "aging"
		if(70 to INFINITY)	return "elderly"
		else				return "unknown"

/// Medical-HUD health bar icon_state for a mob, from its vitality() (0..1).
/// Critical mobs show the bottom of the bar.
/proc/vitality_hud_state(mob/living/L)
	var/percent = L.is_critical() ? -100 : round(L.vitality() * 100)
	var/list/icon_states = icon_states_fast(GLOB.ingame_hud_med)
	for(var/icon_state in icon_states)
		if(percent >= text2num(icon_state))
			return icon_state
	return icon_states[icon_states.len] // If we had no match, return the last element

/// The one vitality -> "health0".."health7" band table for a mob's own health meter
/// (robots, brains, aliens, pAIs, simple mobs). Dead or faking death reads "health7",
/// critical or no vitality reads "health6".
/proc/vitality_health_band(mob/living/L)
	if(L.stat == DEAD || (L.status_flags & FAKEDEATH))
		return "health7"
	if(L.is_critical())
		return "health6"
	var/percent = L.vitality() * 100
	if(percent >= 100)
		return "health0"
	if(percent >= 80)
		return "health1"
	if(percent >= 60)
		return "health2"
	if(percent >= 40)
		return "health3"
	if(percent >= 20)
		return "health4"
	if(percent > 0)
		return "health5"
	return "health6"

/*
Proc for attack log creation, because really why not
1 argument is the actor
2 argument is the target of action
3 is the description of action(like punched, throwed, or any other verb)
4 should it make adminlog note or not
5 is the tool with which the action was made(usually item)					5 and 6 are very similar(5 have "by " before it, that it) and are separated just to keep things in a bit more in order
6 is additional information, anything that needs to be added
*/

/proc/add_attack_logs(mob/user, mob/target, what_done, admin_notify = TRUE)
	if(islist(target)) //Multi-victim adding
		var/list/targets = target
		for(var/mob/M in targets)
			add_attack_logs(user,M,what_done,admin_notify)
		return

	var/target_str = key_name(target)

	log_combat(user, target, what_done)
	if(admin_notify)
		msg_admin_attack("[key_name_admin(user)] vs [target_str]: [what_done]")

//checks whether this item is a module of the robot it is located in.
/proc/is_robot_module(obj/item/thing)
	if (!thing || !isrobot(thing.loc))
		return 0
	var/mob/living/silicon/robot/R = thing.loc
	return (thing in R.module.modules)

/proc/get_exposed_defense_zone(atom/movable/target)
	var/obj/item/grab/G = locate_within(target, /obj/item/grab)
	if(G && G.state >= GRAB_NECK) //works because mobs are currently not allowed to upgrade to NECK if they are grabbing two people.
		return pick(BP_HEAD, BP_L_HAND, BP_R_HAND, BP_L_FOOT, BP_R_FOOT, BP_L_ARM, BP_R_ARM, BP_L_LEG, BP_R_LEG)
	else
		return pick(BP_TORSO, BP_GROIN)

/atom/proc/living_mobs(range = world.view, count_held = FALSE)
	var/list/viewers = oviewers(src,range)
	if(count_held)
		viewers = viewers(src,range)
	var/list/living = list()
	for(var/mob/living/L in viewers)
		living += L
		if(count_held)
			for(var/obj/item/holder/H in contents_of(L))
				if(istype(H.held_mob, /mob/living))
					living += H.held_mob
	return living

/atom/proc/human_mobs(range = world.view)
	var/list/viewers = oviewers(src,range)
	var/list/humans = list()
	for(var/mob/living/carbon/human/H in viewers)
		humans += H

	return humans

DECLARE_SHARED_CACHE_EX(character_icons, GLOBAL_PROC_REF(build_character_icon), SC_NEVER, 512, 0)

/proc/build_character_icon(mob/desired)
	return getCompoundIcon(desired)

/proc/cached_character_icon(mob/desired)
	// A mob has no registry id: SHARED_CACHE_UID() is never reused, where a ref would be.
	return CACHED_KEY(character_icons, "[SHARED_CACHE_UID(desired)]|[desired.real_name]", desired)

/proc/not_has_ooc_text(mob/user)
	if (CONFIG_GET(flag/allow_metadata) && (!user.client?.prefs?.read_preference(/datum/preference/text/living/ooc_notes) || length(user.client.prefs.read_preference(/datum/preference/text/living/ooc_notes)) < 15))
		to_chat(user, span_warning("Please set informative OOC notes related to RP/ERP preferences. Set them using the 'OOC Notes' button on the 'General' tab in character setup."))
		return TRUE
	return FALSE

///Makes a call in the context of a different usr. Use sparingly
/world/proc/push_usr(mob/user_mob, datum/callback/invoked_callback, ...)
	var/temp = usr
	usr = user_mob
	if (length(args) > 2)
		. = invoked_callback.Invoke(arglist(args.Copy(3)))
	else
		. = invoked_callback.Invoke()
	usr = temp
