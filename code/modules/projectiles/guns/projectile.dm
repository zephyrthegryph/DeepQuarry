/obj/item/gun/projectile
	name = "gun"
	desc = "A gun that fires bullets."
	icon_state = "revolver"
	w_class = ITEMSIZE_NORMAL
	MATERIAL_BULK(MAT_STEEL, 1000)
	recoil = 1
	projectile_type = /obj/item/projectile/bullet/pistol/strong	//Only used for chameleon guns

	var/caliber = ".357"		//determines which casings will fit
	var/handle_casings = EJECT_CASINGS	//determines how spent casings should be handled
	var/load_method = SINGLE_CASING|SPEEDLOADER //1 = Single shells, 2 = box or quick loader, 3 = magazine
	var/obj/item/ammo_casing/chambered = null

	reload_time = 1				//Ballistics reload fast, but not instantly

	//For SINGLE_CASING or SPEEDLOADER guns
	var/max_shells = 0			//the number of casings that will fit inside
	var/ammo_type = null		//the type of ammo that the gun comes preloaded with
	// ALLOW(instance_list): d: guns spawn loaded; the chamber list is indexed everywhere
	var/list/loaded = list()	//stored ammo

	//For MAGAZINE guns
	var/magazine_type = null	//the type of magazine that the gun comes preloaded with
	var/obj/item/ammo_magazine/ammo_magazine = null //stored magazine
	var/allowed_magazines		//determines list of which magazines will fit in the gun
	var/auto_eject = 0			//if the magazine should automatically eject itself when empty.
	var/auto_eject_sound = null
	//TODO generalize ammo icon states for guns
	//var/magazine_states = 0
	//var/list/icon_keys = list()		//keys
	//var/list/ammo_states = list()	//values

	var/random_start_ammo = FALSE	//randomize amount of starting ammo

	special_handling = TRUE

	///Var for attack_self chain
	var/special_weapon_handling = FALSE

CAPABILITIES(/obj/item/gun/projectile)
	// chambered names a casing in the gun (loaded) or its magazine (stored_ammo): a relation view.
	ref_one(nameof(chambered))
	owns_many(nameof(loaded))
	param(nameof(starts_loaded), pos = 1)

TYPE_TABLE_DECLARE(/obj/item/gun/projectile, projectile_initial_transform, FALSE)

/// Whether the gun starts loaded (its constructor param).
/obj/item/gun/projectile/var/starts_loaded = TRUE

// ALLOW(init/INSTANCE_STATE): a projectile gun loads its starting rounds or magazine (some randomly short) and takes its transform
/obj/item/gun/projectile/Initialize(mapload)
	. = ..()
	if(starts_loaded)
		if(ispath(ammo_type) && (load_method & (SINGLE_CASING|SPEEDLOADER)))
			for(var/i in 1 to max_shells)
				rel_add(src, nameof(loaded), new ammo_type(src))
			if(random_start_ammo)
				for(var/i in 1 to rand(0, max_shells))
					if(!length(loaded))
						break
					own_remove(src, nameof(loaded), loaded[1])
		if(ispath(magazine_type) && (load_method & MAGAZINE))
			rel_set(src, nameof(ammo_magazine), new magazine_type(src))
			allowed_magazines += /obj/item/ammo_magazine/smart
			if(random_start_ammo)
				var/ammo_cut = rand(0,ammo_magazine.max_ammo)
				for(var/i in 1 to min(ammo_cut, length(ammo_magazine.stored_ammo)))
					own_remove(ammo_magazine, nameof(ammo_magazine.stored_ammo), ammo_magazine.stored_ammo[1])

	update_icon()
	if(TYPE_TABLE_GET(src, projectile_initial_transform))
		update_transform()

/obj/item/gun/projectile/consume_next_projectile()
	if(!manual_chamber) // Manual Chambering
		//get the next casing
		if(length(loaded))
			rel_set(src, nameof(chambered), loaded[1]) //load next casing.
			if(handle_casings != HOLD_CASINGS)
				own_take_member(src, nameof(loaded), chambered)
		else if(ammo_magazine && length(ammo_magazine.stored_ammo))
			rel_set(src, nameof(chambered), ammo_magazine.stored_ammo[length(ammo_magazine.stored_ammo)])
			if(handle_casings != HOLD_CASINGS)
				own_take_member(ammo_magazine, nameof(ammo_magazine.stored_ammo), chambered)
	if(manual_chamber && auto_loading_type && CHECK_BITFIELD(auto_loading_type,OPEN_BOLT) && bolt_open)
		chamber_bullet() // Manual Chambering

	var/mob/living/M = loc // TGMC Ammo HUD
	if(istype(M)) // TGMC Ammo HUD
		M?.hud_used?.update_ammo_hud(M, src)

	if (chambered)
		return chambered.BB
	return null

