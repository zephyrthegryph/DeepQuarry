DECLARE_SHARED_CACHE(ashtray_overlays, GLOBAL_PROC_REF(build_ashtray_overlay), SC_NEVER)

/// Builder for ashtray_overlays: `colour` is null for the fill-level overlays.
/proc/build_ashtray_overlay(state, colour)
	var/image/I = image('icons/obj/objects.dmi', state)
	if(colour)
		I.color = colour
	return I

/obj/item/material/ashtray
	name = "ashtray"
	icon = 'icons/obj/objects.dmi'
	icon_state = "ashtray"
	randpixel = 5
	force_divisor = 0.1
	thrown_force_divisor = 0.1
	w_class = ITEMSIZE_SMALL
	var/image/base_image
	var/max_butts = 10

/obj/item/material/ashtray/Initialize(mapload, material_key)
	. = ..()
	if(!material)
		return INITIALIZE_HINT_QDEL
	icon_state = "blank" // ALLOW(decl): material-coloured, drawn by update_icon()
	max_butts = round(material.hardness/5) //This is arbitrary but whatever.
	randpixel_xy()
	update_icon()

/obj/item/material/ashtray/update_icon()
	color = null
	cut_overlays()
	add_overlay(CACHED_KEY(ashtray_overlays, "base-[material.name]", "ashtray", material.icon_colour))

	if (contents_count(src) == max_butts)
		add_overlay(CACHED_KEY(ashtray_overlays, "full", "ashtray_full", null))
		desc = "It's stuffed full."
	else if (contents_count(src) > max_butts/2)
		add_overlay(CACHED_KEY(ashtray_overlays, "half", "ashtray_half", null))
		desc = "It's half-filled."
	else
		desc = "An ashtray made of [material.display_name]."

EXTEND_INTERACTIONS(/obj/item/material/ashtray, INTERACT_ITEM(null, PROC_REF(ashtray_item)))

/// Old attackby. It never called its parent, so it always answers.
/obj/item/material/ashtray/proc/ashtray_item(mob/user, obj/item/W, datum/interaction/interaction)
	if (get_integrity() <= 0)
		return INTERACTION_HANDLED_PASS
	if (istype(W,/obj/item/trash/cigbutt) || istype(W,/obj/item/clothing/mask/smokable/cigarette) || istype(W, /obj/item/flame/match))
		if (contents_count(src) >= max_butts)
			to_chat(user, "\The [src] is full.")
			return INTERACTION_HANDLED_PASS
		user.remove_from_mob(W)
		W.forceMove(src)

		if (istype(W,/obj/item/clothing/mask/smokable/cigarette))
			var/obj/item/clothing/mask/smokable/cigarette/cig = W
			if (cig.lit == 1)
				src.visible_message("[user] crushes [cig] in \the [src], putting it out.")
				om_task_periodic_stop(cig)
				var/obj/item/butt = new cig.type_butt(src)
				cig.transfer_fingerprints_to(butt)
				// Turn mind bound cigs into butts
				if(cig.possessed_voice && cig.possessed_voice.len)
					var/mob/living/voice/V = cig.possessed_voice[1]
					butt.inhabit_item(V, null, V.tf_mob_holder, TRUE)
					qdel(V)
				consume(cig, user)
				W = butt
			else if (cig.lit == 0)
				to_chat(user, "You place [cig] in [src] without even smoking it. Why would you do that?")

		src.visible_message("[user] places [W] in [src].")
		user.update_inv_l_hand()
		user.update_inv_r_hand()
		add_fingerprint(user)
		update_icon()
	else
		to_chat(user, "You hit [src] with [W].")
		material_wear(W.force * MATERIAL_WEAR_UNIT)
	return INTERACTION_HANDLED_PASS

/obj/item/material/ashtray/throw_impact(atom/hit_atom)
	if (get_integrity() > 0)
		if (contents_count(src))
			src.visible_message(span_danger("\The [src] slams into [hit_atom], spilling its contents!"))
		for (var/obj/item/O in contents) // Dump all items out, so it ejects butts too
			O.forceMove(src.loc)
		material_wear(3 * MATERIAL_WEAR_UNIT)
		if (QDELETED(src))
			return
		update_icon()
	return ..()

/// An ashtray broken by blows shatters. Fire and acid destroy it outright.
/obj/item/material/ashtray/atom_destruction(damage_flag)
	if(damage_flag == FIRE || damage_flag == ACID)
		return ..()
	shatter()

/obj/item/material/ashtray/plastic/Initialize(mapload)
	. = ..(mapload, MAT_PLASTIC)

/obj/item/material/ashtray/bronze/Initialize(mapload)
	. = ..(mapload, MAT_BRONZE)

/obj/item/material/ashtray/glass/Initialize(mapload)
	. = ..(mapload, MAT_GLASS)

