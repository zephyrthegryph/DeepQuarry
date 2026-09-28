// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

#define THROWER_MIN 50
#define THROWER_MAX 1000

/obj/item/flamethrower
	name = "flamethrower"
	desc = "You are a firestarter!"
	icon = 'icons/obj/flamethrower.dmi'
	icon_state = "flamethrowerbase"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_guns.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_guns.dmi',
			)
	item_state = "flamethrower_0"
	force = 3.0
	throwforce = 10.0
	throw_speed = 1
	throw_range = 5
	w_class = ITEMSIZE_NORMAL
	MATERIAL_BULK(MAT_STEEL, 500)
	var/status = FALSE
	var/throw_amount = THROWER_MIN
	var/lit = FALSE	//on or off
	COOLDOWN_DECLARE(operating)
	var/previousturf_handle
	var/obj/item/weldingtool/weldtool = null
	var/obj/item/assembly/igniter/igniter = null
	var/obj/item/tank/phoron/ptank = null
	var/volume_per_max_burn = 20 // gets divided by the intended burn ratio

/obj/item/flamethrower/Initialize(mapload)
	weldtool = new /obj/item/weldingtool(src)
	weldtool.status = 0 // for disassembly
	update_icon()
	. = ..()

/obj/item/flamethrower/full/Initialize(mapload)
	igniter = new /obj/item/assembly/igniter(src)
	igniter.secured = 0 // for disassembly
	. = ..()
	status = TRUE

DECLARE_REF(/obj/item/flamethrower, "weldtool", OWNED, null)
DECLARE_REF(/obj/item/flamethrower, "igniter", OWNED, null)
DECLARE_REF(/obj/item/flamethrower, "ptank", OWNED, null)

/obj/item/flamethrower/periodic_step()
	if(!lit)
		om_task_periodic_stop(src)
		return null
	var/turf/location = loc
	if(istype(location, /mob/))
		var/mob/living/M = location
		if(M.item_is_in_hands(src))
			location = M.loc
	if(isturf(location)) //start a fire if possible
		location.hotspot_expose(700, 2)
	return

/obj/item/flamethrower/update_icon()
	cut_overlays()
	if(igniter)
		add_overlay("+igniter[status]")
	if(ptank)
		add_overlay("+ptank")
	if(lit)
		add_overlay("+lit")
		item_state = "flamethrower_1"
	else
		item_state = "flamethrower_0"
	return

/obj/item/flamethrower/afterattack(atom/target, mob/user, proximity, click_parameters, stance = I_HURT)
	if(!lit || !COOLDOWN_FINISHED(src, operating))
		return
	if(user && user.get_active_hand() == src)
		if(stance == I_HELP && user.client?.prefs?.read_preference(/datum/preference/toggle/safefiring))
			to_chat(user, span_warning("You refrain from firing \the [src] as you are out of combat mode."))
			return
		if(check_fuel())
			// spawn projectile
			var/obj/item/projectile/P = new /obj/item/projectile/bullet/dragon/flamethrower(get_turf(src))
			P.submunition_spread_max = 90 + round(80*thrower_spew_percent())
			P.submunition_spread_min = 5 + round(50*thrower_spew_percent())
			P.submunitions = list(/obj/item/projectile/bullet/incendiary/dragonflame/flamethrower = 1 + round(thrower_spew_percent()*2))
			P.launch_projectile( target, BP_TORSO, user)

			// suck out fuel and burn it
			var/datum/gas_mixture/used_gas = ptank.air_contents.remove_ratio(volume_per_max_burn * thrower_spew_percent() / ptank.air_contents.return_volume())
			qdel(used_gas)
			if(!check_fuel())
				lit = FALSE
			update_icon()
		else
			to_chat(user, span_notice("There is not enough pressure in [src]'s tank!"))
			lit = FALSE
			update_icon()
		// prevent spam
		COOLDOWN_START(src, operating, 15)
	return

/obj/item/flamethrower/proc/thrower_spew_percent()
	return throw_amount / THROWER_MAX

/obj/item/flamethrower/proc/check_fuel()
	return ptank != null && ptank.air_contents.total_moles() > 5 // minimum fuel usage is five moles, for EXTREMELY hot mix or super low pressure

