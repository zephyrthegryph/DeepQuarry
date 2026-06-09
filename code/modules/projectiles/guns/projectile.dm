/obj/item/gun/projectile
	name = "gun"
	desc = "A gun that fires bullets."
	icon_state = "revolver"
	w_class = ITEMSIZE_NORMAL
	matter = list(MAT_STEEL = 1000)
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

	/// Ammo provider datum (see ammo_provider.dm).  Set in Initialize() based on
	/// load_method.  Provides a unified get_next_round()/unload() interface.
	var/datum/ammo_provider/ammo_provider = null

/obj/item/gun/projectile/Initialize(mapload, starts_loaded = 1)
	. = ..()
	if(starts_loaded)
		if(ispath(ammo_type) && (load_method & (SINGLE_CASING|SPEEDLOADER)))
			for(var/i in 1 to max_shells)
				loaded += new ammo_type(src)
				if(random_start_ammo)
					loaded.Cut(0,rand(0,max_shells))
		if(ispath(magazine_type) && (load_method & MAGAZINE))
			ammo_magazine = new magazine_type(src)
			allowed_magazines += /obj/item/ammo_magazine/smart
			if(random_start_ammo)
				var/ammo_cut = rand(0,ammo_magazine.max_ammo)
				ammo_magazine.contents.Cut(0,ammo_cut)
				ammo_magazine.stored_ammo.Cut(0,ammo_cut)

	// Create the appropriate ammo provider for this gun's load method.
	if(load_method & MAGAZINE)
		ammo_provider = new /datum/ammo_provider/magazine(src)
	else
		// SINGLE_CASING and SPEEDLOADER share the same provider type since they
		// both use the `loaded` list; the allow_dump flag in unload() distinguishes
		// speedloader behaviour.
		ammo_provider = new /datum/ammo_provider/single_casing(src)

	update_icon()

/obj/item/gun/projectile/Destroy()
	QDEL_NULL(ammo_provider)
	loaded = null
	ammo_magazine = null
	chambered = null
	return ..()

/obj/item/gun/projectile/consume_next_projectile()
	if(!manual_chamber) // Manual Chambering
		//get the next casing
		if(loaded.len)
			chambered = loaded[1] //load next casing.
			if(handle_casings != HOLD_CASINGS)
				loaded -= chambered
		else if(ammo_magazine && ammo_magazine.stored_ammo.len)
			chambered = ammo_magazine.stored_ammo[ammo_magazine.stored_ammo.len]
			if(handle_casings != HOLD_CASINGS)
				ammo_magazine.stored_ammo -= chambered
	if(manual_chamber && auto_loading_type && CHECK_BITFIELD(auto_loading_type,OPEN_BOLT) && bolt_open)
		chamber_bullet() // Manual Chambering

	var/mob/living/M = loc // TGMC Ammo HUD
	if(istype(M)) // TGMC Ammo HUD
		M?.hud_used.update_ammo_hud(M, src)

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
			if(!istype(H.gloves, /obj/item/clothing))
				H.add_gunshotresidue(chambered)
			else
				var/obj/item/clothing/G = H.gloves
				G.add_gunshotresidue(chambered)

	switch(handle_casings)
		if(EJECT_CASINGS) //eject casing onto ground.
			if(chambered.caseless)
				qdel(chambered)
				return
			else
				chambered.loc = get_turf(src)
				playsound(src, "casing", 50, 1)
		if(CYCLE_CASINGS) //cycle the casing back to the end.
			if(ammo_magazine)
				ammo_magazine.stored_ammo += chambered
			else
				loaded += chambered

	if(handle_casings != HOLD_CASINGS)
		chambered = null

	var/mob/living/M = loc // TGMC Ammo HUD
	if(istype(M)) // TGMC Ammo HUD
		M?.hud_used.update_ammo_hud(M, src)


