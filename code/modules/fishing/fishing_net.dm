/obj/item/material/fishing_net/get_mechanics_info(list/additional_information)
	return ..(list("It has a reach of two tiles. This version does not keep creatures inside in stasis, and is heavier while it contains a mob.") + additional_information)

/obj/item/material/fishing_net
	name = "fishing net"
	desc = "A crude fishing net."
	icon = 'icons/obj/items.dmi'
	icon_state = "net"
	item_state = "net"

	var/empty_state = "net"
	var/contain_state = "net_full"

	w_class = ITEMSIZE_SMALL
	flags = NOBLUDGEON

	slowdown = 0.5

	reach = 2

	default_material = MAT_CLOTH


	///Var for attack_self chain
	var/special_handling = FALSE

TYPE_TABLE_DECLARE(/obj/item/material/fishing_net, fishing_net_accepted_mobs, list(/mob/living/simple_mob/animal/passive/fish))

/obj/item/material/fishing_net/Initialize(mapload)
	. = ..()
	update_icon()

/obj/item/material/fishing_net/afterattack(atom/A, mob/user, proximity)
	if(get_dist(get_turf(src), A) > reach)
		return

	if(istype(A, /turf))
		var/mob/living/Target
		for(var/type in TYPE_TABLE_GET(src, fishing_net_accepted_mobs))
			Target = locate_within(A, type)
			if(Target)
				afterattack(Target, user, proximity)
				break

	if(istype(A, /mob))
		var/accept = FALSE
		for(var/D in TYPE_TABLE_GET(src, fishing_net_accepted_mobs))
			if(istype(A, D))
				accept = TRUE
		for(var/atom/At in contents_of(src))
			if(isliving(At))
				to_chat(user, span_notice("Your net is already holding something!"))
				accept = FALSE
		if(!accept)
			to_chat(user, span_filter_notice("[A] can't be trapped in \the [src]."))
			return
		var/mob/L = A
		user.visible_message(span_notice("[user] snatches [L] with \the [src]."), span_notice("You snatch [L] with \the [src]."))
		L.forceMove(src)
		update_icon()
		update_weight()
		return
	return ..()

EXTEND_INTERACTIONS(/obj/item/material/fishing_net, \
	INTERACT_SELF("Empty", PROC_REF(fishing_net_self)), \
	INTERACT_ITEM(null, PROC_REF(fishing_net_item)), \
)

/// Old attack_self: empty the net. Subtypes with special_handling fall through.
/obj/item/material/fishing_net/proc/fishing_net_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(special_handling)
		return FALSE
	for(var/mob/M in contents_of(src))
		M.forceMove(get_turf(src))
		user.visible_message(span_notice("[user] releases [M] from \the [src]."), span_notice("You release [M] from \the [src]."))
	for(var/obj/item/I in contents_of(src))
		I.forceMove(get_turf(src))
		user.visible_message(span_notice("[user] dumps \the [I] out of \the [src]."), span_notice("You dump \the [I] out of \the [src]."))
	update_icon()
	update_weight()
	return TRUE

/// Old attackby: a trapped creature may take the hit; then falls through as its ..() did.
/obj/item/material/fishing_net/proc/fishing_net_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(contents)
		for(var/mob/living/L in contents)
			if(prob(25))
				L.attackby(W, user)
	return FALSE

// ALLOW(sys_update_icon): underlays copied from the contained mobs' icons; rewrites name/desc from contents
/obj/item/material/fishing_net/update_icon() // Also updates name and desc
	underlays.Cut()
	cut_overlays()

	..()

	name = initial(name)
	desc = initial(desc)
	var/contains_mob = FALSE
	for(var/mob/M in contents_of(src))
		var/image/victim = image(M.icon, M.icon_state)
		underlays += victim
		name = "filled net"
		desc = "A net with [M] inside."
		contains_mob = TRUE

	if(contains_mob)
		icon_state = contain_state

	else
		icon_state = empty_state

	return

/obj/item/material/fishing_net/proc/update_weight()
	if(icon_state == contain_state)	// Let's not do a for loop just to see if a mob is in here.
		slowdown = initial(slowdown) * 2
		reach = 1
	else
		slowdown = initial(slowdown)
		reach = initial(reach)