/obj/item/gun/projectile/handle_click_empty()
	..()
	if(!manual_chamber) // Manual Chambering
		process_chambered() // Manual Chambering

/obj/item/gun/projectile/proc/process_chambered()
	if (!chambered) return

	// Aurora forensics port, gunpowder residue.
	if(chambered.leaves_residue)
		var/mob/living/carbon/human/H = loc
		if(istype(H))
			if(!istype(H.get_equipped_item(SLOT_ID_GLOVES), /obj/item/clothing))
				H.add_gunshotresidue(chambered)
			else
				var/obj/item/clothing/G = H.get_equipped_item(SLOT_ID_GLOVES)
				G.add_gunshotresidue(chambered)

	switch(handle_casings)
		if(EJECT_CASINGS) //eject casing onto ground.
			if(chambered.caseless)
				consume(chambered)
				return
			else
				chambered.forceMove(get_turf(src))
				play_sfx(src, SFX_CASING_SOUND)
		if(CYCLE_CASINGS) //cycle the casing back to the end.
			if(ammo_magazine)
				rel_add(ammo_magazine, nameof(ammo_magazine.stored_ammo), chambered)
			else
				rel_add(src, nameof(loaded), chambered)

	if(handle_casings != HOLD_CASINGS)
		rel_clear(src, nameof(chambered))

	var/mob/living/M = loc // TGMC Ammo HUD
	if(istype(M)) // TGMC Ammo HUD
		M?.hud_used?.update_ammo_hud(M, src)

//attempts to unload src. If allow_dump is set to 0, the speedloader unloading method will be disabled
/obj/item/gun/projectile/proc/unload_ammo(mob/user, allow_dump=1)
	if(manual_chamber && only_open_load && !bolt_open) // Manual Chambering
		to_chat(user,span_warning("You must open the bolt to load or unload this gun!")) // Manual Chambering
		return // Manual Chambering

	if(ammo_magazine)
		user.put_in_hands(ammo_magazine)
		act_message(user, src, MSG_SELF(span_notice("You remove [ammo_magazine] from %T%.")), MSG_OTHERS("%U% removes [ammo_magazine] from %T%."))
		play_sfx(src, SFX_WEAPONS_EMPTY)
		ammo_magazine.update_icon()
		own_take(src, nameof(ammo_magazine))
		user.hud_used?.update_ammo_hud(user, src)
	else if(length(loaded))
		//presumably, if it can be speed-loaded, it can be speed-unloaded.
		if(allow_dump && (load_method & SPEEDLOADER))
			var/count = 0
			var/turf/T = get_turf(user)
			if(T)
				for(var/obj/item/ammo_casing/C in loaded)
					C.forceMove(T)
					count++
				own_take_all(src, nameof(loaded))
			if(count)
				act_message(user, src, MSG_SELF(span_notice("You unload [count] round\s from %T%.")), MSG_OTHERS("%U% unloads %T%."))
		else if(load_method & SINGLE_CASING)
			var/obj/item/ammo_casing/C = own_take_member(src, nameof(loaded), loaded[length(loaded)])
			user.put_in_hands(C)
			act_message(user, src, MSG_SELF(span_notice("You remove \a [C] from %T%.")), MSG_OTHERS("%U% removes \a [C] from %T%."))
		play_sfx(src, SFX_WEAPONS_EMPTY)
		user.hud_used?.update_ammo_hud(user, src)
	else
		to_chat(user, span_warning("[src] is empty."))
	update_icon()
	user.hud_used?.update_ammo_hud(user, src)

/// Old attackby: the parent's first, then loading.
/obj/item/gun/projectile/gun_item(mob/user, obj/item/A, datum/interaction/interaction)
	. = ..()
	load_ammo(A, user)

/// Old attack_self.
/obj/item/gun/projectile/gun_self(mob/user, obj/item/held, datum/interaction/interaction, callback)
	. = ..()
	if(.)
		return TRUE
	if(special_weapon_handling && !callback)
		return FALSE
	if(manual_chamber) // Gun Rework
		om_task_timed(user, 0.4 SECONDS, src, src, PROC_REF(bolt_handle), list(user, interaction?.stance)) // Gun Rework
	else if(length(firemodes) > 1) // Gun Rework
		switch_firemodes(user)
	else
		unload_ammo(user)

EXTEND_INTERACTIONS(/obj/item/gun/projectile, INTERACT_HAND_UNGATED("Unload", PROC_REF(gun_hand)))

/// Old attack_hand: unload from the off hand. Subtypes override it with ..(); FALSE goes on to pickup.
/obj/item/gun/projectile/proc/gun_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(user.get_inactive_hand() == src)
		unload_ammo(user, allow_dump=0)
		return TRUE
	return FALSE

