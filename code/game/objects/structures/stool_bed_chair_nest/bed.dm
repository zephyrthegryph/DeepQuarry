/* Beds... get your mind out of the gutter, they're for sleeping!
 * Contains:
 * 		Beds
 *		Roller beds
 */

/*
 * Beds
 */
/obj/structure/bed
	name = "bed"
	desc = "This is used to lie in, sleep in or strap on."
	icon = 'icons/obj/furniture.dmi'
	icon_state = "bed"
	pressure_resistance = 15
	anchored = TRUE
	can_buckle = TRUE
	buckle_dir = SOUTH
	buckle_lying = 1
	var/datum/material/material
	var/datum/material/padding_material
	var/base_icon = "bed"
	var/applies_material_colour = 1
	var/flippable = TRUE

/obj/structure/bed/Initialize(mapload, new_material, new_padding_material)
	..()
	color = null
	if(!new_material)
		new_material = MAT_STEEL
	material = get_material_by_name(new_material)
	if(!istype(material))
		stack_trace("Material of type: [new_material] does not exist.")
		return INITIALIZE_HINT_QDEL
	if(new_padding_material)
		padding_material = get_material_by_name(new_padding_material)
	update_icon()
	if(flippable) // If we can't change directions, don't bother.
		// Ugly check for chairs, beds can only be flipped north and south...
		if(istype(src,/obj/structure/bed/chair))
			make_rotatable()
		else
			make_rotatable(only_flip = TRUE)
	return INITIALIZE_HINT_NORMAL

/obj/structure/bed/get_material()
	return material

// Reuse the cache/code from stools, todo maybe unify.
DECLARE_APPEARANCE_PROC(/obj/structure/bed, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/structure/bed/appearance_overlays()
	. = list()
	// Prep icon.
	icon_state = ""
	// Base icon.
	var/cache_key = "[base_icon]-[material.name]"
	if(isnull(GLOB.stool_cache[cache_key]))
		var/image/I = image(icon, base_icon)
		if(applies_material_colour) // Goes with added var
			I.color = material.icon_colour
		GLOB.stool_cache[cache_key] = I
	. += GLOB.stool_cache[cache_key]
	// Padding overlay.
	if(padding_material)
		var/padding_cache_key = "[base_icon]-padding-[padding_material.name]"
		if(isnull(GLOB.stool_cache[padding_cache_key]))
			var/image/I =  image(icon, "[base_icon]_padding")
			I.color = padding_material.icon_colour
			GLOB.stool_cache[padding_cache_key] = I
		. += GLOB.stool_cache[padding_cache_key]
	// Strings.
	desc = initial(desc)
	if(padding_material)
		name = "[padding_material.display_name] [initial(name)]" //this is not perfect but it will do for now.
		desc += " It's made of [material.use_name] and covered with [padding_material.use_name]."
	else
		name = "[material.display_name] [initial(name)]"
		desc += " It's made of [material.use_name]."

/obj/structure/bed/CanPass(atom/movable/mover, turf/target)
	if(istype(mover) && mover.checkpass(PASSTABLE))
		return TRUE
	return ..()

/obj/structure/bed/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_item/bed_item,
	)
	..()

/// Old attackby: pad with a stack, tuck a disk/plushie in, or buckle a grabbed mob in.
/datum/interaction/entry_item/bed_item
	id = "bed_item"
	name = "Use"
	effect = /obj/structure/bed/proc/interaction_item

