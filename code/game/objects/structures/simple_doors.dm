// A simple door's integrity is its material's integrity, rounded to tens
// (the old "hardness" was integrity / 10; one hardness point is 10 integrity).

/obj/structure/simple_door
	name = "door"
	density = TRUE
	anchored = TRUE
	can_atmos_pass = ATMOS_PASS_DENSITY
	breakable = TRUE

	icon = 'icons/obj/doors/material_doors.dmi'
	icon_state = "metal"

	var/datum/material/material
	var/state = 0 //closed, 1 == open
	var/isSwitchingStates = 0
	var/oreAmount = 7
	var/knock_sound = SFX_MACHINES_DOOR_KNOCK_GLASS
	var/knock_hammer_sound = SFX_WEAPONS_SONIC_JACKHAMMER

	var/locked = FALSE	//has the door been locked?
	var/lock_id = null	//does the door have an associated key?
	var/lock_type = "simple"	//string matched to "pick_type" on /obj/item/lockpick
	var/can_pick = TRUE	//can it be picked/bypassed?
	var/lock_difficulty = 1	//multiplier to picking/bypassing time
	var/keysound = SFX_ITEMS_TOOLBELT_EQUIP

/// Heat behaviour rule: a flammable material door burns.
/obj/structure/simple_door/proc/rule_burn(datum/rule/rule)
	TemperatureAct(get_temperature())

/obj/structure/simple_door/proc/TemperatureAct(temperature)
	var/burnt = material.combustion_effect(get_turf(src),temperature, 0.3)
	if(burnt > 0)
		take_damage(burnt * 10, BURN, FIRE, FALSE)

/obj/structure/simple_door/Initialize(mapload, material_name)
	. = ..()
	set_material(material_name)
	if(!material)
		return INITIALIZE_HINT_QDEL

/obj/structure/simple_door/proc/set_material(material_name)
	if(!material_name)
		material_name = MAT_STEEL
	material = get_material_by_name(material_name)
	if(!material)
		return
	max_integrity = max(1,round(material.integrity/10)) * 10
	update_integrity(max_integrity)
	icon_state = material.door_icon_base
	name = "[material.display_name] door"
	color = material.icon_colour
	set_rad_insulation(material.radiation_transmission(RAD_DOOR_THICKNESS_MM))
	if(material.opacity < 0.5)
		set_opacity(0)
	else
		set_opacity(1)
	if(material.products_need_process())
		om_task_periodic(src, PERIODIC_SLOW)
	update_nearby_tiles(need_rebuild=1)

/obj/structure/simple_door/get_material()
	return material

/obj/structure/simple_door/Bumped(atom/user)
	..()
	if(!state)
		return TryToSwitchState(user)
	return

/// Old attack_ai: those aren't machinery, they're just big slabs of a mineral. Cyborgs next to it open it; the AI can't.
/obj/structure/simple_door/proc/simple_door_silicon_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(isAI(user)) //so the AI can't open it
		return TRUE
	if(isrobot(user) && get_dist(user,src) <= 1) //but cyborgs can, not remotely though
		TryToSwitchState(user)
	return TRUE

/obj/structure/simple_door/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/simple_door_hand,
		/datum/interaction/entry_item/simple_door_item,
	)
	into += dq_interaction_from_spec(type, INTERACT_SILICON("Open", PROC_REF(simple_door_silicon_use)))
	..()

/// Old attack_hand: open/close the door.
/datum/interaction/entry_hand/simple_door_hand
	id = "simple_door_hand"
	name = "Use"
	effect = /obj/structure/simple_door/proc/interaction_hand

/obj/structure/simple_door/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	TryToSwitchState(user)
	return TRUE

/obj/structure/simple_door/CanPass(atom/movable/mover, turf/target)
	if(istype(mover, /obj/effect/beam))
		return !opacity
	return !density

/obj/structure/simple_door/proc/TryToSwitchState(atom/user)
	if(isSwitchingStates) return
	if(ismob(user))
		var/mob/M = user
		if(!material.can_open_material_door(user))
			return
		if(locked && state == 0)
			to_chat(M,span_warning("It's locked!"))
			return
		if(ELAPSED(src, last_bumped, CLOCK_WORLD) <= 6 SECONDS)
			return
		if(M.client)
			if(iscarbon(M))
				var/mob/living/carbon/C = M
				if(!C.get_equipped_item(SLOT_ID_HANDCUFFED))
					SwitchState()
			else
				SwitchState()
	else if(istype(user, /obj/mecha))
		SwitchState()