/obj/item/gun/projectile/afterattack(atom/A, mob/living/user)
	..()
	if(auto_eject && ammo_magazine && ammo_magazine.stored_ammo && !length(ammo_magazine.stored_ammo) && !(manual_chamber && chambered && chambered.BB != null)) // Manual Chambering
		ammo_magazine.forceMove(get_turf(src.loc))
		act_message(user, null, MSG_SELF(span_notice("[ammo_magazine] falls out and clatters on the floor!")), \
			MSG_OTHERS("[ammo_magazine] falls out and clatters on the floor!"))
		if(auto_eject_sound)
			playsound(src, auto_eject_sound, 40, 1)
		ammo_magazine.update_icon()
		own_take(src, nameof(ammo_magazine))
		update_icon() //make sure to do this after unsetting ammo_magazine
		user.hud_used?.update_ammo_hud(user, src)

/obj/item/gun/projectile/examine(mob/user)
	. = ..()
	if(ammo_magazine)
		. += "It has \a [ammo_magazine] loaded."
	. += "It has [getAmmo()] round\s remaining."

/obj/item/gun/projectile/proc/getAmmo()
	var/bullets = 0
	if(loaded)
		bullets += length(loaded)
	if(ammo_magazine && ammo_magazine.stored_ammo)
		bullets += length(ammo_magazine.stored_ammo)
	if(chambered)
		bullets += 1
	return bullets


// TGMC Ammo HUD Insertion
/obj/item/gun/projectile/has_ammo_counter()
	return TRUE

/obj/item/gun/projectile/get_ammo_type()
	if(load_method & MAGAZINE)
		if(chambered) // Do we have an ammo casing chambered
			var/obj/item/ammo_casing/A = chambered
			var/obj/item/projectile/P = A.projectile_type
			return list(initial(P.hud_state), initial(P.hud_state_empty))
		else if(ammo_magazine && length(ammo_magazine.stored_ammo)) // Do we have a mag, and have ammo in the mag, but nothing chambered?
			var/obj/item/ammo_casing/A = ammo_magazine.stored_ammo[1]
			var/obj/item/projectile/P = A.projectile_type
			return list(initial(P.hud_state), initial(P.hud_state_empty))
		else if(src.projectile_type) // Else, we're entirely empty, and irregardless of the mag we have loaded (as it's empty, or it would've passed the length check above), return the DEFAULT projectile_type on the gun, if set.
			var/obj/item/projectile/P = src.projectile_type
			return list(initial(P.hud_state), initial(P.hud_state_empty))
		else
			return list("unknown", "unknown") // Safety, this shouldn't happen, but just in case
	else if(load_method & (SINGLE_CASING|SPEEDLOADER)) // Do we load with single casings OR speedloaders?
		if(chambered) // Do we have an ammo casing loaded in the chamber? All casings still have a projectile_type var.
			var/obj/item/ammo_casing/A = chambered
			var/obj/item/projectile/P = A.projectile_type
			return list(initial(P.hud_state), initial(P.hud_state_empty)) // Return the casing's projectile_type ammo hud state
		else if(length(loaded)) // Else, is the gun loaded, but no ammo casings in chamber currently?
			var/obj/item/ammo_casing/A = loaded[1]
			var/obj/item/projectile/P = A.projectile_type
			return list(initial(P.hud_state), initial(P.hud_state_empty)) // Return the ammunition loaded in the gun's hud_state
		else if(src.projectile_type) // Else, we're entirely empty, and have nothing loaded in the gun, and nothing in the chamber. Return the DEFAULT projectile_type on the gun, if set.
			var/obj/item/projectile/P = src.projectile_type
			return list(initial(P.hud_state), initial(P.hud_state_empty))
		else
			return list("unknown", "unknown") // Safety, this shouldn't happen, but just in case
	else if(src.projectile_type) // Failsafe if we somehow don't pass the above. Return the DEFAULT projectile_type on the gun, if set.
		var/obj/item/projectile/P = src.projectile_type
		return list(initial(P.hud_state), initial(P.hud_state_empty))
	else  // Failsafe if we somehow fail all three methods
		return list("unknown", "unknown")