/obj/structure/bed/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W,/obj/item/stack))
		if(padding_material)
			to_chat(user, "\The [src] is already padded.")
			return TRUE
		var/obj/item/stack/C = W
		if(C.get_amount() < 1) // How??
			consume(C, user)
			return TRUE
		var/padding_type
		// making carpets different and not just the boring basic red no matter carpet type, consider merging material variables at stack level in future - Jack
		if(istype(W,/obj/item/stack/tile/carpet))
			var/obj/item/stack/tile/carpet/M = W
			if(M.material && (M.material.flags & MATERIAL_PADDING))
				padding_type = "[M.material.name]"
		else if(istype(W,/obj/item/stack/material))
			var/obj/item/stack/material/M = W
			if(M.material && (M.material.flags & MATERIAL_PADDING))
				padding_type = "[M.material.name]"
		if(!padding_type)
			to_chat(user, "You cannot pad \the [src] with that.")
			return TRUE
		C.use(1)
		if(!istype(src.loc, /turf))
			user.drop_from_inventory(src)
			src.forceMove(get_turf(src))
		to_chat(user, "You add padding to \the [src].")
		add_padding(padding_type)
		return TRUE

	else if(istype(W, /obj/item/disk) || (istype(W, /obj/item/toy/plushie)))
		user.drop_from_inventory(W, get_turf(src))
		W.pixel_x = 10 //make sure they reach the pillow
		W.pixel_y = -6
		if(istype(W, /obj/item/disk))
			user.visible_message(span_notice("[src] sleeps soundly. Sleep tight, disky."))

	else if(istype(W, /obj/item/grab))
		var/obj/item/grab/G = W
		var/mob/living/affecting = G?.grab_target()
		if(has_buckled_mobs()) //Handles trying to buckle someone else to a chair when someone else is on it
			to_chat(user, span_notice("\The [src] already has someone buckled to it."))
			return TRUE
		act_message(user, affecting, others = span_notice("%U% attempts to buckle %T% into \the [src]!"))
		om_task_start(/datum/om/task/timed/bed_attackby, user, src, W = W, affecting = affecting)
	return TRUE

/datum/om/task/timed/bed_attackby
	duration = 2 SECONDS
	complete_proc = /obj/structure/bed/proc/attackby_timed_done
	var/obj/item/W
	var/mob/living/affecting

/obj/structure/bed/proc/attackby_timed_done(datum/om/task/timed/bed_attackby/task)
	var/obj/item/W = task.W
	var/mob/user = task.actor
	var/mob/living/affecting = task.affecting
	affecting.forceMove(loc)
	deferred_buckle(affecting, user.name)
	consume(W, user)

/obj/structure/bed/wrench_act(mob/user, obj/item/W)
	playsound(src, W.usesound, 50, 1)
	dismantle()
	qdel(src)
	return TRUE

/obj/structure/bed/wirecutter_act(mob/user, obj/item/W)
	if(!padding_material)
		to_chat(user, "\The [src] has no padding to remove.")
		return TRUE
	to_chat(user, "You remove the padding from \the [src].")
	playsound(src, W.usesound, 100, 1)
	remove_padding()
	return TRUE

/obj/structure/bed/proc/deferred_buckle(mob/living/affecting, buckler_name)
	if(buckle_mob(affecting))
		act_message(affecting, src, MSG_SELF(span_danger("You are src?.buckled_to() to %T% by [buckler_name]!")), \
			MSG_OTHERS(span_danger("[affecting.name] is src?.buckled_to() to %T% by [buckler_name]!")), \
			MSG_BLIND(span_notice("You hear metal clanking.")))

/obj/structure/bed/proc/remove_padding()
	if(padding_material)
		padding_material.place_sheet(get_turf(src), 1)
		padding_material = null
	update_icon()

/obj/structure/bed/proc/add_padding(padding_type)
	padding_material = get_material_by_name(padding_type)
	update_icon()

/obj/structure/bed/proc/dismantle()
	material.place_sheet(get_turf(src), 1)
	if(padding_material)
		padding_material.place_sheet(get_turf(src), 1)

/obj/structure/bed/ghosts_can_use_rotate_verbs()
	return CONFIG_GET(flag/ghost_interaction)

/obj/structure/bed/can_use_rotate_verbs_while_anchored()
	return TRUE

/obj/structure/bed/psych
	name = "psychiatrist's couch"
	desc = "For prime comfort during psychiatric evaluations."
	icon_state = "psychbed"
	base_icon = "psychbed"

/obj/structure/bed/psych/Initialize(mapload)
	. = ..(mapload, MAT_WOOD, MAT_LEATHER)

/obj/structure/bed/padded/Initialize(mapload)
	. = ..(mapload, MAT_PLASTIC, MAT_CLOTH)

/obj/structure/bed/double
	name = "double bed"
	icon_state = "doublebed"
	base_icon = "doublebed"

/obj/structure/bed/double/padded/Initialize(mapload)
	. = ..(mapload, MAT_WOOD, MAT_CLOTH)