/obj/structure/simple_door/proc/SwitchState()
	if(state)
		Close()
	else
		Open()

/obj/structure/simple_door/proc/Open()
	isSwitchingStates = 1
	playsound(src, material.dooropen_noise, 100, 1)
	flick("[material.door_icon_base]opening",src)
	after(src, 1 SECOND, PROC_REF(open_finish))

/obj/structure/simple_door/proc/open_finish()
	set_density(FALSE)
	set_opacity(0)
	state = 1
	update_icon()
	isSwitchingStates = 0
	update_nearby_tiles()

/obj/structure/simple_door/proc/Close()
	isSwitchingStates = 1
	playsound(src, material.dooropen_noise, 100, 1)
	flick("[material.door_icon_base]closing",src)
	after(src, 1 SECOND, PROC_REF(close_finish))

/obj/structure/simple_door/proc/close_finish()
	set_density(TRUE)
	set_opacity(1)
	state = 0
	update_icon()
	isSwitchingStates = 0
	update_nearby_tiles()

/obj/structure/simple_door/proc/appearance_base()
	return material.door_icon_base

APPEARANCE_TEMPLATE(/obj/structure/simple_door, "{appearance_base}{state?open:}")

/// Old attackby: lock/unlock with the matching key, dig/hit the door, or fall back to toggling.
/datum/interaction/entry_item/simple_door_item
	id = "simple_door_item"
	name = "Use"
	effect = /obj/structure/simple_door/proc/interaction_item

/obj/structure/simple_door/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if(istype(W,/obj/item/simple_key))
		var/obj/item/simple_key/key = W
		if(state)
			to_chat(user,span_notice("\The [src] must be closed in order for you to lock it."))
		else if(key.key_id != src.lock_id)
			to_chat(user,span_warning("The [key] doesn't fit \the [src]'s lock!"))
		else if(key.key_id == src.lock_id)
			act_message(user, src, others = span_notice("%U% [key.keyverb] %I% and [locked ? "unlocks" : "locks"] %T%."), item = key)
			locked = !locked
			playsound(src, keysound,100, 1)
		return TRUE
	if(istype(W,/obj/item/pickaxe) && breakable)
		var/obj/item/pickaxe/digTool = W
		act_message(user, src, others = span_danger("%U% starts digging %T%!"))
		om_task_timed(user, digTool.digspeed*get_integrity()/10, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done), done_args = list(user))
	else if(istype(W,/obj/item) && breakable) //not sure, can't not just weapons get passed to this proc?
		act_message(user, src, others = span_danger("%U% hits %T% with [W]!"))
		if(material == get_material_by_name(MAT_RESIN))
			play_sfx(src, SFX_EFFECTS_ATTACKBLOB, 2)
		else if(material == get_material_by_name(MAT_WOOD) || material == get_material_by_name(MAT_SIFWOOD) || material == get_material_by_name(MAT_HARDWOOD))
			play_sfx(src, SFX_EFFECTS_WOODCUTTING)
		else
			play_sfx(src, SFX_WEAPONS_SMASH)
		receive_weapon_hit(W, user)
	else
		interaction_hand(user, W, interaction)
	return TRUE

/obj/structure/simple_door/proc/attackby_timed_done(mob/user)
	if(!(src))
		return
	act_message(user, src, others = span_danger("%U% finished digging %T%!"))
	Dismantle()

/obj/structure/simple_door/welder_act(mob/user, obj/item/W)
	if(!breakable)
		return TRUE
	var/obj/item/weldingtool/WT = W.get_welder()
	if(material.ignition_point && WT.remove_fuel(0, user))
		TemperatureAct(150)
	return TRUE

/// Projectile adapter: a door soaks most of a round.
/obj/structure/simple_door/projectile_damage(obj/item/projectile/P, def_zone)
	return receive_projectile(P, def_zone, 0.1)

/obj/structure/simple_door/attack_generic(mob/user, damage, attack_verb)
	act_message(user, src, others = span_danger("%U% [attack_verb] %T%!"))
	if(material == get_material_by_name(MAT_RESIN))
		play_sfx(src, SFX_EFFECTS_ATTACKBLOB, 2)
	else if(material == (get_material_by_name(MAT_WOOD) || get_material_by_name(MAT_SIFWOOD) || get_material_by_name(MAT_HARDWOOD)))
		play_sfx(src, SFX_EFFECTS_WOODCUTTING)
	else
		play_sfx(src, SFX_WEAPONS_SMASH)
	user.do_attack_animation(src)
	receive_generic_attack(user, damage)