/obj/item/gun/projectile/get_ammo_count()
	if(ammo_magazine) // Do we have a magazine loaded?
		var/shots_left
		if(chambered && chambered.BB) // Do we have a bullet in the currently-chambered casing, if any?
			shots_left++
		for(var/obj/item/ammo_casing/bullet in ammo_magazine.stored_ammo)
			if(bullet.BB)
				shots_left++

		if(shots_left > 0)
			return shots_left
		else
			return 0 // No ammo left or failsafe.
	else if(loaded) // Do we use internal ammunition
		var/shots_left
		if(chambered && chambered.BB) // Do we have a bullet in the currently-chambered casing, if any?
			shots_left++
		for(var/obj/item/ammo_casing/bullet in loaded)
			if(bullet.BB) // Only increment how many shots we have left if we're loaded.
				shots_left++

		if(shots_left > 0)
			return shots_left
		else
			return 0 // No ammo left or failsafe.
	else if(chambered) // If we don't have a magazine or internal ammunition loaded, but we have a casing in chamber, return the amount.
		return chambered.BB ? 1 : 0
	else // Failsafe, or completely unloaded
		return 0

#define BOLT_NOEVENT 0
#define BOLT_CLOSED 1
#define BOLT_OPENED 2
#define BOLT_LOCKED 4
#define BOLT_UNLOCKED 8
#define BOLT_CASING_EJECTED 16
#define BOLT_CASING_CHAMBERED 32

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////// CADYN'S BALLISTICS ////////////////////////////////////////////////////////////////////////// ORIGINAL FROM CHOMPSTATION ////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/obj/item/gun/projectile
	var/manual_chamber = TRUE
	var/only_open_load = FALSE
	var/auto_loading_type = CLOSED_BOLT | LOCK_MANUAL_LOCK | LOCK_SLAPPABLE
	var/misc_loading_flags = 0
	var/bolt_name = "bolt"
	var/bolt_open = FALSE
	var/bolt_locked = FALSE
	var/bolt_release = "bolt release"
	var/sound_ejectchamber = SFX_WEAPONS_BALLISTICS_PISTOL_EJECTCHAMBER
	var/sound_eject = SFX_WEAPONS_BALLISTICS_PISTOL_EJECT
	var/sound_chamber = SFX_WEAPONS_BALLISTICS_PISTOL_CHAMBER
	special_handling = TRUE
TRACKED(/obj/item/gun/projectile, bolt_open)

/obj/item/gun/projectile/handle_post_fire(mob/user, atom/target, pointblank=0, reflex=0)
	if(fire_anim)
		flick(fire_anim, src)

	if(muzzle_flash)
		set_light(muzzle_flash)

	if(one_handed_penalty)
		if(!src.is_held_twohanded(user))
			switch(one_handed_penalty)
				if(1 to 15)
					if(prob(50)) //don't need to tell them every single time
						to_chat(user, span_warning("Your aim wavers slightly."))
				if(16 to 30)
					to_chat(user, span_warning("Your aim wavers as you fire \the [src] with just one hand."))
				if(31 to 45)
					to_chat(user, span_warning("You have trouble keeping \the [src] on target with just one hand."))
				if(46 to INFINITY)
					to_chat(user, span_warning("You struggle to keep \the [src] on target with just one hand!"))
		else if(!user.can_wield_item(src))
			switch(one_handed_penalty)
				if(1 to 15)
					if(prob(50)) //don't need to tell them every single time
						to_chat(user, span_warning("Your aim wavers slightly."))
				if(16 to 30)
					to_chat(user, span_warning("Your aim wavers as you try to hold \the [src] steady."))
				if(31 to 45)
					to_chat(user, span_warning("You have trouble holding \the [src] steady."))
				if(46 to INFINITY)
					to_chat(user, span_warning("You struggle to hold \the [src] steady!"))

	if(recoil)
		shake_camera(user, recoil+1, recoil)
	update_icon()

	if(chambered)
		chambered.expend()
		if(!manual_chamber) process_chambered()
	if(manual_chamber && auto_loading_type)
		bolt_toggle()