//attempts to unload src. If allow_dump is set to 0, the speedloader unloading method will be disabled
/obj/item/gun/projectile/proc/unload_ammo(mob/user, allow_dump=1)
	if(manual_chamber && only_open_load && !bolt_open) // Manual Chambering
		to_chat(user,span_warning("You must open the bolt to load or unload this gun!")) // Manual Chambering
		return // Manual Chambering

	if(ammo_magazine)
		user.put_in_hands(ammo_magazine)
		user.visible_message("[user] removes [ammo_magazine] from [src].", span_notice("You remove [ammo_magazine] from [src]."))
		playsound(src, 'sound/weapons/empty.ogg', 50, 1)
		ammo_magazine.update_icon()
		ammo_magazine = null
		user.hud_used.update_ammo_hud(user, src)
	else if(loaded.len)
		//presumably, if it can be speed-loaded, it can be speed-unloaded.
		if(allow_dump && (load_method & SPEEDLOADER))
			var/count = 0
			var/turf/T = get_turf(user)
			if(T)
				for(var/obj/item/ammo_casing/C in loaded)
					C.loc = T
					count++
				loaded.Cut()
			if(count)
				user.visible_message("[user] unloads [src].", span_notice("You unload [count] round\s from [src]."))
		else if(load_method & SINGLE_CASING)
			var/obj/item/ammo_casing/C = loaded[loaded.len]
			loaded.len--
			user.put_in_hands(C)
			user.visible_message("[user] removes \a [C] from [src].", span_notice("You remove \a [C] from [src]."))
		playsound(src, 'sound/weapons/empty.ogg', 50, 1)
		user.hud_used.update_ammo_hud(user, src)
	else
		to_chat(user, span_warning("[src] is empty."))
	update_icon()
	user.hud_used.update_ammo_hud(user, src)

/obj/item/gun/projectile/attackby(obj/item/A as obj, mob/user as mob)
	..()
	load_ammo(A, user)

/obj/item/gun/projectile/attack_self(mob/user, callback)
	. = ..(user)
	if(.)
		return TRUE
	if(special_weapon_handling && !callback)
		return FALSE
	if(manual_chamber) // Gun Rework
		if(do_after(user, 0.4 SECONDS, src)) // Gun Rework
			bolt_handle(user) // Gun Rework
	else if(firemodes.len > 1) // Gun Rework
		switch_firemodes(user)
	else
		unload_ammo(user)

/obj/item/gun/projectile/attack_hand(mob/user as mob)
	if(user.get_inactive_hand() == src)
		unload_ammo(user, allow_dump=0)
	else
		return ..()

/obj/item/gun/projectile/afterattack(atom/A, mob/living/user)
	..()
	if(auto_eject && ammo_magazine && ammo_magazine.stored_ammo && !ammo_magazine.stored_ammo.len && !(manual_chamber && chambered && chambered.BB != null)) // Manual Chambering
		ammo_magazine.loc = get_turf(src.loc)
		user.visible_message(
			"[ammo_magazine] falls out and clatters on the floor!",
			span_notice("[ammo_magazine] falls out and clatters on the floor!")
			)
		if(auto_eject_sound)
			playsound(src, auto_eject_sound, 40, 1)
		ammo_magazine.update_icon()
		ammo_magazine = null
		update_icon() //make sure to do this after unsetting ammo_magazine
		user.hud_used.update_ammo_hud(user, src)

/obj/item/gun/projectile/examine(mob/user)
	. = ..()
	if(ammo_magazine)
		. += "It has \a [ammo_magazine] loaded."
	. += "It has [getAmmo()] round\s remaining."

/obj/item/gun/projectile/proc/getAmmo()
	var/bullets = 0
	if(loaded)
		bullets += loaded.len
	if(ammo_magazine && ammo_magazine.stored_ammo)
		bullets += ammo_magazine.stored_ammo.len
	if(chambered)
		bullets += 1
	return bullets

/* Unneeded -- so far.
//in case the weapon has firemodes and can't unload using attack_hand()
/obj/item/gun/projectile/verb/unload_gun()
	set name = "Unload Ammo"
	set category = "Object"
	set src in usr

	if(usr.stat || usr.restrained()) return

	unload_ammo(usr)
*/