/obj/structure/simple_door/proc/Dismantle(devastated = 0)
	deconstruct(!devastated)

/obj/structure/simple_door/handle_deconstruct(disassembled = TRUE)
	material.place_dismantled_product(get_turf(src))
	visible_message(span_danger("The [src] is destroyed!"))

/obj/structure/simple_door/periodic_step()
	// material.radioactivity moved to a component; query the helper.
	var/rad = dq_material_radioactivity(material)
	if(!rad)
		return
	radiation_pulse(
		src,
		max_range = 5,
		threshold = RAD_MEDIUM_INSULATION,
		chance = round((rad * 0.33), 0.1),
		minimum_exposure_time = URANIUM_RADIATION_MINIMUM_EXPOSURE_TIME,
		strength = rad
	)

/obj/structure/simple_door/iron/Initialize(mapload,material_name)
	. = ..(mapload, material_name || MAT_IRON)

/obj/structure/simple_door/silver/Initialize(mapload,material_name)
	. = ..(mapload, material_name || MAT_SILVER)

/obj/structure/simple_door/gold/Initialize(mapload,material_name)
	. = ..(mapload, material_name || MAT_GOLD)

/obj/structure/simple_door/uranium
	COOLDOWN_DECLARE(event_cooldown)
	/// Mutex to prevent infinite recursion when propagating radiation pulses
	var/active = null

/obj/structure/simple_door/uranium/Initialize(mapload,material_name)
	. = ..(mapload, material_name || MAT_URANIUM)

DECLARE_PERIODIC(/obj/structure/simple_door/uranium, PERIODIC_SLOW)

// Use the uranium-specific rate-limited pulse instead of the base generic material radiation.
/// Radiates only while a mob is close enough to be affected; otherwise it sleeps until one comes near.
/obj/structure/simple_door/uranium/periodic_step()
	if(!mob_near(world.view))
		return sleep_until_mob_near(world.view)
	radiate()

/obj/structure/simple_door/uranium/proc/radiate()
	if(active)
		return
	if(!COOLDOWN_FINISHED(src, event_cooldown))
		return
	active = TRUE
	radiation_pulse(
		src,
		max_range = 3,
		threshold = RAD_LIGHT_INSULATION,
		chance = URANIUM_IRRADIATION_CHANCE,
		minimum_exposure_time = URANIUM_RADIATION_MINIMUM_EXPOSURE_TIME,
		strength = 5
	)
	COOLDOWN_START(src, event_cooldown, 1.5 SECONDS)
	active = FALSE

/obj/structure/simple_door/sandstone/Initialize(mapload,material_name)
	. = ..(mapload, material_name || MAT_SANDSTONE)

/obj/structure/simple_door/phoron/Initialize(mapload,material_name)
	. = ..(mapload, material_name || MAT_PHORON)

/obj/structure/simple_door/diamond/Initialize(mapload,material_name)
	. = ..(mapload, material_name || MAT_DIAMOND)

//I was going to give wooden doors RAD_VERY_LIGHT_INSULATION but they need a proper parent instead of this garbage.
/obj/structure/simple_door/wood/Initialize(mapload,material_name)
	. = ..(mapload, material_name || MAT_WOOD)
	knock_sound = SFX_MACHINES_DOOR_KNOCK_WOOD

/obj/structure/simple_door/hardwood/Initialize(mapload,material_name)
	. = ..(mapload, material_name || MAT_HARDWOOD)
	knock_sound = SFX_MACHINES_DOOR_KNOCK_WOOD

/obj/structure/simple_door/sifwood/Initialize(mapload,material_name)
	. = ..(mapload, material_name || MAT_SIFWOOD)
	knock_sound = SFX_MACHINES_DOOR_KNOCK_WOOD

/obj/structure/simple_door/birchwood/Initialize(mapload,material_name)
	. = ..(mapload, material_name || MAT_BIRCHWOOD)
	knock_sound = SFX_MACHINES_DOOR_KNOCK_WOOD

/obj/structure/simple_door/pinewood/Initialize(mapload,material_name)
	. = ..(mapload, material_name || MAT_PINEWOOD)
	knock_sound = SFX_MACHINES_DOOR_KNOCK_WOOD