/// Works the bolt; `stance` I_HURT slaps the release (flavour).
/obj/item/gun/projectile/proc/bolt_handle(mob/user, stance)
	var/previous_chambered = chambered
	var/result = bolt_toggle(TRUE)
	update_icon()
	if(!result)
		to_chat(user,span_notice("Nothing happens."))
	else
		var/closed = CHECK_BITFIELD(result,BOLT_CLOSED)
		var/opened = CHECK_BITFIELD(result,BOLT_OPENED)
		var/locked = CHECK_BITFIELD(result,BOLT_LOCKED)
		var/unlocked = CHECK_BITFIELD(result,BOLT_UNLOCKED)
		var/casing_ejected = CHECK_BITFIELD(result,BOLT_CASING_EJECTED)
		var/close_open_ejected = casing_ejected ? ", which causes \the [previous_chambered] to be ejected, as well as" : ","
		var/other_ejected = CHECK_BITFIELD(result,BOLT_CASING_CHAMBERED) ? " and causing \the [previous_chambered] to be ejected" : ", causing \the [previous_chambered] to be ejected"
		other_ejected = casing_ejected ? other_ejected : ""
		var/casing_chambered = CHECK_BITFIELD(result,BOLT_CASING_CHAMBERED) ? ", chambering a new round" : ""
		if(closed && opened)
			playsound(src, sound_ejectchamber, 50, 0)
			act_message(user, null, MSG_SELF(span_notice("You pull back \the [bolt_name] before releasing it[close_open_ejected] causing it to slide forward again[casing_chambered].")), \
				MSG_OTHERS(span_notice("%U% pulls back \the [bolt_name] before releasing it[close_open_ejected] causing it to slide forward again[casing_chambered].")))
			user.hud_used?.update_ammo_hud(user, src)
		else if(opened)
			playsound(src, sound_eject, 50, 0)
			if(locked)
				if(CHECK_BITFIELD(auto_loading_type,LOCK_MANUAL_LOCK))
					playsound(src, sound_ejectchamber, 50, 0)
					act_message(user, null, MSG_SELF(span_notice("You pull back \the [bolt_name] and lock it in the open position[other_ejected][casing_chambered].")), \
						MSG_OTHERS(span_notice("%U% pulls back \the [bolt_name] and locks it in the open position[casing_chambered][other_ejected].")))
				else
					act_message(user, null, MSG_SELF(span_notice("You pull back \the [bolt_name] before releasing it, causing it to lock in the open position[casing_chambered][other_ejected].")), \
						MSG_OTHERS(span_notice("%U% pulls back \the [bolt_name] before releasing it, causing it to lock in the open position[casing_chambered][other_ejected].")))
			else
				act_message(user, null, MSG_SELF(span_notice("You pull back \the [bolt_name][casing_chambered][other_ejected].")), \
					MSG_OTHERS(span_notice("%U% opens \the [bolt_name][casing_chambered][other_ejected].")))
		else if(closed)
			playsound(src, sound_chamber, 50, 0)
			if(unlocked)
				if(bolt_release)
					if(stance == I_HURT && CHECK_BITFIELD(auto_loading_type,LOCK_SLAPPABLE))
						act_message(user, null, MSG_SELF(span_notice("You slap the [bolt_release], causing \the [bolt_name] to slide forward[casing_chambered]!")), \
							MSG_OTHERS(span_notice("%U% slaps the [bolt_release], causing \the [bolt_name] to slide forward[casing_chambered]!")))
					else
						act_message(user, null, MSG_SELF(span_notice("You press the [bolt_release], causing \the [bolt_name] to slide forward[casing_chambered].")), \
							MSG_OTHERS(span_notice("%U% presses the [bolt_release], causing \the [bolt_name] to slide forward[casing_chambered].")))
				else
					act_message(user, null, MSG_SELF(span_notice("You pull \the [bolt_name] back the rest of the way, causing it to slide forward[casing_chambered].")), \
						MSG_OTHERS(span_notice("%U% pulls \the [bolt_name] back the rest of the way, causing it to slide forward[casing_chambered].")))
			else
				act_message(user, null, MSG_SELF(span_notice("You close \the [bolt_name][casing_chambered].")), \
					MSG_OTHERS(span_notice("%U% closes \the [bolt_name][casing_chambered].")))
		user.hud_used?.update_ammo_hud(user, src)

/obj/item/gun/projectile/proc/bolt_toggle(manual)
	if(!bolt_open)
		if(auto_loading_type)
			var/able_to_lock = (CHECK_BITFIELD(auto_loading_type,LOCK_OPEN_EMPTY) || (CHECK_BITFIELD(auto_loading_type,LOCK_MANUAL_LOCK) && manual))
			if(CHECK_BITFIELD(auto_loading_type,OPEN_BOLT))
				set_bolt_open(TRUE)
				var/ejected = process_chambered()
				var/output = BOLT_OPENED
				if(ejected) output |= BOLT_CASING_EJECTED
				return output
			else if(length(loaded) || (ammo_magazine && length(ammo_magazine.stored_ammo)) || !able_to_lock)
				var/ejected = process_chambered()
				var/chambering = chamber_bullet()
				var/output = BOLT_OPENED | BOLT_CLOSED
				if(ejected) output |= BOLT_CASING_EJECTED
				if(chambering) output |= BOLT_CASING_CHAMBERED
				return output
			else
				if(!manual)
					visible_message(src,span_notice("The [src] fires its last round, causing the [bolt_name] to lock."))
				set_bolt_open(TRUE)
				bolt_locked = TRUE
				var/ejected = process_chambered()
				var/output = BOLT_OPENED | BOLT_LOCKED
				if(ejected) output |= BOLT_CASING_EJECTED
				return output
		else
			set_bolt_open(TRUE)
			var/ejected = process_chambered()

			var/output = BOLT_OPENED
			if(ejected) output |= BOLT_CASING_EJECTED
			return output
	else
		if(auto_loading_type)
			if(CHECK_BITFIELD(auto_loading_type,OPEN_BOLT))
				if(length(loaded) || (ammo_magazine && length(ammo_magazine.stored_ammo)))
					if(!manual)
						var/ejected = process_chambered()
						var/output = BOLT_CLOSED | BOLT_OPENED
						if(ejected) output |= BOLT_CASING_EJECTED
						return output
					else
						return BOLT_NOEVENT
				else
					set_bolt_open(FALSE)
					return BOLT_CLOSED
			else if(bolt_locked)
				var/chambering = FALSE
				if(!chambered)
					chambering = chamber_bullet()
				bolt_locked = FALSE
				set_bolt_open(FALSE)
				var/output = BOLT_CLOSED | BOLT_UNLOCKED
				if(chambering) output |= BOLT_CASING_CHAMBERED
				return output
			else
				set_bolt_open(FALSE)
				return BOLT_CLOSED
		else
			set_bolt_open(FALSE)
			var/output = BOLT_CLOSED
			var/chambering = chamber_bullet()
			if(chambering) output |= BOLT_CASING_CHAMBERED
			return output

