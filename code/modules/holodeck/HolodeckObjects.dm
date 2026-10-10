// Holographic Items!

// Holographic tables are in code/modules/tables/presets.dm
// Holographic racks are in code/modules/tables/rack.dm

/turf/simulated/floor/holofloor
	desc = "A convincing simulation."
	thermal_conductivity = 0
	flags = TURF_ACID_IMMUNE

// Old attackby: the holofloor ignores items.
CAPABILITIES(/turf/simulated/floor/holofloor)
	op("pass_item", item(/obj/item), label("Nothing"), passes())

/turf/simulated/floor/holofloor/install_flooring()
	return

/turf/simulated/floor/holofloor/carpet
	name = "carpet"
	icon = 'icons/turf/flooring/carpet.dmi'
	icon_state = "carpet"
	initial_flooring = /datum/decl/flooring/carpet

/turf/simulated/floor/holofloor/tiled
	name = "floor"
	icon = 'icons/turf/flooring/tiles.dmi'
	icon_state = "steel"
	initial_flooring = /datum/decl/flooring/tiling

/turf/simulated/floor/holofloor/tiled/dark
	name = "dark floor"
	icon_state = "dark"
	initial_flooring = /datum/decl/flooring/tiling/dark

/turf/simulated/floor/holofloor/lino
	name = "lino"
	icon = 'icons/turf/flooring/linoleum.dmi'
	icon_state = "lino"
	initial_flooring = /datum/decl/flooring/linoleum

/turf/simulated/floor/holofloor/wood
	name = "wooden floor"
	icon = 'icons/turf/flooring/wood.dmi'
	icon_state = "wood"
	initial_flooring = /datum/decl/flooring/wood

/turf/simulated/floor/holofloor/grass
	name = "lush grass"
	icon = 'icons/turf/flooring/grass.dmi'
	icon_state = "grass0"
	initial_flooring = /datum/decl/flooring/grass


/turf/simulated/floor/holofloor/snow
	name = "snow"
	base_name = "snow"
	icon = 'icons/turf/floors.dmi'
	base_icon = 'icons/turf/floors.dmi'
	icon_state = "snow"
	base_icon_state = "snow"

/turf/simulated/floor/holofloor/space
	icon = 'icons/turf/space.dmi'
	plane = SPACE_PLANE
	name = "\proper space"
	icon_state = "white"

/turf/simulated/floor/holofloor/space/draw(datum/look/look)
	..()
	look.overlay(space_dust())

/// The dust of the skybox over this tile: one of its cached pieces, picked by where the tile is.
/turf/simulated/floor/holofloor/space/proc/space_dust()
	var/datum/system/skybox/sky = SSskybox.ready()
	return sky.dust_cache["[((x + y) ^ ~(x * y) + z) % 25]"]

/turf/simulated/floor/holofloor/reinforced
	icon = 'icons/turf/flooring/tiles.dmi'
	initial_flooring = /datum/decl/flooring/reinforced
	name = "reinforced holofloor"
	icon_state = "reinforced"

/turf/simulated/floor/holofloor/beach
	desc = "Uncomfortably gritty for a hologram."
	base_desc = "Uncomfortably gritty for a hologram."
	icon = 'icons/misc/beach.dmi'
	base_icon = 'icons/misc/beach.dmi'
	initial_flooring = null

/turf/simulated/floor/holofloor/beach/sand
	name = "sand"
	icon_state = "desert"
	base_icon_state = "desert"

/turf/simulated/floor/holofloor/beach/coastline
	name = "coastline"
	icon = 'icons/misc/beach2.dmi'
	icon_state = "sandwater"
	base_icon_state = "sandwater"

/turf/simulated/floor/holofloor/beach/water
	name = "water"
	icon_state = "seashallow"
	base_icon_state = "seashallow"