/obj/structure/bed/double/post_buckle_mob(mob/living/M as mob)
	if(M?.buckled_to() == src)
		M.pixel_y = 13
		M.old_y = 13
	else
		M.pixel_y = 0
		M.old_y = 0

/*
 * Roller beds
 */
/obj/structure/bed/roller
	name = "roller bed"
	desc = "A portable bed-on-wheels made for transporting medical patients."
	icon = 'icons/obj/rollerbed.dmi'
	icon_state = "rollerbed"
	anchored = FALSE
	surgery_cleanliness = 60
	var/bedtype = /obj/structure/bed/roller
	var/rollertype = /obj/item/roller
	flippable = FALSE

/obj/structure/bed/roller/adv
	name = "advanced roller bed"
	icon_state = "rollerbedadv"
	surgery_cleanliness = 75
	bedtype = /obj/structure/bed/roller/adv
	rollertype = /obj/item/roller/adv

APPEARANCE_NONE(/obj/structure/bed/roller)

/// Overrides bed's interaction_item(): a stack does nothing, a roller holder collapses the
/// bed, and anything else falls through to bed's own handling.
/obj/structure/bed/roller/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W,/obj/item/stack))
		return TRUE
	else if(istype(W,/obj/item/roller_holder))
		if(has_buckled_mobs())
			for(var/A in src?.buckled_mob_list())
				user_unbuckle_mob(A, user)
		else
			act_message(user, null, others = "%U% collapses \the [src.name].")
			new rollertype(get_turf(src))
			expire(0)
		return TRUE
	return ..()

/obj/structure/bed/roller/wrench_act(mob/user, obj/item/W)
	return TRUE

/obj/structure/bed/roller/wirecutter_act(mob/user, obj/item/W)
	return TRUE

/obj/item/roller
	name = "roller bed"
	desc = "A collapsed roller bed that can be carried around."
	icon = 'icons/obj/rollerbed.dmi'
	icon_state = "folded_rollerbed"
	center_of_mass_x = 17
	center_of_mass_y = 7
	slot_flags = SLOT_BACK
	w_class = ITEMSIZE_LARGE
	var/rollertype = /obj/item/roller
	var/bedtype = /obj/structure/bed/roller
	drop_sound = SFX_ITEMS_DROP_AXE
	pickup_sound = SFX_ITEMS_PICKUP_AXE

DECLARE_INTERACTIONS(/obj/item/roller, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_self.
/obj/item/roller/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	var/obj/structure/bed/roller/R = new bedtype(user.loc)
	R.add_fingerprint(user)
	consume(src, user)
	return TRUE

/// Old attackby.
/obj/item/roller/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)

	if(istype(W,/obj/item/roller_holder))
		var/obj/item/roller_holder/RH = W
		if(!RH.held)
			to_chat(user, span_notice("You collect the roller bed."))
			src.forceMove(RH)
			own_set(RH, nameof(RH.held), src)
			return INTERACTION_HANDLED_PASS

	return FALSE

/obj/item/roller/adv
	name = "advanced roller bed"
	desc = "A high-tech, compact version of the regular roller bed."
	icon_state = "folded_rollerbedadv"
	w_class = ITEMSIZE_NORMAL
	rollertype = /obj/item/roller/adv
	bedtype = /obj/structure/bed/roller/adv

/obj/item/roller_holder
	name = "roller bed rack"
	desc = "A rack for carrying a collapsed roller bed."
	icon = 'icons/obj/rollerbed.dmi'
	icon_state = "rollerbed"
	var/obj/item/roller/held

DECLARE_INTERACTIONS(/obj/item/roller_holder, INTERACT_USE(null, PROC_REF(interaction_self), REQ_BECAUSE(REQ_FIELD("held"), "the rack is empty")))

/// Old attack_self.
/obj/item/roller_holder/proc/interaction_self(mob/user, obj/item/self_item, datum/interaction/interaction)
	to_chat(user, span_notice("You deploy the roller bed."))
	var/obj/structure/bed/roller/R = new held.bedtype(user.loc)
	R.add_fingerprint(user)
	own_clear(src, nameof(held), OWN_DELETE)
	return TRUE


/obj/structure/bed/roller/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()

	play_sfx(src, SFX_EFFECTS_ROLL)