/obj/item/material/fishing_net/butterfly_net
	name = "butterfly net"
	desc = "A butterfly net, it can be used to catch small critters, such as butterflies, but perhaps also friends?"
	icon = 'icons/obj/items.dmi'
	icon_state = "butterfly_net"
	item_state = "butterfly_net"

	empty_state = "butterfly_net"
	contain_state = "butterfly_net_full"

	w_class = ITEMSIZE_SMALL
	flags = NOBLUDGEON

	reach = 1

	default_material = MAT_CLOTH


	special_handling = TRUE

TYPE_TABLE(/obj/item/material/fishing_net/butterfly_net, fishing_net_accepted_mobs, list(/mob/living/simple_mob/animal/sif/glitterfly, /mob/living/carbon/human))

/obj/item/material/fishing_net/butterfly_net/afterattack(atom/A, mob/user, proximity)
	if(get_dist(get_turf(src), A) > reach)
		return

	if(istype(A, /turf))
		var/mob/living/Target
		for(var/type in TYPE_TABLE_GET(src, fishing_net_accepted_mobs))
			Target = locate_within(A, type)
			if(Target)
				afterattack(Target, user, proximity)
				break

	if(istype(A, /mob))
		var/accept = FALSE
		for(var/D in TYPE_TABLE_GET(src, fishing_net_accepted_mobs))
			if(istype(A, D))
				var/mob/M = A
				if(ishuman(M) && M.size_multiplier > 0.5)
					accept = FALSE
				else if(A == user)
					accept = FALSE
				else
					accept = TRUE
		for(var/atom/At in contents_of(src))
			if(isliving(At))
				to_chat(user, span_notice("Your net is already holding something!"))
				accept = FALSE
		if(!accept)
			to_chat(user, span_filter_notice("[A] can't be trapped in \the [src]."))
			return
		var/mob/L = A
		user.visible_message(span_notice("[user] snatches [L] with \the [src]."), span_notice("You snatch [L] with \the [src]."))
		L.forceMove(src)
		play_sfx(src, SFX_EFFECTS_PLOP, volume = 50, vary = TRUE)
		update_icon()
		update_weight()
		return
	return ..()

EXTEND_INTERACTIONS(/obj/item/material/fishing_net/butterfly_net, INTERACT_USE("Empty", PROC_REF(butterfly_net_self)))

/// Old attack_self.
/obj/item/material/fishing_net/butterfly_net/proc/butterfly_net_self(mob/user, obj/item/held, datum/interaction/interaction)
	for(var/mob/living/M in contents_of(src))
		if(!user.get_inactive_hand()) //Check if the inactive hand is empty
			M.forceMove(get_turf(src))
			M.attempt_to_scoop(user, stance = I_HELP)
			user.visible_message(span_notice("[user] scoops [M] out from \the [src]."), span_notice("You pull [M] from \the [src]."))
		else
			M.forceMove(get_turf(src))
			user.visible_message(span_notice("[user] releases [M] from \the [src]."), span_notice("You release [M] from \the [src]."))
	for(var/obj/item/I in contents_of(src))
		I.forceMove(get_turf(src))
		user.visible_message(span_notice("[user] dumps \the [I] out of \the [src]."), span_notice("You dump \the [I] out of \the [src]."))
	update_icon()
	update_weight()
	return

/obj/item/material/fishing_net/butterfly_net/container_resist(mob/living/M)
	if(prob(20))
		if(isdisposalpacket(loc))
			M.forceMove(loc)
		else
			M.forceMove(get_turf(src))
		to_chat(M, span_warning("You climb out of \the [src]."))
		update_icon()
		update_weight()
	else
		to_chat(M, span_warning("You fail to escape \the [src]."))

// ALLOW(sys_update_icon): state and name/desc depend on contained mobs; opts out of the parent's mob underlays
/obj/item/material/fishing_net/butterfly_net/update_icon() // Also updates name and desc
	underlays.Cut()
	cut_overlays()

	name = initial(name)
	desc = initial(desc)
	var/contains_mob = FALSE
	for(var/mob/M in contents_of(src))
		name = "filled butterfly net"
		desc = "A net with [M] inside."
		contains_mob = TRUE

	if(contains_mob)
		icon_state = contain_state

	else
		icon_state = empty_state

	return

/datum/crafting_recipe/butterfly_net
	name = "butterfly net"
	result = /obj/item/material/fishing_net/butterfly_net
	reqs = list(
		list(/obj/item/stack/material/cloth = 2)
	)
	time = 20
	category = CAT_MISC