/turf/simulated/floor/holofloor/desert
	name = "desert sand"
	base_name = "desert sand"
	desc = "Uncomfortably gritty for a hologram."
	base_desc = "Uncomfortably gritty for a hologram."
	icon_state = "asteroid"
	base_icon_state = "asteroid"
	icon = 'icons/turf/flooring/asteroid.dmi'
	base_icon = 'icons/turf/flooring/asteroid.dmi'
	initial_flooring = null

// ALLOW(init/INSTANCE_STATE): rolls whether this tile shows rocks
/turf/simulated/floor/holofloor/desert/Initialize(mapload)
	. = ..()
	if(prob(10))
		add_overlay("asteroid[rand(0,9)]")

/turf/simulated/floor/holofloor/bmarble
	name = "marble"
	icon = 'icons/turf/flooring/misc.dmi'
	icon_state = "darkmarble"
	initial_flooring = /datum/decl/flooring/bmarble

/turf/simulated/floor/holofloor/wmarble
	name = "marble"
	icon = 'icons/turf/flooring/misc.dmi'
	icon_state = "lightmarble"
	initial_flooring = /datum/decl/flooring/wmarble

/obj/structure/holostool
	name = "stool"
	desc = "Apply butt."
	icon = 'icons/obj/furniture.dmi'
	icon_state = "stool_padded_preview"
	anchored = TRUE
	unacidable = TRUE
	pressure_resistance = 15

/obj/item/clothing/gloves/boxing/hologlove
	name = "boxing gloves"
	desc = "Because you really needed another excuse to punch your crewmates."
	icon_state = "boxing"
	unacidable = TRUE
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_gloves.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_gloves.dmi',
			)
	item_state = "boxing"
	special_attack_type = /datum/unarmed_attack/holopugilism

/datum/unarmed_attack/holopugilism
	sparring_variant_type = /datum/unarmed_attack/holopugilism
	is_punch = TRUE

/datum/unarmed_attack/holopugilism/unarmed_override(mob/living/carbon/human/user,mob/living/carbon/human/target,zone)
	user.do_attack_animation(src)
	var/damage = rand(0, 9)
	if(!damage)
		play_sfx(target, SFX_WEAPONS_PUNCHMISS)
		act_message(user, target, others = span_danger("%U% has attempted to punch %T%!"))
		return TRUE
	var/obj/item/organ/external/affecting = target.get_organ(ran_zone(user.zone_sel.selecting))
	var/armor_block = target.armor_against(INJURY_PAIN, affecting)

	if(user.has_mutation(HULK))
		damage += 5

	play_sfx(target, SFX_PUNCH, 0.5, extrarange = -1)

	act_message(user, target, others = span_bolddanger("%U% has punched %T%!"))

	target.injure(INJURY_PAIN, damage, affecting?.organ_tag, user, flags = INJURE_ARMORED)
	if(damage >= 9)
		act_message(user, target, others = span_bolddanger("%U% has weakened %T%!"))
		target.apply_effect(4, WEAKEN, armor_block)

	return TRUE

CAPABILITIES(/obj/structure/window/reinforced/holowindow)
	op("holowindow_interaction_item", item(/obj/item), priority(OP_PRIORITY_PART + 1), then(PROC_REF(holowindow_interaction_item)))   // ahead of the window's own item use, which its pass goes on to