/// Old attackby.
/obj/item/flamethrower/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(user.stat || user.restrained() || user.lying)
		return INTERACTION_HANDLED_PASS

	if(isigniter(W))
		var/obj/item/assembly/igniter/I = W
		if(I.secured)	return INTERACTION_HANDLED_PASS
		if(igniter)		return INTERACTION_HANDLED_PASS
		user.drop_item()
		I.forceMove(src)
		igniter = I
		update_icon()
		return INTERACTION_HANDLED_PASS

	if(istype(W,/obj/item/tank/phoron))
		if(ptank)
			to_chat(user, span_notice("There appears to already be a phoron tank loaded in [src]!"))
			return INTERACTION_HANDLED_PASS
		user.drop_item()
		ptank = W
		W.forceMove(src)
		update_icon()
		return INTERACTION_HANDLED_PASS

	return FALSE

/obj/item/flamethrower/wrench_act(mob/user, obj/item/tool)
	if(status || user.stat || user.restrained() || user.lying)
		return ITEM_INTERACT_BLOCKING
	var/turf/T = get_turf(src)
	if(weldtool)
		weldtool.forceMove(T)
		weldtool = null
	if(igniter)
		igniter.forceMove(T)
		igniter = null
	if(ptank)
		ptank.forceMove(T)
		ptank = null
	new /obj/item/stack/rods(T)
	qdel(src)
	return ITEM_INTERACT_SUCCESS

/obj/item/flamethrower/screwdriver_act(mob/user, obj/item/tool)
	if(!igniter || lit || user.stat || user.restrained() || user.lying)
		return ITEM_INTERACT_BLOCKING
	status = !status
	to_chat(user, span_notice("[igniter] is now [status ? "secured" : "unsecured"]!"))
	update_icon()
	return ITEM_INTERACT_SUCCESS

DECLARE_INTERACTIONS(/obj/item/flamethrower, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_self.
/obj/item/flamethrower/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(user.stat || user.restrained() || user.lying)
		return TRUE
	tgui_interact(user)
	return TRUE

/obj/item/flamethrower/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Flamethrower", name)
		ui.open()

/obj/item/flamethrower/tgui_data(mob/user)
	var/list/dat = list()
	dat["lit"] = lit
	dat["constructed"] = status
	dat["throw_amount"] = throw_amount
	// Tank
	dat["has_tank"] = !isnull(ptank)
	dat["throw_min"] = THROWER_MIN
	dat["throw_max"] = THROWER_MAX
	dat["fuel_kpa"] = check_fuel() ? ptank.air_contents.return_pressure() : 0
	return dat

/obj/item/flamethrower/tgui_act(action, params, datum/tgui/ui)
	if(usr.stat || usr.restrained() || usr.lying)
		return FALSE
	if(..())
		return FALSE

	switch(action)
		if("light")
			if(!check_fuel() || LINDA_GAS_AMT(ptank.air_contents, GAS_PHORON) < 1 || !status)
				return FALSE
			lit = !lit
			if(lit)
				om_task_periodic(src, PERIODIC_SLOW)
				playsound(src, 'sound/items/welderactivate.ogg', 50, 1)
			else
				playsound(src, 'sound/items/welderdeactivate.ogg', 50, 1)
			update_icon()
			return TRUE
		if("amount")
			throw_amount = text2num(params["amount"])
			throw_amount = clamp(throw_amount,THROWER_MIN,THROWER_MAX)
			return TRUE
		if("remove")
			if(!ptank)
				return FALSE
			usr.put_in_hands(ptank)
			ptank = null
			lit = 0
			update_icon()
			return TRUE

// Projectile
/obj/item/projectile/bullet/dragon/flamethrower
	name = "flames"
	icon_state = "fireball2"
	submunitions = list(/obj/item/projectile/bullet/incendiary/dragonflame/flamethrower = 2)
	damage = 0
	hitsound_wall = null

/obj/item/projectile/bullet/incendiary/dragonflame/flamethrower
	name = "flames"
	icon_state = "fireball2"
	damage = 2
	hitsound_wall = null

#undef THROWER_MIN
#undef THROWER_MAX

/// LC-refs: previousturf -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/flamethrower/proc/previousturf() as /turf
	return om_resolve(previousturf_handle)
