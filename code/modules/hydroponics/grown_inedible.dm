// **********************
// Other harvested materials from plants (that are not food)
// **********************

/obj/item/grown // Grown weapons
	name = "grown_weapon"
	icon = 'icons/obj/weapons.dmi'
	var/plantname
	var/potency = 1

DECLARE_REAGENTS(/obj/item/grown, 50, null)

CAPABILITIES(/obj/item/grown)
	param(nameof(planttype_at_make), pos = 1)

/// The plant an inedible harvest is made from (its constructor param).
/obj/item/grown/var/planttype_at_make

// ALLOW(init/INSTANCE_STATE): an inedible harvest made from a plant takes its potency and chemicals
/obj/item/grown/Initialize(mapload)
	. = ..()

	//Handle some post-spawn var stuff.
	if(planttype_at_make)
		plantname = planttype_at_make
		var/datum/seed/S = SSplants.seeds[plantname]
		if(!S || !S.chems)
			return

		potency = S.get_trait(TRAIT_POTENCY)

		for(var/rid in S.chems)
			var/list/reagent_data = S.chems[rid]
			var/rtotal = reagent_data[1]
			if(reagent_data.len > 1 && potency > 0)
				rtotal += round(potency/reagent_data[2])
			reagents.add_reagent(rid,max(1,rtotal))

/obj/item/corncob
	name = "corn cob"
	desc = "A reminder of meals gone by."
	icon = 'icons/obj/trash.dmi'
	icon_state = "corncob"
	flags = NOCONDUCT
	w_class = ITEMSIZE_SMALL
	throwforce = 0
	throw_speed = 4
	throw_range = 20

DECLARE_INTERACTIONS(/obj/item/corncob, INTERACT_ITEM(null, PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/corncob/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/surgical/circular_saw) || istype(W, /obj/item/material/knife/machete/hatchet) || istype(W, /obj/item/material/knife))
		to_chat(user, span_notice("You use [W] to fashion a pipe out of the corn cob!"))
		replace_with(src, /obj/item/clothing/mask/smokable/pipe/cobpipe)
		return INTERACTION_HANDLED_PASS
	return INTERACTION_HANDLED_PASS

/obj/item/bananapeel
	name = "banana peel"
	desc = "A peel from a banana."
	icon = 'icons/obj/items.dmi'
	icon_state = "banana_peel"
	flags = NOCONDUCT
	w_class = ITEMSIZE_SMALL
	throwforce = 0
	throw_speed = 4
	throw_range = 20
