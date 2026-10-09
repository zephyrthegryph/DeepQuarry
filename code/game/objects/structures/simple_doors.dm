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

TRACKED(/obj/structure/simple_door, state)

/// Heat behaviour rule: a flammable material door burns.
/obj/structure/simple_door/proc/rule_burn(datum/rule/rule)
	TemperatureAct(get_temperature())

/obj/structure/simple_door/proc/TemperatureAct(temperature)
	var/burnt = material.combustion_effect(get_turf(src),temperature, 0.3)
	if(burnt > 0)
		take_damage(burnt * 10, BURN, FIRE, FALSE)

/// The material the door is made of (its constructor param; a subtype's default).
/obj/structure/simple_door/var/material_name = MAT_STEEL

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). A door of no known material is not made.
/obj/structure/simple_door/proc/make_of(material_key)
	set_material(material_key)
	if(!material)
		spent(src)

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
	set_radiating(material.products_need_process())
	update_nearby_tiles(need_rebuild=1)

/obj/structure/simple_door/get_material()
	return material

/// A door of a radioactive material gives off its radiation every few seconds.
/obj/structure/simple_door/var/tmp/radiating = FALSE
TRACKED(/obj/structure/simple_door, radiating)

CAPABILITIES(/obj/structure/simple_door)
	every(2 SECONDS, then(PROC_REF(radiate_step)), when = nameof(radiating))
	on_notice(/datum/notice/bumped, then(PROC_REF(bumped_into)))
	op("use_welder", tool(TOOL_WELDER), wait(0), costs(RES_FUEL, 0), then(PROC_REF(welder_used)))
	op("use", hand(), label("Use"), then(PROC_REF(interaction_hand)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	op("dig", item(/obj/item/pickaxe), label("Dig"), when(req(PROC_REF(is_breakable))), begins(MSG(simple_door/digging)), wait(PROC_REF(dig_time)), then(PROC_REF(dug)))
	// those aren't machinery, they're slabs of a mineral: a cyborg beside it opens it, the AI can't
	op("silicon_open", remote(), label("Open"), when(req_actor_kind(/mob/living/silicon/robot)), needs(req_adjacent()), then(PROC_REF(interaction_hand)))
	param(nameof(material_name), pos = 1, apply = PROC_REF(make_of))

/// Something walked into it (the bump action's notice).
/obj/structure/simple_door/proc/bumped_into(datum/act/A)
	var/datum/notice/bumped/N = A
	var/atom/user = N.bumper
	if(!state)
		return TryToSwitchState(user)
	return

/// A hand (or a cyborg beside it) opens or shuts it.
/obj/structure/simple_door/proc/interaction_hand(datum/act/op/A)
	TryToSwitchState(A.actor)
	return OP_OK

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
	set_state(1)
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
	set_state(0)
	isSwitchingStates = 0
	update_nearby_tiles()

/obj/structure/simple_door/proc/appearance_base()
	return material.door_icon_base

/// The look (the draw sweep: from its template).
/obj/structure/simple_door/draw(datum/look/look)
	..()
	look.state("[appearance_base()][state ? "open" : ""]")

/obj/structure/simple_door/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
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
		return OP_OK
	if(istype(W,/obj/item/lockpick))
		return OP_PASS // the pick's own "pick" op (code/game/objects/items/lockpicks.dm) works the lock
	if(istype(W,/obj/item) && breakable) //not sure, can't not just weapons get passed to this proc?
		act_message(user, src, others = span_danger("%U% hits %T% with [W]!"))
		if(material == get_material_by_name(MAT_RESIN))
			play_sfx(src, SFX_EFFECTS_ATTACKBLOB, 2)
		else if(material == get_material_by_name(MAT_WOOD) || material == get_material_by_name(MAT_SIFWOOD) || material == get_material_by_name(MAT_HARDWOOD))
			play_sfx(src, SFX_EFFECTS_WOODCUTTING)
		else
			play_sfx(src, SFX_WEAPONS_SMASH)
		receive_weapon_hit(W, user)
	else
		TryToSwitchState(user)
	return OP_OK

MSG_DEF(simple_door/digging, null, span_danger("%U% starts digging %T%!"))

/obj/structure/simple_door/proc/is_breakable(datum/act/op/A)
	return breakable

/// Digging takes as long as the pick is slow and the door is sound.
/obj/structure/simple_door/proc/dig_time(datum/act/op/A)
	var/obj/item/pickaxe/digTool = A.held
	return digTool.digspeed * get_integrity() / 10

/obj/structure/simple_door/proc/dug(datum/act/op/A)
	act_message(A.actor, src, others = span_danger("%U% finished digging %T%!"))
	Dismantle()

/obj/structure/simple_door/proc/welder_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(!breakable)
		return OP_OK
	var/obj/item/weldingtool/WT = W.get_welder()
	if(material.ignition_point && WT.remove_fuel(0, user))
		TemperatureAct(150)
	return OP_OK

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

/obj/structure/simple_door/proc/radiate_step(datum/act/A)
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

/obj/structure/simple_door/iron
	material_name = MAT_IRON

/obj/structure/simple_door/silver
	material_name = MAT_SILVER

/obj/structure/simple_door/gold
	material_name = MAT_GOLD

/obj/structure/simple_door/uranium
	COOLDOWN_DECLARE(event_cooldown)
	/// Mutex to prevent infinite recursion when propagating radiation pulses
	var/active = null
	proximity_tracked = TRUE

/obj/structure/simple_door/uranium
	material_name = MAT_URANIUM

// Use the uranium-specific rate-limited pulse instead of the base generic material radiation.
/// Radiates only while a client is near (the proximity tracker, STAT_RELEVANCE); otherwise the every() parks until one comes near.
CAPABILITIES(/obj/structure/simple_door/uranium)
	every(2 SECONDS, then(PROC_REF(uranium_door_step)), when = STAT_RELEVANCE)

/obj/structure/simple_door/uranium/proc/uranium_door_step(datum/act/timer/A)
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

/obj/structure/simple_door/sandstone
	material_name = MAT_SANDSTONE

/obj/structure/simple_door/phoron
	material_name = MAT_PHORON

/obj/structure/simple_door/diamond
	material_name = MAT_DIAMOND

//I was going to give wooden doors RAD_VERY_LIGHT_INSULATION but they need a proper parent instead of this garbage.
/obj/structure/simple_door/wood
	material_name = MAT_WOOD
	knock_sound = SFX_MACHINES_DOOR_KNOCK_WOOD

/obj/structure/simple_door/hardwood
	material_name = MAT_HARDWOOD
	knock_sound = SFX_MACHINES_DOOR_KNOCK_WOOD

/obj/structure/simple_door/sifwood
	material_name = MAT_SIFWOOD
	knock_sound = SFX_MACHINES_DOOR_KNOCK_WOOD

/obj/structure/simple_door/birchwood
	material_name = MAT_BIRCHWOOD
	knock_sound = SFX_MACHINES_DOOR_KNOCK_WOOD

/obj/structure/simple_door/pinewood
	material_name = MAT_PINEWOOD
	knock_sound = SFX_MACHINES_DOOR_KNOCK_WOOD

/obj/structure/simple_door/oakwood
	material_name = MAT_OAKWOOD
	knock_sound = SFX_MACHINES_DOOR_KNOCK_WOOD

/obj/structure/simple_door/acaciawood
	material_name = MAT_ACACIAWOOD
	knock_sound = SFX_MACHINES_DOOR_KNOCK_WOOD

/obj/structure/simple_door/redwood
	material_name = MAT_REDWOOD
	knock_sound = SFX_MACHINES_DOOR_KNOCK_WOOD

/obj/structure/simple_door/resin
	material_name = MAT_RESIN

/obj/structure/simple_door/cult
	material_name = MAT_CULT

/obj/structure/simple_door/glamour
	material_name = MAT_GLAMOUR

/obj/structure/simple_door/snowbrick
	material_name = MAT_SNOWBRICK

/obj/structure/simple_door/cult/TryToSwitchState(atom/user)
	if(isliving(user))
		var/mob/living/L = user
		if(!iscultist(L) && !istype(L, /mob/living/simple_mob/construct))
			return
	..()

// start: Allows removing resin doors.
// Resin's Use fully replaces the base simple_door's (the original override never called
// ..() into it either), so it declares its own interaction.
// The resin door replaces the base door's hand and item: a hand pulls at it, in combat mode tears at it; the cyborg's open stays.
CAPABILITIES(/obj/structure/simple_door/resin)
	without("use")
	without("item")
	op("resin_hand", hand(), label("Use"), stance(I_HELP, I_DISARM, I_GRAB), then(PROC_REF(interaction_resin_hand)))
	op("tear", hand(), label("Tear at"), stance(I_HURT), then(PROC_REF(interaction_resin_tear)))

/// A Hulk destroys it, a xenomorph melts through it, or it opens as usual.
/obj/structure/simple_door/resin/proc/interaction_resin_hand(datum/act/op/A)
	var/mob/user = A.actor
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if (HULK in user.mutations)
		act_message(user, null, others = span_warning("%U% destroys the [name]!"))
		Dismantle(1)
		return OP_OK
	TryToSwitchState(user)
	return OP_OK

/// Combat mode: a carbon tears at the resin, or a xenomorph melts it; a Hulk or anyone else gets the ordinary use.
/obj/structure/simple_door/resin/proc/interaction_resin_tear(datum/act/op/A)
	var/mob/user = A.actor
	if((HULK in user.mutations) || !istype(user, /mob/living/carbon))
		return interaction_resin_hand(A)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	var/mob/living/carbon/M = user
	if(locate_in_list(M.internal_organ_list(), /obj/item/organ/internal/xenos/hivenode))
		act_message(user, null, others = span_warning("%U% strokes the [name] and it melts away!"))
		Dismantle(1)
		return OP_OK
	act_message(user, null, others = span_warning("%U% tears at the [name]!"))
	take_damage(20, BRUTE, MELEE, FALSE)
	return OP_OK
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

/obj/structure/simple_door/flock
	material_name = MAT_FLOKIUM