// TGMC Ammo HUD Insertion
/obj/item/gun/projectile/has_ammo_counter()
	return TRUE

/obj/item/gun/projectile/get_ammo_type()
	if(load_method & MAGAZINE)
		if(chambered) // Do we have an ammo casing chambered
			var/obj/item/ammo_casing/A = chambered
			var/obj/item/projectile/P = A.projectile_type
			return list(initial(P.hud_state), initial(P.hud_state_empty))
		else if(ammo_magazine && ammo_magazine.stored_ammo.len) // Do we have a mag, and have ammo in the mag, but nothing chambered?
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
		else if(loaded.len) // Else, is the gun loaded, but no ammo casings in chamber currently?
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


// === merged from projectile_ch.dm during hard-fork de-suffix (manually verified: all-new types/defines, no base re-open) ===
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
	var/sound_ejectchamber = 'sound/weapons/ballistics/pistol_ejectchamber.ogg'
	var/sound_eject = 'sound/weapons/ballistics/pistol_eject.ogg'
	var/sound_chamber = 'sound/weapons/ballistics/pistol_chamber.ogg'
	special_handling = TRUE

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
		spawn()
			shake_camera(user, recoil+1, recoil)
	update_icon()

	if(chambered)
		chambered.expend()
		if(!manual_chamber) process_chambered()
	if(manual_chamber && auto_loading_type)
		bolt_toggle()

/obj/item/gun/projectile/proc/bolt_handle(mob/user)
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
			user.visible_message(span_notice("[user] pulls back \the [bolt_name] before releasing it[close_open_ejected] causing it to slide forward again[casing_chambered]."), \
			span_notice("You pull back \the [bolt_name] before releasing it[close_open_ejected] causing it to slide forward again[casing_chambered]."))
			user.hud_used.update_ammo_hud(user, src)
		else if(opened)
			playsound(src, sound_eject, 50, 0)
			if(locked)
				if(CHECK_BITFIELD(auto_loading_type,LOCK_MANUAL_LOCK))
					playsound(src, sound_ejectchamber, 50, 0)
					user.visible_message(span_notice("[user] pulls back \the [bolt_name] and locks it in the open position[casing_chambered][other_ejected]."), \
					span_notice("You pull back \the [bolt_name] and lock it in the open position[other_ejected][casing_chambered]."))
				else
					user.visible_message(span_notice("[user] pulls back \the [bolt_name] before releasing it, causing it to lock in the open position[casing_chambered][other_ejected]."), \
					span_notice("You pull back \the [bolt_name] before releasing it, causing it to lock in the open position[casing_chambered][other_ejected]."))
			else
				user.visible_message(span_notice("[user] opens \the [bolt_name][casing_chambered][other_ejected]."), \
				span_notice("You pull back \the [bolt_name][casing_chambered][other_ejected]."))
		else if(closed)
			playsound(src, sound_chamber, 50, 0)
			if(unlocked)
				if(bolt_release)
					if(user.a_intent == I_HURT && CHECK_BITFIELD(auto_loading_type,LOCK_SLAPPABLE))
						user.visible_message(span_notice("[user] slaps the [bolt_release], causing \the [bolt_name] to slide forward[casing_chambered]!"), \
						span_notice("You slap the [bolt_release], causing \the [bolt_name] to slide forward[casing_chambered]!"))
					else
						user.visible_message(span_notice("[user] presses the [bolt_release], causing \the [bolt_name] to slide forward[casing_chambered]."), \
						span_notice("You press the [bolt_release], causing \the [bolt_name] to slide forward[casing_chambered]."))
				else
					user.visible_message(span_notice("[user] pulls \the [bolt_name] back the rest of the way, causing it to slide forward[casing_chambered]."), \
					span_notice("You pull \the [bolt_name] back the rest of the way, causing it to slide forward[casing_chambered]."))
			else
				user.visible_message(span_notice("[user] closes \the [bolt_name][casing_chambered]."), \
				span_notice("You close \the [bolt_name][casing_chambered]."))
		user.hud_used.update_ammo_hud(user, src)