/obj/item/gun/projectile/proc/chamber_bullet()
	if(chambered)
		return FALSE
	var/obj/item/ammo_casing/to_chamber
	if(length(loaded))
		to_chamber = loaded[1] //load next casing.
		if(handle_casings != HOLD_CASINGS)
			own_take_member(src, nameof(loaded), to_chamber)
	else if(ammo_magazine && length(ammo_magazine.stored_ammo))
		to_chamber = ammo_magazine.stored_ammo[length(ammo_magazine.stored_ammo)]
		if(handle_casings != HOLD_CASINGS)
			own_take_member(ammo_magazine, nameof(ammo_magazine.stored_ammo), to_chamber)
	rel_set(src, nameof(chambered), to_chamber)
	if(to_chamber)
		return TRUE
	else
		return FALSE

// Feeds rounds one at a time from a loose handful into a gun with an internal
// store (revolver / shotgun / internal-mag), respecting capacity and bolt state.
/obj/item/gun/projectile/proc/feed_from_handful(obj/item/ammo_magazine/handful/H, mob/user)
	if(!(load_method & (SINGLE_CASING|SPEEDLOADER)) || (misc_loading_flags & INTERNAL_MAG_SEPARATE))
		to_chat(user, span_warning("You can't thumb loose rounds into \the [src]."))
		return
	if(H.caliber != caliber)
		to_chat(user, span_warning("\The [H] doesn't fit \the [src]."))
		return
	if(only_open_load && !bolt_open)
		to_chat(user, span_warning("[src] must have its bolt open to be loaded!"))
		return
	if(length(loaded) >= max_shells)
		to_chat(user, span_warning("[src] is full."))
		return
	// The handful may still hold its rounds as a count (C5) if it was
	// picked straight off a turf or out of a latent holder.
	H.make_rounds_real()
	to_chat(user, span_notice("You start feeding rounds into \the [src]."))
	if(can_feed_from(H))
		om_task_start(/datum/om/task/timed/feed_rounds, user, src, handful = H)
		return
	feed_done(H, user, 0)

/// TRUE while the handful's next round fits and there is room for it.
/obj/item/gun/projectile/proc/can_feed_from(obj/item/ammo_magazine/handful/H)
	if(QDELETED(H) || !length(H.stored_ammo) || length(loaded) >= max_shells)
		return FALSE
	var/obj/item/ammo_casing/rd = H.stored_ammo[length(H.stored_ammo)]
	return rd.caliber == caliber

/// Feeding rounds from a handful, one per reload_time, until the gun is full or the handful out.
/datum/om/task/timed/feed_rounds
	steps = list(/obj/item/gun/projectile/proc/feed_round = 0)
	complete_proc = /obj/item/gun/projectile/proc/feed_ended
	cancel_proc = /obj/item/gun/projectile/proc/feed_ended
	var/obj/item/ammo_magazine/handful/handful
	var/count = 0
	var/waited = FALSE

/obj/item/gun/projectile/proc/feed_round(datum/om/task/timed/feed_rounds/task)
	if(!task.waited)
		task.waited = TRUE
		return STEP_REPEAT(reload_time)
	// re-validate after the wait; the stack may have shrunk or moved.
	var/obj/item/ammo_magazine/handful/H = task.handful
	if(!can_feed_from(H))
		return STEP_DONE
	var/obj/item/ammo_casing/rd = H.stored_ammo[length(H.stored_ammo)]
	rd.forceMove(src)
	own_transfer(H, nameof(H.stored_ammo), src, nameof(loaded), rd)
	moveElement(loaded, length(loaded), 1) //to the head of the list
	play_sfx(src, SFX_WEAPONS_EMPTY)
	var/mob/user = task.actor
	user.hud_used?.update_ammo_hud(user, src)
	task.count++
	return can_feed_from(H) ? STEP_REPEAT(reload_time) : STEP_DONE

