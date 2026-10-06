/obj/vehicle/bike
	name = "space-bike"
	desc = "Space wheelies! Woo!"
	icon = 'icons/obj/bike.dmi'
	icon_state = "bike_off"
	dir = SOUTH

	load_item_visible = 1
	mob_offset_y = 5
	max_integrity = 100

	locked = 0
	powered = 1

	fire_dam_coeff = 0.6
	brute_dam_coeff = 0.5
	var/protection_percent = 60

	var/land_speed = 1.5 //if 0 it can't go on turf
	var/space_speed = 0.5
	var/bike_icon = "bike"
	var/custom_icon = FALSE

	paint_color = "#ffffff"

	var/datum/effect/effect/system/ion_trail_follow/ion
	var/kickstand = 1

CAPABILITIES(/obj/vehicle/bike)
	owns_one(nameof(ion), starts = /datum/effect/effect/system/ion_trail_follow)

/obj/vehicle/bike/ownership()
	. = ..()
	. += owns(nameof(cell), policy = OWN_CONTAINED, starts = /obj/item/cell/high)

/obj/vehicle/bike/Initialize(mapload)
	. = ..()
	ion.set_up(src)
	turn_off()
	icon_state = "[bike_icon]_off"
	update_icon()

/// A frame the builder fits a cell to: it starts without the factory cell.
/obj/vehicle/bike/built/ownership()
	. = ..()
	. += no_starts(nameof(cell))

CAPABILITIES(/obj/vehicle/bike/random)
	rolls(nameof(paint_color), PROC_REF(roll_paint_color))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/vehicle/bike/random/proc/roll_paint_color(datum/roller/R)
	return rgb(R.number(1, 255),R.number(1, 255),R.number(1, 255))

EXTEND_INTERACTIONS(/obj/vehicle/bike, \
	INTERACT_ITEM("Paint", PROC_REF(interaction_vehicle_paint)), \
	INTERACT_ALT("Toggle kickstand", PROC_REF(interaction_bike_kickstand)), \
	INTERACT_DRAG("Load", PROC_REF(interaction_bike_drag)), \
	INTERACT_HAND(null, PROC_REF(interaction_bike_hand)), \
	INTERACT_VERB("Toggle Engine", PROC_REF(bike_toggle_engine), REQ_REACH(0)), \
	INTERACT_VERB("Toggle Kickstand", PROC_REF(bike_kickstand), REQ_REACH(0)), \
)

/// A vehicle's paint colour (multitool, panel open). Re-checked on the answer: the painter is
/// still next to it and able. Shared by the bike, the quad and its trailer.
/datum/prompt/color/vehicle_paint
	title = "Paint Color"
	question = "Please select paint color."
	ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE
	timeout = 0

/obj/vehicle/proc/vehicle_paint_picked(datum/act/request/A)
	if(!A.answer)
		return
	paint_color = A.answer.value
	update_icon()

/obj/vehicle/bike/click_ctrl(mob/user)
	if(Adjacent(user) && anchored)
		return toggle_proc(user)
	else
		return ..()

/// Old verb "Toggle Engine".
/obj/vehicle/bike/proc/bike_toggle_engine(mob/user, obj/item/held, datum/interaction/interaction)
	toggle_proc(user)

/obj/vehicle/bike/proc/toggle_proc(mob/user)
	if(!isliving(user) || has_trait(user, TRAIT_AMBIENT_PEST_MOB))
		return CLICK_ACTION_BLOCKING

	if(user.incapacitated())
		return CLICK_ACTION_BLOCKING

	if(!on && cell && cell.charge > charge_use)
		turn_on()
		visible_message("\The [src] rumbles to life.", "You hear something rumble deeply.")
		return CLICK_ACTION_SUCCESS
	else
		turn_off()
		visible_message("\The [src] putters before turning off.", "You hear something putter slowly.")
		return CLICK_ACTION_SUCCESS

/// Old click_alt: toggle the kickstand when adjacent.
/obj/vehicle/bike/proc/interaction_bike_kickstand(mob/user, obj/item/held, datum/interaction/interaction)
	if(!Adjacent(user))
		return FALSE
	bike_kickstand(user)
	return TRUE

/// Old verb "Toggle Kickstand".
/obj/vehicle/bike/proc/bike_kickstand(mob/user, obj/item/held, datum/interaction/interaction)
	if(!isliving(user) || has_trait(user, TRAIT_AMBIENT_PEST_MOB))
		return

	if(user.incapacitated()) return

	if(kickstand)
		act_message(user, src, others = "%U% puts up %T%'s kickstand.")
	else
		if(istype(src.loc,/turf/space) || istype(src.loc, /turf/simulated/floor/water))
			to_chat(user, span_warning(" You don't think kickstands work here..."))
			return
		act_message(user, src, others = "%U% puts down %T%'s kickstand.")
		var/mob/pulledby = src?.pulled_by_mob()
		if(pulledby)
			pulledby.stop_pulling()

	kickstand = !kickstand
	set_anchored((kickstand || on))

/obj/vehicle/bike/load(atom/movable/C, mob/user as mob)
	var/mob/living/M = C
	if(!istype(C)) return 0
	if(M?.buckled_to() || M.restrained() || !Adjacent(M) || !M.Adjacent(src))
		return 0
	return ..(M, user)