/obj/item/gun/projectile/proc/bolt_toggle(manual)
	if(!bolt_open)
		if(auto_loading_type)
			var/able_to_lock = (CHECK_BITFIELD(auto_loading_type,LOCK_OPEN_EMPTY) || (CHECK_BITFIELD(auto_loading_type,LOCK_MANUAL_LOCK) && manual))
			if(CHECK_BITFIELD(auto_loading_type,OPEN_BOLT))
				bolt_open = TRUE
				var/ejected = process_chambered()
				var/output = BOLT_OPENED
				if(ejected) output |= BOLT_CASING_EJECTED
				return output
			else if(loaded.len || (ammo_magazine && ammo_magazine.stored_ammo.len) || !able_to_lock)
				var/ejected = process_chambered()
				var/chambering = chamber_bullet()
				var/output = BOLT_OPENED | BOLT_CLOSED
				if(ejected) output |= BOLT_CASING_EJECTED
				if(chambering) output |= BOLT_CASING_CHAMBERED
				return output
			else
				if(!manual)
					visible_message(src,span_notice("The [src] fires its last round, causing the [bolt_name] to lock."))
				bolt_open = TRUE
				bolt_locked = TRUE
				var/ejected = process_chambered()
				var/output = BOLT_OPENED | BOLT_LOCKED
				if(ejected) output |= BOLT_CASING_EJECTED
				return output
		else
			bolt_open = TRUE
			var/ejected = process_chambered()

			var/output = BOLT_OPENED
			if(ejected) output |= BOLT_CASING_EJECTED
			//if(chambering) output |= BOLT_CASING_CHAMBERED
			return output
	else
		if(auto_loading_type)
			if(CHECK_BITFIELD(auto_loading_type,OPEN_BOLT))
				if(loaded.len || (ammo_magazine && ammo_magazine.stored_ammo.len))
					if(!manual)
						var/ejected = process_chambered()
						var/output = BOLT_CLOSED | BOLT_OPENED
						if(ejected) output |= BOLT_CASING_EJECTED
						return output
					else
						return BOLT_NOEVENT
				else
					bolt_open = FALSE
					return BOLT_CLOSED
			else if(bolt_locked)
				var/chambering = FALSE
				if(!chambered)
					chambering = chamber_bullet()
				bolt_locked = FALSE
				bolt_open = FALSE
				var/output = BOLT_CLOSED | BOLT_UNLOCKED
				if(chambering) output |= BOLT_CASING_CHAMBERED
				return output
			else
				bolt_open = FALSE
				return BOLT_CLOSED
		else
			bolt_open = FALSE
			var/output = BOLT_CLOSED
			var/chambering = chamber_bullet()
			if(chambering) output |= BOLT_CASING_CHAMBERED
			return output

/obj/item/gun/projectile/proc/chamber_bullet()
	if(chambered)
		return FALSE
	var/obj/item/ammo_casing/to_chamber
	if(loaded.len)
		to_chamber = loaded[1] //load next casing.
		if(handle_casings != HOLD_CASINGS)
			loaded -= to_chamber
	else if(ammo_magazine && ammo_magazine.stored_ammo.len)
		to_chamber = ammo_magazine.stored_ammo[ammo_magazine.stored_ammo.len]
		if(handle_casings != HOLD_CASINGS)
			ammo_magazine.stored_ammo -= to_chamber
	chambered = to_chamber
	if(to_chamber)
		return TRUE
	else
		return FALSE

