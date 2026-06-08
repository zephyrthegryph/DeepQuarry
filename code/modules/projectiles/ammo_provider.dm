/*
 * /datum/ammo_provider — abstraction layer over the three load methods.
 *
 * The load_method bitflag (SINGLE_CASING|SPEEDLOADER|MAGAZINE) currently
 * scatters handling across gun.dm, guns/projectile.dm, and ammunition.dm.
 * This datum provides a unified interface that guns can query at fire-time.
 *
 * Three concrete implementations:
 *   /datum/ammo_provider/single_casing  — revolvers, shotguns, bolt-actions
 *   /datum/ammo_provider/speedloader    — speedloader-fed revolvers
 *   /datum/ammo_provider/magazine       — detachable-box-magazine guns
 *
 * Guns create their provider in Initialize() and hold a reference.  At fire
 * time they call provider.get_next_round() instead of switching on load_method.
 * Reload procs delegate to provider.receive_ammo(obj/item/A, mob/user).
 *
 * The existing /obj/item/gun/projectile vars (loaded, ammo_magazine, chambered)
 * remain in place for backwards-compatibility with all existing subtypes.  The
 * provider is an additive layer — it reads/writes those same lists rather than
 * duplicating state.
 */

/datum/ammo_provider
	/// The gun that owns this provider.  Weakref to avoid preventing GC.
	var/datum/weakref/gun_ref = null

/datum/ammo_provider/New(obj/item/gun/projectile/gun)
	..()
	if(gun)
		gun_ref = WEAKREF(gun)

/datum/ammo_provider/Destroy()
	gun_ref = null
	return ..()

/// Returns the next projectile object to be fired, or null if empty.
/// Implementations must advance the internal ammo state (decrement loaded list,
/// advance magazine pointer, etc.) as part of this call.
/datum/ammo_provider/proc/get_next_round()
	return null

/// Describe the ammo source for examine() and UI.  Returns a human-readable string.
/datum/ammo_provider/proc/describe_ammo()
	return "unknown"

/// Return current ammo count (rounds that can still be fired).
/datum/ammo_provider/proc/ammo_count()
	return 0

/// Attempt to receive ammo item A loaded by user.
/// Returns TRUE on success, FALSE if incompatible or full.
/datum/ammo_provider/proc/receive_ammo(obj/item/A, mob/user)
	return FALSE

/// Unload remaining ammo.  Places ejected items into user's hands / floor.
/datum/ammo_provider/proc/unload(mob/user, allow_dump = TRUE)
	return

// ---------------------------------------------------------------------------
// Single-casing provider (revolvers, shotguns, bolt-actions, etc.)
// Reads/writes /obj/item/gun/projectile.loaded list.
// ---------------------------------------------------------------------------

/datum/ammo_provider/single_casing

/datum/ammo_provider/single_casing/get_next_round()
	var/obj/item/gun/projectile/gun = gun_ref?.resolve()
	if(!gun)
		return null
	if(!gun.loaded.len)
		return null
	gun.chambered = gun.loaded[1]
	if(gun.handle_casings != HOLD_CASINGS)
		gun.loaded -= gun.chambered
	return gun.chambered?.BB

/datum/ammo_provider/single_casing/describe_ammo()
	var/obj/item/gun/projectile/gun = gun_ref?.resolve()
	if(!gun)
		return "no gun"
	return "[gun.loaded.len] round\s loaded"

/datum/ammo_provider/single_casing/ammo_count()
	var/obj/item/gun/projectile/gun = gun_ref?.resolve()
	if(!gun)
		return 0
	var/count = gun.loaded.len
	if(gun.chambered?.BB)
		count++
	return count

/datum/ammo_provider/single_casing/receive_ammo(obj/item/A, mob/user)
	var/obj/item/gun/projectile/gun = gun_ref?.resolve()
	if(!gun || !user)
		return FALSE
	if(!istype(A, /obj/item/ammo_casing))
		return FALSE
	var/obj/item/ammo_casing/C = A
	if(!(gun.load_method & SINGLE_CASING) || gun.caliber != C.caliber)
		return FALSE
	if(gun.loaded.len >= gun.max_shells)
		to_chat(user, span_warning("[gun] is full."))
		return FALSE
	if(do_after(user, gun.reload_time * C.w_class, target = gun))
		user.remove_from_mob(C)
		C.loc = gun
		gun.loaded.Insert(1, C)
		user.visible_message("[user] inserts \a [C] into [gun].", span_notice("You insert \a [C] into [gun]."))
		playsound(gun, 'sound/weapons/empty.ogg', 50, 1)
		gun.update_icon()
		user.hud_used.update_ammo_hud(user, gun)
		return TRUE
	return FALSE