/obj/structure/bed/roller/post_buckle_mob(mob/living/M as mob)
	if(M?.buckled_to() == src)
		M.pixel_y = 6
		M.old_y = 6
		set_density(TRUE)
		icon_state = "[initial(icon_state)]_up"
	else
		M.pixel_y = 0
		M.old_y = 0
		set_density(FALSE)
		icon_state = "[initial(icon_state)]"
	update_icon()
	return ..()

/obj/structure/bed/roller/MouseDrop(over_object, src_location, over_location)
	..()
	if((over_object == usr && (in_range(src, usr) || usr.contents.Find(src))))
		if(!ishuman(usr))	return
		if(has_buckled_mobs())	return 0
		act_message(usr, null, others = "%U% collapses \the [src.name].")
		new rollertype(get_turf(src))
		expire(0)
		return

/datum/category_item/catalogue/anomalous/precursor_a/alien_bed
	name = "Precursor Alpha Object - Resting Contraption"
	desc = "This appears to be a relatively long and flat object, with the top side being made of \
	an soft material, giving it very similar characteristics to an ordinary bed. If this object was \
	designed to act as a bed, this carries several implications for whatever species had built it, such as;\
	<br><br>\
	Being capable of experiencing comfort, or at least being able to suffer from some form of fatigue.<br>\
	Developing while under the influence of gravitational forces, to be able to 'lie' on the object.<br>\
	Being within a range of sizes in order for the object to function as a bed. Too small, and the species \
	would be unable to reach the top of the object. Too large, and they would have little room to contact \
	the top side of the object.<br>\
	<br><br>\
	As a note, the size of this object appears to be within the bounds for an average human to be able to \
	rest comfortably on top of it."
	value = CATALOGUER_REWARD_EASY

/obj/structure/bed/alien
	name = "resting contraption"
	desc = "Whatever species designed this must've enjoyed relaxation as well. Looks vaguely comfy."
	catalogue_data = list(/datum/category_item/catalogue/anomalous/precursor_a/alien_bed)
	icon = 'icons/obj/abductor.dmi'
	icon_state = "bed_red"
	flippable = FALSE

APPEARANCE_NONE(/obj/structure/bed/alien)
/// Overrides bed's interaction_item(): no deconning.
/obj/structure/bed/alien/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	return TRUE

/obj/structure/bed/alien/wrench_act(mob/user, obj/item/W)
	return TRUE

/obj/structure/bed/alien/wirecutter_act(mob/user, obj/item/W)
	return TRUE

/*
 * Dirty Mattress
 */
/obj/structure/dirtybed
	name = "dirty mattress"
	desc = "A stained matress. Guess it's better than sleeping on the floor."
	icon = 'icons/obj/furniture.dmi'
	icon_state = "dirtybed"
	pressure_resistance = 15
	anchored = TRUE
	can_buckle = TRUE
	buckle_dir = SOUTH
	buckle_lying = 1

/obj/structure/dirtybed/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_item/dirtybed_item,
	)
	..()

/// Old attackby: a notice if the bed isn't anchored.
/datum/interaction/entry_item/dirtybed_item
	id = "dirtybed_item"
	name = "Use"
	offered_when = list(REQ_ON(PRED_TARGET, /obj/structure/dirtybed/proc/dirtybed_not_anchored, null))
	effect = /obj/structure/dirtybed/proc/interaction_item

/obj/structure/dirtybed/proc/dirtybed_not_anchored(mob/actor, atom/target, obj/item/held)
	return !anchored

/obj/structure/dirtybed/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	to_chat(user,span_notice(" The bed isn't secured."))
	return TRUE

/obj/structure/dirtybed/wrench_act(mob/user, obj/item/W)
	act_message(user, src, MSG_SELF("You start [anchored ? "unsecuring %T% from" : "securing %T% to"] the floor."), \
		MSG_OTHERS("%U% begins [anchored ? "unsecuring %T% from" : "securing %T% to"] the floor."))
	use_tool(user, W, src, delay = 2 SECONDS, quality = TOOL_WRENCH, volume = 100, receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
	return TRUE

/obj/structure/dirtybed/proc/wrench_act_tool_done(mob/user)
	set_anchored(!anchored)
	to_chat(user, span_notice("You [anchored ? "secured" : "unsecured"] \the [src]!"))

DECLARE_DEFAULT_CHILD(/obj/item/roller_holder, "held", /obj/item/roller)