/// Old attackby: slam a grabbed mob against it, or take a hit; then the window's own handling.
/obj/structure/window/reinforced/holowindow/proc/holowindow_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(!istype(W))
		return OP_PASS
	if (istype(W, /obj/item/grab) && get_dist(src,user)<2)
		var/obj/item/grab/G = W
		if(isliving(G?.grab_target()))
			var/mob/living/M = G?.grab_target()
			var/state = G.state
			spent(W, user)	//gotta delete it here because if window breaks, it won't get deleted
			switch (state)
				if(1)
					act_message(user, M, others = span_warning("%U% slams %T% against \the [src]!"))
					M.injure(INJURY_PAIN, 7, null, src)
					hit(10)
				if(2)
					act_message(user, M, others = span_danger("%U% bashes %T% against \the [src]!"))
					if (prob(50))
						M.status_at_least(STAT_WEAKENED, 1)
					M.injure(INJURY_PAIN, 10, null, src)
					hit(25)
				if(3)
					act_message(M, user, others = span_danger("<big>%T% crushes %U% against \the [src]!</big>"))
					M.status_at_least(STAT_WEAKENED, 5)
					M.injure(INJURY_PAIN, 20, null, src)
					hit(50)
			return OP_PASS

	if(W.flags & NOBLUDGEON) return OP_PASS

	if(W.obj_damage_type())
		hit(W.force)
		if(get_integrity() <= 7)
			set_anchored(FALSE)
			step(src, get_dir(user, src))
	else
		play_sfx(src, SFX_EFFECTS_GLASSHIT)
	return OP_DECLINE

/obj/structure/window/reinforced/holowindow/screwdriver_act(mob/user, obj/item/tool)
	to_chat(user, span_notice("It's a holowindow, you can't unfasten it!"))
	return ITEM_INTERACT_BLOCKING

/obj/structure/window/reinforced/holowindow/crowbar_act(mob/user, obj/item/tool)
	to_chat(user, span_notice("It's a holowindow, you can't pry it!"))
	return ITEM_INTERACT_BLOCKING

/obj/structure/window/reinforced/holowindow/wrench_act(mob/user, obj/item/tool)
	to_chat(user, span_notice("It's a holowindow, you can't dismantle it!"))
	return ITEM_INTERACT_BLOCKING

/obj/structure/window/reinforced/holowindow/shatter(display_message = 1)
	play_sfx(src, SFX_SHATTER)
	if(display_message)
		visible_message("[src] fades away as it shatters!")
	consume(src)
	return

/obj/machinery/door/window/holowindoor/shatter(display_message = 1)
	set_density(FALSE)
	play_sfx(src, SFX_SHATTER)
	if(display_message)
		visible_message("[src] fades away as it shatters!")
	consume(src)

/obj/structure/bed/chair/holochair
	can_dismantle = FALSE

/obj/structure/bed/holobed
	can_dismantle = FALSE

/obj/item/holo
	injury_kind = INJURY_PAIN
	no_attack_log = 1
	no_random_knockdown = TRUE

/obj/item/holo/esword
	name = "holographic energy sword"
	desc = "May the force be within you. Sorta."
	icon_state = "esword"
	var/lcolor
	var/rainbow = FALSE
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_melee.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_melee.dmi',
			)
	force = 3.0
	throw_speed = 1
	throw_range = 5
	throwforce = 0
	w_class = ITEMSIZE_SMALL
	flags = NOBLOODY
	unacidable = TRUE
	var/active = 0

TRACKED(/obj/item/holo/esword, active)
TRACKED(/obj/item/holo/esword, lcolor)

/obj/item/holo/esword/green
	lcolor = "#008000"

/obj/item/holo/esword/red
	lcolor = "#FF0000"

/obj/item/holo/esword/handle_shield(mob/user, damage, atom/damage_source = null, mob/attacker = null, def_zone = null, attack_text = "the attack")
	if(active && default_parry_check(user, attacker, damage_source) && prob(50))
		act_message(user, src, others = span_danger("%U% parries [attack_text] with %T%!"))

		fx_sparks(user.loc, 5, FALSE)
		play_sfx(src, SFX_WEAPONS_BLADE1)
		return TRUE
	return FALSE

CAPABILITIES(/obj/item/holo/esword)
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attack_self.
/obj/item/holo/esword/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	set_active(!active)
	if (active)
		force = 30
		item_state = "[icon_state]_blade"
		w_class = ITEMSIZE_LARGE
		play_sfx(src, SFX_WEAPONS_SABERON)
		to_chat(user, span_notice("[src] is now active."))
	else
		force = 3
		item_state = "[icon_state]"
		w_class = ITEMSIZE_SMALL
		play_sfx(src, SFX_WEAPONS_SABEROFF)
		to_chat(user, span_notice("[src] can now be concealed."))

	// The held sprite follows item_state, so the hand it is in is redrawn with it.
	update_held_icon()
	add_fingerprint(user)
	return TRUE