/datum/ammo_provider/single_casing/unload(mob/user, allow_dump = TRUE)
	var/obj/item/gun/projectile/gun = gun_ref?.resolve()
	if(!gun || !gun.loaded.len)
		return
	if(allow_dump && (gun.load_method & SPEEDLOADER))
		var/count = 0
		var/turf/T = get_turf(user)
		if(T)
			for(var/obj/item/ammo_casing/C in gun.loaded)
				C.loc = T
				count++
			gun.loaded.Cut()
		if(count)
			user.visible_message("[user] unloads [gun].", span_notice("You unload [count] round\s from [gun]."))
	else if(gun.load_method & SINGLE_CASING)
		var/obj/item/ammo_casing/C = gun.loaded[gun.loaded.len]
		gun.loaded.len--
		user.put_in_hands(C)
		user.visible_message("[user] removes \a [C] from [gun].", span_notice("You remove \a [C] from [gun]."))
	playsound(gun, 'sound/weapons/empty.ogg', 50, 1)
	gun.update_icon()
	user.hud_used.update_ammo_hud(user, gun)

// ---------------------------------------------------------------------------
// Magazine provider (detachable box magazines).
// Reads/writes /obj/item/gun/projectile.ammo_magazine.
// ---------------------------------------------------------------------------

/datum/ammo_provider/magazine

/datum/ammo_provider/magazine/get_next_round()
	var/obj/item/gun/projectile/gun = gun_ref?.resolve()
	if(!gun)
		return null
	if(gun.ammo_magazine && gun.ammo_magazine.stored_ammo.len)
		gun.chambered = gun.ammo_magazine.stored_ammo[gun.ammo_magazine.stored_ammo.len]
		if(gun.handle_casings != HOLD_CASINGS)
			gun.ammo_magazine.stored_ammo -= gun.chambered
		return gun.chambered?.BB
	return null

/datum/ammo_provider/magazine/describe_ammo()
	var/obj/item/gun/projectile/gun = gun_ref?.resolve()
	if(!gun)
		return "no gun"
	if(gun.ammo_magazine)
		return "[gun.ammo_magazine] ([gun.ammo_magazine.stored_ammo.len] round\s)"
	return "no magazine"

/datum/ammo_provider/magazine/ammo_count()
	var/obj/item/gun/projectile/gun = gun_ref?.resolve()
	if(!gun)
		return 0
	var/count = 0
	if(gun.ammo_magazine?.stored_ammo)
		count += gun.ammo_magazine.stored_ammo.len
	if(gun.chambered?.BB)
		count++
	return count

/datum/ammo_provider/magazine/receive_ammo(obj/item/A, mob/user)
	var/obj/item/gun/projectile/gun = gun_ref?.resolve()
	if(!gun || !user)
		return FALSE
	if(!istype(A, /obj/item/ammo_magazine))
		return FALSE
	var/obj/item/ammo_magazine/AM = A
	if(!(gun.load_method & AM.mag_type) || gun.caliber != AM.caliber)
		to_chat(user, span_warning("[AM] won't load into [gun]!"))
		return FALSE
	if(gun.allowed_magazines && !is_type_in_list(A, gun.allowed_magazines))
		to_chat(user, span_warning("[AM] won't load into [gun]!"))
		return FALSE
	if(gun.ammo_magazine)
		to_chat(user, span_warning("[gun] already has a magazine loaded."))
		return FALSE
	if(do_after(user, gun.reload_time * AM.w_class, target = gun))
		user.remove_from_mob(AM)
		AM.loc = gun
		gun.ammo_magazine = AM
		user.visible_message("[user] inserts [AM] into [gun].", span_notice("You insert [AM] into [gun]."))
		user.hud_used.update_ammo_hud(user, gun)
		playsound(gun, 'sound/weapons/flipblade.ogg', 50, 1)
		gun.update_icon()
		return TRUE
	return FALSE

/datum/ammo_provider/magazine/unload(mob/user, allow_dump = TRUE)
	var/obj/item/gun/projectile/gun = gun_ref?.resolve()
	if(!gun || !gun.ammo_magazine)
		return
	user.put_in_hands(gun.ammo_magazine)
	user.visible_message("[user] removes [gun.ammo_magazine] from [gun].", span_notice("You remove [gun.ammo_magazine] from [gun]."))
	playsound(gun, 'sound/weapons/empty.ogg', 50, 1)
	gun.ammo_magazine.update_icon()
	gun.ammo_magazine = null
	gun.update_icon()
	user.hud_used.update_ammo_hud(user, gun)