/obj/structure/simple_door/oakwood/Initialize(mapload,material_name)
	. = ..(mapload, material_name || MAT_OAKWOOD)
	knock_sound = SFX_MACHINES_DOOR_KNOCK_WOOD

/obj/structure/simple_door/acaciawood/Initialize(mapload,material_name)
	. = ..(mapload, material_name || MAT_ACACIAWOOD)
	knock_sound = SFX_MACHINES_DOOR_KNOCK_WOOD

/obj/structure/simple_door/redwood/Initialize(mapload,material_name)
	. = ..(mapload, material_name || MAT_REDWOOD)
	knock_sound = SFX_MACHINES_DOOR_KNOCK_WOOD

/obj/structure/simple_door/resin/Initialize(mapload,material_name)
	. = ..(mapload, material_name || MAT_RESIN)

/obj/structure/simple_door/cult/Initialize(mapload,material_name)
	. = ..(mapload, material_name || MAT_CULT)

/obj/structure/simple_door/glamour/Initialize(mapload,material_name)
	. = ..(mapload, material_name || MAT_GLAMOUR)

/obj/structure/simple_door/snowbrick/Initialize(mapload, material_name)
	. = ..(mapload, material_name || MAT_SNOWBRICK)

/obj/structure/simple_door/cult/TryToSwitchState(atom/user)
	if(isliving(user))
		var/mob/living/L = user
		if(!iscultist(L) && !istype(L, /mob/living/simple_mob/construct))
			return
	..()

// start: Allows removing resin doors.
// Resin's Use fully replaces the base simple_door's (the original override never called
// ..() into it either), so it declares its own interaction.
/obj/structure/simple_door/resin/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/simple_door_resin_tear,
		/datum/interaction/entry_hand/simple_door_resin_hand,
	)
	into += dq_interaction_from_spec(type, INTERACT_SILICON("Open", PROC_REF(simple_door_silicon_use))) // doesn't chain to the base door's

/// Old attack_hand: a Hulk destroys it, a xenomorph melts through it, or it opens as usual.
/datum/interaction/entry_hand/simple_door_resin_hand
	id = "simple_door_resin_hand"
	name = "Use"
	effect = /obj/structure/simple_door/resin/proc/interaction_resin_hand

/obj/structure/simple_door/resin/proc/interaction_resin_hand(mob/user, obj/item/held, datum/interaction/interaction)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if (HULK in user.mutations)
		act_message(user, null, others = span_warning("%U% destroys the [name]!"))
		Dismantle(1)
		return TRUE
	TryToSwitchState(user)
	return TRUE

/// Old attack_hand's harm branch: a carbon tears at the resin, or a xenomorph melts it (combat mode only).
/datum/interaction/entry_hand/simple_door_resin_tear
	id = "simple_door_resin_tear"
	name = "Tear at"
	effect = /obj/structure/simple_door/resin/proc/interaction_resin_tear
	stance = I_HURT

/obj/structure/simple_door/resin/proc/interaction_resin_tear(mob/user, obj/item/held, datum/interaction/interaction)
	if((HULK in user.mutations) || !istype(user, /mob/living/carbon))
		return FALSE // a Hulk destroys it, anyone else opens it: interaction_resin_hand()
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	var/mob/living/carbon/M = user
	if(locate_in_list(M.internal_organ_list(), /obj/item/organ/internal/xenos/hivenode))
		act_message(user, null, others = span_warning("%U% strokes the [name] and it melts away!"))
		Dismantle(1)
		return TRUE
	act_message(user, null, others = span_warning("%U% tears at the [name]!"))
	take_damage(20, BRUTE, MELEE, FALSE)
	return TRUE
// end.

/datum/material/flockium
	name = MAT_FLOKIUM
	icon_base = "flock"
	icon_reinf = "flock"
	icon_colour = "#FFFFFF"
	density = 30 // weight renamed to density.
	hardness = 200
	protectiveness = 5 // 20%
	conductive = 0
	conductivity = 0
	door_icon_base = "flockdoor"
	sheet_singular_name = "quanta"
	sheet_plural_name = "quanta"
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = 3

/obj/structure/simple_door/flock
	name = "aperture"
	icon = 'icons/goonstation/featherzone.dmi'
	icon_state = "flockdoor"

/obj/structure/simple_door/flock/Initialize(mapload, newmat)
	. = ..(mapload, MAT_FLOKIUM)