/obj/item/gun/projectile/proc/feed_ended(datum/om/task/timed/feed_rounds/task)
	feed_done(task.handful, task.actor, task.count)

/obj/item/gun/projectile/proc/feed_done(obj/item/ammo_magazine/handful/H, mob/user, count)
	if(count && user)
		act_message(user, src, MSG_SELF(span_notice("You load [count] round\s into %T%.")), MSG_OTHERS("%U% feeds [count] round\s into %T%."))
	if(H && !QDELETED(H) && !length(H.stored_ammo))
		consume(H, user)
	update_icon()

// Attempts to load A into src, depending on the type of thing being loaded and the load_method.
// Handles magazine/speedloader/single-casing/storage bulk loads, including the manual-chamber
// and bolt mechanics keyed off auto_loading_type.
/obj/item/gun/projectile/proc/load_ammo(obj/item/A, mob/user)
	if(istype(A, /obj/item/ammo_magazine/handful)) //loose-round stack: deliberate per-round feed
		feed_from_handful(A, user)
		return
	if(istype(A, /obj/item/ammo_magazine))
		var/obj/item/ammo_magazine/AM = A
		if(!(load_method & AM.mag_type) || caliber != AM.caliber || allowed_magazines && !is_type_in_list(A, allowed_magazines))
			to_chat(user, span_warning("[AM] won't load into [src]!"))
			return
		// Legacy gun code reads stored_ammo directly below (C5); a magazine
		// picked straight off a turf or out of a latent holder still holds
		// its rounds as a count until now.
		AM.make_rounds_real()
		var/loading_method = AM.mag_type & load_method
		if(loading_method == (MAGAZINE & SPEEDLOADER)) loading_method = MAGAZINE //Default to magazine if both are valid
		switch(loading_method)
			if(MAGAZINE)
				if(ammo_magazine)
					to_chat(user, span_warning("[src] already has a magazine loaded.")) //already a magazine here
					return
				if(manual_chamber && CHECK_BITFIELD(auto_loading_type,OPEN_BOLT) && bolt_open)
					to_chat(user, span_warning("This is an open bolt gun. Make sure you close the bolt before inserting a new magazine."))
					return
				if(!move_into(src, nameof(src.ammo_magazine), AM, user))
					return
				act_message(user, src, MSG_SELF(span_notice("You insert [AM] into %T%.")), MSG_OTHERS("%U% inserts [AM] into %T%."))
				if(manual_chamber && CHECK_BITFIELD(auto_loading_type,CHAMBER_ON_RELOAD) && bolt_open && !chambered)
					chamber_bullet()
					bolt_toggle()
				play_sfx(src, SFX_WEAPONS_FLIPBLADE)
				user.hud_used?.update_ammo_hud(user, src)
			if(SPEEDLOADER)
				if(only_open_load && !bolt_open)
					to_chat(user, span_warning("[src] must have its bolt open to be loaded!"))
					return
				if(length(loaded) >= max_shells)
					to_chat(user, span_warning("[src] is full!"))
					return
				var/count = 0
				for(var/obj/item/ammo_casing/C in AM.stored_ammo)
					if(length(loaded) >= max_shells)
						break
					if(C.caliber == caliber)
						C.forceMove(src)
						own_transfer(AM, nameof(AM.stored_ammo), src, nameof(loaded), C) //should probably go inside an ammo_magazine proc, but I guess less proc calls this way...
						count++
				if(count)
					act_message(user, src, MSG_SELF(span_notice("You load [count] round\s into %T%.")), MSG_OTHERS("%U% reloads %T%."))
					play_sfx(src, SFX_WEAPONS_EMPTY)
					user.hud_used?.update_ammo_hud(user, src)
	else if(istype(A, /obj/item/ammo_casing))
		var/obj/item/ammo_casing/C = A
		if(caliber != C.caliber)
			return
		if(!(load_method & SINGLE_CASING) || (misc_loading_flags & INTERNAL_MAG_SEPARATE)) //INTERNAL_MAG_SEPARATE is pretty much exclusively for the SPAS-12
			if(manual_chamber)
				if(!CHECK_BITFIELD(auto_loading_type,OPEN_BOLT))
					if(!chambered)
						if(bolt_open)
							om_task_start(/datum/om/task/timed/projectile_chamber_round, user, src, duration = 0.5 SECONDS, C = C, message = "[user] slides \the [C] into the [src]'s chamber.")
							return
						else if(!(CHECK_BITFIELD(auto_loading_type,LOCK_OPEN_EMPTY) || (CHECK_BITFIELD(auto_loading_type,LOCK_MANUAL_LOCK))))
							om_task_start(/datum/om/task/timed/projectile_chamber_round, user, src, duration = 1.5 SECONDS, C = C, message = "[user] holds open \the [src]'s [bolt_name] and slides [C] into the chamber before letting the bolt close again.")
							return
						else
							to_chat(user,span_warning("Open the bolt first before chambering a round!"))
							return
					else
						to_chat(user,span_warning("Eject the current chambered round before trying to chamber a new one!"))
						return
				else
					to_chat(user,span_warning("You can't manually chamber rounds with an open bolt gun!"))
					return
			else
				return
		if(only_open_load && !bolt_open)
			to_chat(user, span_warning("[src] must have its bolt open to be loaded!"))
			return
		if(length(loaded) >= max_shells)
			to_chat(user, span_warning("[src] is full."))
			return

		if(!move_into(src, nameof(src.loaded), C, user))
			return
		moveElement(loaded, length(loaded), 1) //to the head of the list
		act_message(user, src, MSG_SELF(span_notice("You insert \a [C] into %T%.")), MSG_OTHERS("%U% inserts \a [C] into %T%."))
		play_sfx(src, SFX_WEAPONS_EMPTY)
		user.hud_used?.update_ammo_hud(user, src)

	else if(istype(A, /obj/item/storage))
		var/obj/item/storage/storage = A
		if(!(load_method & SINGLE_CASING))
			return //incompatible

		to_chat(user, span_notice("You start loading \the [src]."))
		var/list/rounds = list()
		storage.latent_materialize_all() // a walk needs real things (C5)
		for(var/obj/item/ammo_casing/ammo in contents_of(storage)) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
			if(caliber == ammo.caliber)
				rounds += ammo
		after(src, 1 SECOND, PROC_REF(load_from_storage), with = list(user, rounds))

	update_icon()

