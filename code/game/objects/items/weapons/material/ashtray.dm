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
	set_max_butts(round(material.hardness/5)) //This is arbitrary but whatever.
	color = null
	randpixel_xy()
	set_base_overlay(CACHED_KEY(ashtray_overlays, "base-[material.name]", "ashtray", material.icon_colour))
	sync_butts()

/// How many butts it holds, as its look shows them.
/obj/item/material/ashtray/var/butts = 0
/// The dish itself, in its material's colour (made once the material is known).
/obj/item/material/ashtray/var/image/base_overlay
TRACKED(/obj/item/material/ashtray, base_overlay)
TRACKED(/obj/item/material/ashtray, max_butts)

/// The fill changes what it says about itself.
/obj/item/material/ashtray/proc/set_butts(value)
	if(butts == value)
		return FALSE
	butts = value
	tracked_changed(src, nameof(butts))
	describe_fill()
	return TRUE

SETTER(/obj/item/material/ashtray, butts)

CAPABILITIES(/obj/item/material/ashtray)
	op("add_butt", item(/obj/item), priority(above("material_interaction_item")), when(req(PROC_REF(held_is_another))), then(PROC_REF(butt_added)))

/// A click with the held item on itself is the in-hand use, not an item put in it.
/obj/item/material/ashtray/proc/held_is_another(datum/act/op/A)
	return A.held != src

/// The count follows what it holds (everything that puts butts in or spills them out ends here).
/obj/item/material/ashtray/proc/sync_butts()
	if(!set_butts(contents_count(src)))
		describe_fill()

/obj/item/material/ashtray/proc/describe_fill()
	if(butts == max_butts)
		desc = "It's stuffed full."
	else if(butts > max_butts / 2)
		desc = "It's half-filled."
	else
		desc = "An ashtray made of [material.display_name]."

/obj/item/material/ashtray/draw(datum/look/look)
	..()
	look.overlay(base_overlay)
	if(butts == max_butts)
		look.overlay(CACHED_KEY(ashtray_overlays, "full", "ashtray_full", null))
	else if(butts > max_butts / 2)
		look.overlay(CACHED_KEY(ashtray_overlays, "half", "ashtray_half", null))

/// A butt, a cigarette or a match put in; a lit cigarette is put out on the way. Any other item hits it. It never took the material's repairs (it answers first and the click ends).
/obj/item/material/ashtray/proc/butt_added(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if (get_integrity() <= 0)
		return OP_OK
	if (istype(W,/obj/item/trash/cigbutt) || istype(W,/obj/item/clothing/mask/smokable/cigarette) || istype(W, /obj/item/flame/match))
		if (contents_count(src) >= max_butts)
			to_chat(user, "\The [src] is full.")
			return OP_OK
		if(!own_bring_in(src, nameof(contents), W, null, user, TRUE, null, FALSE))
			return OP_OK

		if (istype(W,/obj/item/clothing/mask/smokable/cigarette))
			var/obj/item/clothing/mask/smokable/cigarette/cig = W
			if (cig.lit == 1)
				act_message(user, src, others = "%U% crushes [cig] in %T%, putting it out.")
				var/obj/item/butt = new cig.type_butt(src)
				cig.transfer_fingerprints_to(butt)
				// Turn mind bound cigs into butts
				if(cig.possessed_voice && cig.possessed_voice.len)
					var/mob/living/voice/V = cig.possessed_voice[1]
					butt.inhabit_item(V, null, V.tf_mob_holder, TRUE)
					spent(V)
				consume(cig, user)
				W = butt
			else if (cig.lit == 0)
				to_chat(user, "You place [cig] in [src] without even smoking it. Why would you do that?")

		act_message(user, src, others = "%U% places [W] in %T%.")
		user.update_inv_l_hand()
		user.update_inv_r_hand()
		add_fingerprint(user)
		sync_butts()
	else
		to_chat(user, "You hit [src] with [W].")
		material_wear(W.force * MATERIAL_WEAR_UNIT)
	return OP_OK

/obj/item/material/ashtray/throw_impact(atom/hit_atom)
	if (get_integrity() > 0)
		if (contents_count(src))
			src.visible_message(span_danger("\The [src] slams into [hit_atom], spilling its contents!"))
		for (var/obj/item/O in contents) // Dump all items out, so it ejects butts too
			O.forceMove(src.loc)
		material_wear(3 * MATERIAL_WEAR_UNIT)
		if (QDELETED(src))
			return
		sync_butts()
	return ..()

/// An ashtray broken by blows shatters. Fire and acid destroy it outright.
/obj/item/material/ashtray/atom_destruction(damage_flag)
	if(damage_flag == FIRE || damage_flag == ACID)
		return ..()
	shatter()

TYPE_TABLE(/obj/item/material/ashtray/plastic, weapon_forced_material, MAT_PLASTIC)

TYPE_TABLE(/obj/item/material/ashtray/bronze, weapon_forced_material, MAT_BRONZE)

TYPE_TABLE(/obj/item/material/ashtray/glass, weapon_forced_material, MAT_GLASS)