/// Old attackby.
/obj/item/holo/esword/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(W.has_tool_quality(TOOL_MULTITOOL) && !active)
		if(!rainbow)
			rainbow = TRUE
		else
			rainbow = FALSE
		to_chat(user, span_notice("You manipulate the color controller in [src]."))
	return OP_DECLINE

/// The blade, in its colour, while it is switched on (the look redraws the hand it is held in when the sprite changes).
/obj/item/holo/esword/draw(datum/look/look)
	..()
	look.overlay(look_overlay_image(icon, "[initial(icon_state)]_blade", color = lcolor), active)

//BASKETBALL OBJECTS

/obj/item/beach_ball/holoball
	icon = 'icons/obj/balls_vr.dmi'
	icon_state = "basketball"
	name = "basketball"
	desc = "Here's your chance, do your dance at the Space Jam."
	w_class = ITEMSIZE_LARGE //Stops people from hiding it in their bags/pockets
	unacidable = TRUE
	drop_sound = SFX_ITEMS_DROP_BASKETBALL
	pickup_sound = SFX_ITEMS_PICKUP_BASKETBALL

/obj/structure/holohoop
	name = "basketball hoop"
	desc = "Boom, Shakalaka!"
	icon = 'icons/obj/32x64.dmi'
	icon_state = "hoop"
	anchored = TRUE
	density = TRUE
	unacidable = TRUE
	throwpass = 1

CAPABILITIES(/obj/structure/holohoop)
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attackby.
/obj/structure/holohoop/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if (istype(W, /obj/item/grab) && get_dist(src,user)<2)
		var/obj/item/grab/G = W
		if(G.state<2)
			to_chat(user, span_warning("You need a better grip to do that!"))
			return OP_PASS
		var/mob/grabbed = G?.grab_target()
		grabbed.forceMove(src.loc)
		grabbed.status_at_least(STAT_WEAKENED, 5)
		visible_message(span_warning("[G?.grab_assailant()] dunks [grabbed] into the [src]!"), 3)
		consume(W, user)
		return OP_PASS
	else if (istype(W, /obj/item) && get_dist(src,user)<2)
		user.drop_item(src.loc)
		act_message(user, src, others = span_notice("%U% dunks [W] into %T%!"))
		return OP_PASS
	return OP_PASS

/obj/structure/holohoop/CanPass(atom/movable/mover, turf/target)
	if (istype(mover,/obj/item) && mover.throwing)
		var/obj/item/I = mover
		if(istype(I, /obj/item/projectile))
			return TRUE
		if(prob(50))
			I.forceMove(loc)
			visible_message(span_notice("Swish! \the [I] lands in \the [src]."), 3)
		else
			visible_message(span_warning("\The [I] bounces off of \the [src]'s rim!"), 3)
		return FALSE
	return ..()

/obj/machinery/readybutton
	name = "Ready Declaration Device"
	desc = "This device is used to declare ready. If all devices in an area are ready, the event will begin!"
	icon = 'icons/obj/monitors.dmi'
	icon_state = "auth_off"
	layer = ABOVE_WINDOW_LAYER
	var/ready = 0
	var/tmp/area/currentarea
	var/eventstarted = 0

	unacidable = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 2
	active_power_usage = 6
	power_channel = ENVIRON

CAPABILITIES(/obj/machinery/readybutton)
	op("readybutton_silicon_refuse", remote(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(readybutton_silicon_refuse)))
	op("readybutton_touch", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 2), label("Use"), then(PROC_REF(interaction_touch)))
	op("readybutton_press", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 3), label("Press"), needs(req(PROC_REF(can_press_holds), because = PROC_REF(can_press_refusal))), then(PROC_REF(interaction_press)))