// Attempts to load A into src, depending on the type of thing being loaded and the load_method.
// Handles magazine/speedloader/single-casing/storage bulk loads, including the manual-chamber
// and bolt mechanics keyed off auto_loading_type.
/obj/item/gun/projectile/proc/load_ammo(obj/item/A, mob/user)
	if(istype(A, /obj/item/ammo_magazine))
		var/obj/item/ammo_magazine/AM = A
		if(!(load_method & AM.mag_type) || caliber != AM.caliber || allowed_magazines && !is_type_in_list(A, allowed_magazines))
			to_chat(user, span_warning("[AM] won't load into [src]!"))
			return
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
				user.remove_from_mob(AM)
				AM.loc = src
				ammo_magazine = AM
				user.visible_message("[user] inserts [AM] into [src].", span_notice("You insert [AM] into [src]."))
				if(manual_chamber && CHECK_BITFIELD(auto_loading_type,CHAMBER_ON_RELOAD) && bolt_open && !chambered)
					chamber_bullet()
					bolt_toggle()
				playsound(src, 'sound/weapons/flipblade.ogg', 50, 1)
				user.hud_used.update_ammo_hud(user, src)
			if(SPEEDLOADER)
				if(only_open_load && !bolt_open)
					to_chat(user, span_warning("[src] must have its bolt open to be loaded!"))
					return
				if(loaded.len >= max_shells)
					to_chat(user, span_warning("[src] is full!"))
					return
				var/count = 0
				for(var/obj/item/ammo_casing/C in AM.stored_ammo)
					if(loaded.len >= max_shells)
						break
					if(C.caliber == caliber)
						C.loc = src
						loaded += C
						AM.stored_ammo -= C //should probably go inside an ammo_magazine proc, but I guess less proc calls this way...
						count++
				if(count)
					user.visible_message("[user] reloads [src].", span_notice("You load [count] round\s into [src]."))
					playsound(src, 'sound/weapons/empty.ogg', 50, 1)
					user.hud_used.update_ammo_hud(user, src)
		AM.update_icon()
	else if(istype(A, /obj/item/ammo_casing))
		var/obj/item/ammo_casing/C = A
		if(caliber != C.caliber)
			return
		if(!(load_method & SINGLE_CASING) || (misc_loading_flags & INTERNAL_MAG_SEPARATE)) //INTERNAL_MAG_SEPARATE is pretty much exclusively for the SPAS-12
			if(manual_chamber)
				if(!CHECK_BITFIELD(auto_loading_type,OPEN_BOLT))
					if(!chambered)
						if(bolt_open)
							if(do_after(user, 0.5 SECONDS, src))
								user.visible_message(span_notice("[user] slides \the [C] into the [src]'s chamber."),span_notice("You slide \the [C] into the [src]'s chamber."))
								chambered = C
								user.hud_used.update_ammo_hud(user, src)
							else
								return
						else if(!(CHECK_BITFIELD(auto_loading_type,LOCK_OPEN_EMPTY) || (CHECK_BITFIELD(auto_loading_type,LOCK_MANUAL_LOCK))))
							if(do_after(user, 1.5 SECONDS, src))
								user.visible_message(span_notice("[user] holds open \the [src]'s [bolt_name] and slides [C] into the chamber before letting the bolt close again."),span_notice("You slide \the [C] into the [src]'s chamber."))

								chambered = C
								user.hud_used.update_ammo_hud(user, src)
							else
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
				user.remove_from_mob(C)
				C.loc = src
				update_icon()
				return
			else
				return
		if(only_open_load && !bolt_open)
			to_chat(user, span_warning("[src] must have its bolt open to be loaded!"))
			return
		if(loaded.len >= max_shells)
			to_chat(user, span_warning("[src] is full."))
			return

		user.remove_from_mob(C)
		C.loc = src
		loaded.Insert(1, C) //add to the head of the list
		user.visible_message("[user] inserts \a [C] into [src].", span_notice("You insert \a [C] into [src]."))
		playsound(src, 'sound/weapons/empty.ogg', 50, 1)
		user.hud_used.update_ammo_hud(user, src)

	else if(istype(A, /obj/item/storage))
		var/obj/item/storage/storage = A
		if(!(load_method & SINGLE_CASING))
			return //incompatible

		to_chat(user, span_notice("You start loading \the [src]."))
		sleep(1 SECOND)
		for(var/obj/item/ammo_casing/ammo in storage.contents)
			if(caliber != ammo.caliber)
				continue

			load_ammo(ammo, user)
			user.hud_used.update_ammo_hud(user, src)

			if(loaded.len >= max_shells)
				to_chat(user, span_warning("[src] is full."))
				break
			sleep(1 SECOND)

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