/// Old MouseDrop_T: load the dropped atom onto the bike.
/obj/vehicle/bike/proc/interaction_bike_drag(mob/user, atom/movable/C, datum/interaction/interaction)
	if(!load(C, user))
		to_chat(user, span_warning(" You were unable to load \the [C] onto \the [src]."))
	return TRUE

/// Old attack_hand: buckle yourself on, or off.
/obj/vehicle/bike/proc/interaction_bike_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(user == load)
		unload(load, user)
		to_chat(user, "You unbuckle yourself from \the [src].")
	else if(!load && load(user, user))
		to_chat(user, "You buckle yourself to \the [src].")
	return TRUE

/obj/vehicle/bike/relaymove(mob/user, direction)
	if(user != load || !on)
		return 0
	if(Move(get_step(src, direction)))
		return 1
	return 0

/obj/vehicle/bike/Move(atom/newloc, direct = 0, movetime)
	if(kickstand) return 0

	if(on && (!cell || cell.charge < charge_use))
		turn_off()
		visible_message(span_warning("\The [src] whines, before its engines wind down."))
		return FALSE

	//these things like space, not turf. Dragging shouldn't weigh you down.
	if(on && cell)
		cell.use(charge_use)

	if(is_vehicle_inpassable(newloc) || src?.pulled_by_mob())
		if(!space_speed)
			return FALSE
		move_delay = space_speed
	else
		if(!land_speed)
			return FALSE
		move_delay = land_speed
	return ..()

/obj/vehicle/bike/turn_on()
	ion.start()
	set_anchored(TRUE)

	update_icon()

	var/mob/pulledby = src?.pulled_by_mob()
	if(pulledby)
		pulledby.stop_pulling()
	..()

/obj/vehicle/bike/turn_off()
	ion.stop()
	set_anchored(kickstand)

	update_icon()

	..()

/obj/vehicle/bike/bullet_act(obj/item/projectile/Proj)
	if(has_buckled_mobs() && prob(protection_percent))
		var/mob/living/L = pick(src?.buckled_mob_list())
		L.bullet_act(Proj)
		return
	..()

DECLARE_APPEARANCE_PROC(/obj/vehicle/bike, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/vehicle/bike/appearance_overlays()
	. = list()

	if(custom_icon)
		if(on)
			var/image/bodypaint = image('icons/obj/custom_items_vehicle.dmi', "[bike_icon]_on_a", src.layer)
			bodypaint.color = paint_color
			. += bodypaint

			var/image/overmob = image('icons/obj/custom_items_vehicle.dmi', "[bike_icon]_on_overlay", MOB_LAYER + 1)
			var/image/overmob_color = image('icons/obj/custom_items_vehicle.dmi', "[bike_icon]_on_overlay_a", MOB_LAYER + 1)
			overmob.plane = MOB_PLANE
			overmob_color.plane = MOB_PLANE
			overmob_color.color = paint_color
			. += overmob
			. += overmob_color
			if(open)
				icon_state = "[bike_icon]_on-open"
			else
				icon_state = "[bike_icon]_on"
		else
			var/image/bodypaint = image('icons/obj/custom_items_vehicle.dmi', "[bike_icon]_off_a", src.layer)
			bodypaint.color = paint_color
			. += bodypaint

			var/image/overmob = image('icons/obj/custom_items_vehicle.dmi', "[bike_icon]_off_overlay", MOB_LAYER + 1)
			var/image/overmob_color = image('icons/obj/custom_items_vehicle.dmi', "[bike_icon]_off_overlay_a", MOB_LAYER + 1)
			overmob.plane = MOB_PLANE
			overmob_color.plane = MOB_PLANE
			overmob_color.color = paint_color
			. += overmob
			. += overmob_color
			if(open)
				icon_state = "[bike_icon]_off-open"
			else
				icon_state = "[bike_icon]_off"
		. += ..()
		return .

	if(on)
		var/image/bodypaint = image('icons/obj/bike.dmi', "[bike_icon]_on_a", src.layer)
		bodypaint.color = paint_color
		. += bodypaint

		var/image/overmob = image('icons/obj/bike.dmi', "[bike_icon]_on_overlay", MOB_LAYER + 1)
		var/image/overmob_color = image('icons/obj/bike.dmi', "[bike_icon]_on_overlay_a", MOB_LAYER + 1)
		overmob.plane = MOB_PLANE
		overmob_color.plane = MOB_PLANE
		overmob_color.color = paint_color
		. += overmob
		. += overmob_color
		if(open)
			icon_state = "[bike_icon]_on-open"
		else
			icon_state = "[bike_icon]_on"
	else
		var/image/bodypaint = image('icons/obj/bike.dmi', "[bike_icon]_off_a", src.layer)
		bodypaint.color = paint_color
		. += bodypaint

		var/image/overmob = image('icons/obj/bike.dmi', "[bike_icon]_off_overlay", MOB_LAYER + 1)
		var/image/overmob_color = image('icons/obj/bike.dmi', "[bike_icon]_off_overlay_a", MOB_LAYER + 1)
		overmob.plane = MOB_PLANE
		overmob_color.plane = MOB_PLANE
		overmob_color.color = paint_color
		. += overmob
		. += overmob_color
		if(open)
			icon_state = "[bike_icon]_off-open"
		else
			icon_state = "[bike_icon]_off"

	. += ..()

