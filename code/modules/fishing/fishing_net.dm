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
		act_message(user, L, MSG_SELF(span_notice("You snatch %T% with \the [src].")), MSG_OTHERS(span_notice("%U% snatches %T% with \the [src].")))
		L.forceMove(src)
		update_weight()
		return
	return ..()

CAPABILITIES(/obj/item/material/fishing_net)
	slot(CONTAINER_SLOT_NET)
	op("fishing_net_self", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Empty"), then(PROC_REF(fishing_net_self)))
	op("fishing_net_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Fishing net item"), then(PROC_REF(fishing_net_item)))

/// Old attack_self: empty the net. Subtypes with special_handling fall through.
/obj/item/material/fishing_net/proc/fishing_net_self(datum/act/op/A)
	var/mob/user = A.actor
	if(special_handling)
		return OP_DECLINE
	for(var/mob/M in contents_of(src))
		M.forceMove(get_turf(src))
		act_message(user, M, MSG_SELF(span_notice("You release %T% from \the [src].")), MSG_OTHERS(span_notice("%U% releases %T% from \the [src].")))
	for(var/obj/item/I in contents_of(src))
		I.forceMove(get_turf(src))
		act_message(user, src, MSG_SELF(span_notice("You dump %I% out of %T%.")), MSG_OTHERS(span_notice("%U% dumps %I% out of %T%.")), item = I)
	update_weight()
	return OP_OK

/// Old attackby: a trapped creature may take the hit; then falls through as its ..() did.
/obj/item/material/fishing_net/proc/fishing_net_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(contents)
		for(var/mob/living/L in contents)
			if(prob(25))
				L.attackby(W, user)
	return OP_DECLINE

/// The net, empty or with the creatures it holds (named and described by them).
/obj/item/material/fishing_net/draw(datum/look/look)
	..()
	look.identity(name = initial(name), desc = initial(desc))
	var/trapped = 0
	for(var/mob/M as anything in look.things_in(src, CONTAINER_SLOT_NET, /mob))
		look_trapped(look, M)
		trapped++
	look.state(trapped ? contain_state : empty_state)

/// One creature in the net: seen through the mesh, and the net named for it.
/obj/item/material/fishing_net/proc/look_trapped(datum/look/look, mob/M)
	look.underlay(look_overlay_image(M.icon, M.icon_state))
	look.identity(name = "filled net", desc = "A net with [M] inside.")

/// TRUE while a creature is in the net.
/obj/item/material/fishing_net/proc/holds_creature()
	for(var/mob/M in contents_of(src))
		return TRUE
	return FALSE

/obj/item/material/fishing_net/proc/update_weight()
	if(holds_creature())
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
		act_message(user, L, MSG_SELF(span_notice("You snatch %T% with \the [src].")), MSG_OTHERS(span_notice("%U% snatches %T% with \the [src].")))
		L.forceMove(src)
		play_sfx(src, SFX_EFFECTS_PLOP, volume = 50, vary = TRUE)
		update_weight()
		return
	return ..()

CAPABILITIES(/obj/item/material/fishing_net/butterfly_net)
	op("butterfly_net_self", in_hand(), label("Empty"), then(PROC_REF(butterfly_net_self)))

/// Old attack_self.
/obj/item/material/fishing_net/butterfly_net/proc/butterfly_net_self(datum/act/op/A)
	var/mob/user = A.actor
	for(var/mob/living/M in contents_of(src))
		if(!user.get_inactive_hand()) //Check if the inactive hand is empty
			M.forceMove(get_turf(src))
			M.attempt_to_scoop(user, stance = I_HELP)
			act_message(user, M, MSG_SELF(span_notice("You pull %T% from \the [src].")), MSG_OTHERS(span_notice("%U% scoops %T% out from \the [src].")))
		else
			M.forceMove(get_turf(src))
			act_message(user, M, MSG_SELF(span_notice("You release %T% from \the [src].")), MSG_OTHERS(span_notice("%U% releases %T% from \the [src].")))
	for(var/obj/item/I in contents_of(src))
		I.forceMove(get_turf(src))
		act_message(user, src, MSG_SELF(span_notice("You dump %I% out of %T%.")), MSG_OTHERS(span_notice("%U% dumps %I% out of %T%.")), item = I)
	update_weight()
	return

/obj/item/material/fishing_net/butterfly_net/container_resist(mob/living/M)
	if(prob(20))
		if(isdisposalpacket(loc))
			M.forceMove(loc)
		else
			M.forceMove(get_turf(src))
		to_chat(M, span_warning("You climb out of \the [src]."))
		update_weight()
	else
		to_chat(M, span_warning("You fail to escape \the [src]."))

/// A butterfly net does not show its catch.
/obj/item/material/fishing_net/butterfly_net/look_trapped(datum/look/look, mob/M)
	look.identity(name = "filled butterfly net", desc = "A net with [M] inside.")

/datum/crafting_recipe/butterfly_net
	name = "butterfly net"
	result = /obj/item/material/fishing_net/butterfly_net
	reqs = list(
		list(/obj/item/stack/material/cloth = 2)
	)
	time = 20
	category = CAT_MISC