/// Loads the next matching round from a box, one a second.
/obj/item/gun/projectile/proc/load_from_storage(mob/user, list/rounds)
	var/obj/item/ammo_casing/ammo
	while(length(rounds) && !ammo)
		ammo = rounds[1]
		rounds.Cut(1, 2)
		if(QDELETED(ammo))
			ammo = null
	if(!ammo)
		return
	load_ammo(ammo, user)
	user.hud_used.update_ammo_hud(user, src)
	if(length(loaded) >= max_shells)
		to_chat(user, span_warning("[src] is full."))
		return
	// ALLOW(sys_om_after_rearm): a finite sequence, not a loop over state: each run consumes one round from `rounds` (cut in place, so the list is the counter) and it ends when the list or the magazine runs out
	after(src, 1 SECOND, PROC_REF(load_from_storage), with = list(user, rounds))

/datum/om/task/timed/projectile_chamber_round
	complete_proc = /obj/item/gun/projectile/proc/chamber_round
	var/obj/item/ammo_casing/C
	var/message

/// A round slid into the chamber by hand.
/obj/item/gun/projectile/proc/chamber_round(datum/om/task/timed/projectile_chamber_round/task)
	var/mob/user = task.actor
	var/obj/item/ammo_casing/C = task.C
	var/message = task.message
	if(chambered)
		return
	act_message(user, src, MSG_SELF(span_notice("You slide %I% into %T%'s chamber.")), MSG_OTHERS(span_notice(message)), item = C)
	rel_set(src, nameof(chambered), C)
	user.hud_used.update_ammo_hud(user, src)
	user.remove_from_mob(C)
	C.forceMove(src)
	update_icon()

/obj/item/gun/projectile/special_check(mob/user)
	if(..())
		if(manual_chamber)
			if(CHECK_BITFIELD(auto_loading_type,OPEN_BOLT) && !bolt_open)
				to_chat(user,span_warning("This is an open bolt gun! You need to open the bolt before firing it!"))
				return 0
			else if(CHECK_BITFIELD(auto_loading_type,CLOSED_BOLT) && bolt_open)
				to_chat(user,span_warning("This is a closed bolt gun! You need to close the bolt before firing it!"))
				return 0
			else if((!auto_loading_type) && bolt_open)
				to_chat(user,span_warning("This is a manual action gun, the bolt or chamber must be closed before firing it!"))
				return 0
			else
				return 1
		else
			return 1

#undef BOLT_NOEVENT
#undef BOLT_CLOSED
#undef BOLT_OPENED
#undef BOLT_LOCKED
#undef BOLT_UNLOCKED
#undef BOLT_CASING_EJECTED
#undef BOLT_CASING_CHAMBERED

/obj/item/gun/projectile/ownership()
	. = ..()
	. += owns(nameof(ammo_magazine), policy = OWN_CONTAINED)