/// Old attack_ai: refuse silicons.
/obj/machinery/readybutton/proc/readybutton_silicon_refuse(datum/act/op/A)
	to_chat(A.actor, "The station AI is not to interact with these devices!")
	return OP_OK

/// Old attackby: always refused.
/obj/machinery/readybutton/proc/interaction_touch(datum/act/op/A)
	to_chat(A.actor, "The device is a solid button, there's nothing you can do with it!")
	return OP_OK

/// Requirement: the button is powered (and the presser conscious).
/obj/machinery/readybutton/proc/can_press(mob/user, atom/target, obj/item/held)
	if(user.stat || !operable())
		return "this device is not powered"
	return TRUE

/obj/machinery/readybutton/proc/can_press_holds(datum/act/op/A)
	var/answer = can_press(A.actor, src, A.held)
	return !istext(answer) && !!answer

/obj/machinery/readybutton/proc/can_press_refusal(datum/act/op/A)
	var/answer = can_press(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/// Old attack_hand: never called ..().
/obj/machinery/readybutton/proc/interaction_press(datum/act/op/A)
	var/mob/user = A.actor
	if(!user.IsAdvancedToolUser())
		return OP_OK

	currentarea = get_area(src.loc) // a location: a plain var
	if(!currentarea())
		spent(src, user)
		return OP_OK

	if(eventstarted)
		to_chat(user, "The event has already begun!")
		return OP_OK

	set_ready(!ready)

	var/numbuttons = 0
	var/numready = 0
	for(var/obj/machinery/readybutton/button in currentarea())
		numbuttons++
		if (button.ready)
			numready++

	if(numbuttons == numready)
		begin_event()
	return OP_OK

TRACKED(/obj/machinery/readybutton, ready)

/// The look (the draw sweep: from its layers).
/obj/machinery/readybutton/draw(datum/look/look)
	..()
	switch("[ready]")
		if("1")
			look.state("auth_on")
		else
			look.state("auth_off")

/obj/machinery/readybutton/proc/begin_event()

	eventstarted = 1

	for(var/obj/structure/window/reinforced/holowindow/disappearing/W in currentarea())
		spent(W)

	for(var/mob/M in currentarea())
		to_chat(M, "FIGHT!")

// A window that disappears when the ready button is pressed
/obj/structure/window/reinforced/holowindow/disappearing
	name = "Event Window"

//Holocarp

/mob/living/simple_mob/animal/space/carp/holodeck
	icon = 'icons/mob/AI.dmi'
	icon_state = "holo4"
	icon_living = "holo4"
	icon_dead = "holo4"
	alpha = 127
	icon_gib = null
	meat_amount = 0
	meat_type = null

/mob/living/simple_mob/animal/space/carp/holodeck/Initialize(mapload)
	. = ..()
	set_light(2) //hologram lighting

/mob/living/simple_mob/animal/space/carp/holodeck/proc/set_safety(safe)
	if (safe)
		faction = FACTION_NEUTRAL
		melee_damage_lower = 0
		melee_damage_upper = 0
	else
		faction = FACTION_CARP
		melee_damage_lower = initial(melee_damage_lower)
		melee_damage_upper = initial(melee_damage_upper)

/mob/living/simple_mob/animal/space/carp/holodeck/gib()
	derez() //holograms can't gib

/mob/living/simple_mob/animal/space/carp/holodeck/on_death(gibbed)
	..()
	derez()

/mob/living/simple_mob/animal/space/carp/holodeck/proc/derez()
	act_message(src, null, others = span_infoplain(span_bold("%U%") + " fades away!"))
	consume(src)


/// the currentarea this refers to (a relation view: it reads null once the target is deleted).
/obj/machinery/readybutton/proc/currentarea() as /area
	return currentarea
