
/obj/item/material/fishing_rod/get_mechanics_info(list/additional_information)
	return ..(list("Needs cable to be used. Attached bait (food containing protein, sugar or nutriment) speeds up fishing based on its amount.") + additional_information)

/obj/item/material/fishing_rod
	name = "crude fishing rod"
	desc = "A crude rod made for catching fish."
	description_antag = "Some fishing rods can be utilized as long-range, sharp weapons, though their pseudo ranged ability comes at the cost of slow speed."
	icon_state = "fishing_rod"
	item_state = "fishing_rod"
	force_divisor = 0.02
	throwforce = 1
	sharp = TRUE
	injury_kind = INJURY_PIERCE
	attack_verb = list("whipped", "battered", "slapped", "fished", "hooked")
	hitsound = SFX_WEAPONS_PUNCHMISS
	applies_material_colour = TRUE
	default_material = MAT_WOOD
	can_dull = FALSE
	var/strung = TRUE
	var/line_break = TRUE

	var/obj/item/reagent_containers/food/snacks/Bait
	var/bait_type = /obj/item/reagent_containers/food/snacks

	var/cast = FALSE

	attackspeed = 3 SECONDS

/obj/item/material/fishing_rod/built
	strung = FALSE

/obj/item/material/fishing_rod/examine(mob/user)
	. = ..()
	if(Bait)
		. += span_notice("It has [Bait] hanging on its hook: ")
		. += Bait.examine(user)

/obj/item/material/fishing_rod/item_ctrl_click(mob/user)
	if((src.loc == user || Adjacent(user)) && Bait)
		Bait.forceMove(get_turf(user))
		to_chat(user, span_notice("You remove the bait from \the [src]."))
		own_take(src, nameof(Bait))
	else
		..()

/obj/item/material/fishing_rod/Initialize(mapload)
	. = ..()
	update_icon()

/obj/item/material/fishing_rod/proc/string_done(mob/user, obj/item/stack/cable_coil/C)
	if(strung || !C.use(5))
		return
	strung = TRUE
	to_chat(user, span_notice("You string \the [src]!"))
	update_icon()

EXTEND_INTERACTIONS(/obj/item/material/fishing_rod, INTERACT_ITEM(null, PROC_REF(fishing_rod_item)))

/// Old attackby: string the rod or swap its bait; bait falls through as its ..() did.
/obj/item/material/fishing_rod/proc/fishing_rod_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(istype(I, /obj/item/stack/cable_coil) && !strung)
		var/obj/item/stack/cable_coil/C = I
		if(C.get_amount() < 5)
			to_chat(user, span_warning("You do not have enough length in \the [C] to string this!"))
			return INTERACTION_HANDLED_PASS
		task_timed(user, rand(10 SECONDS, 20 SECONDS), src, src, PROC_REF(string_done), list(user, C))
		return INTERACTION_HANDLED_PASS
	else if(istype(I, bait_type))
		if(Bait)
			Bait.forceMove(get_turf(user))
			to_chat(user, span_notice("You swap \the [Bait] with \the [I]."))
		if(!move_into(src, nameof(src.Bait), I, user))
			return INTERACTION_HANDLED_PASS
		update_bait()
	return FALSE

/obj/item/material/fishing_rod/wirecutter_act(mob/user, obj/item/tool)
	if(!strung)
		return ITEM_INTERACT_BLOCKING
	strung = FALSE
	to_chat(user, span_notice("You cut \the [src]'s string!"))
	update_icon()
	return ITEM_INTERACT_SUCCESS

DECLARE_APPEARANCE_PROC(/obj/item/material/fishing_rod, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/material/fishing_rod/appearance_overlays()
	. = list()
	. += ..()
	if(strung)
		. += "[icon_state]_string"

/obj/item/material/fishing_rod/proc/update_bait()
	if(istype(Bait, bait_type))
		var/foodvolume
		for(var/datum/reagent/re in Bait.reagents.reagent_list)
			if(re.id == REAGENT_ID_NUTRIMENT || re.id == REAGENT_ID_PROTEIN || re.id == REAGENT_ID_GLUCOSE || re.id == REAGENT_ID_FISHBAIT)
				foodvolume += re.volume

		toolspeed = initial(toolspeed) * 10*(0.01/(0.2*(foodvolume/Bait.reagents.maximum_volume + 0.5))) // gives fishing a universal formula because Polaris' doesn't work here. Min value of 1, max value of 1/3, 0.5 at 1/2 filled with bait reagents.

	else
		toolspeed = initial(toolspeed)

/obj/item/material/fishing_rod/proc/consume_bait()
	if(Bait)
		own_clear(src, nameof(Bait), OWN_DELETE)
		return TRUE
	return FALSE

/obj/item/material/fishing_rod/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(cast)
		to_chat(user, span_notice("You cannot cast \the [src] when it is already in use!"))
		return ITEM_INTERACT_FAILURE
	update_bait()
	return ..()

/obj/item/material/fishing_rod/modern
	name = "fishing rod"
	desc = "A refined rod for catching fish."
	icon_state = "fishing_rod_modern"
	item_state = "fishing_rod"
	reach = 4
	attackspeed = 2 SECONDS
	default_material = MAT_TITANIUM

	toolspeed = 0.75

/obj/item/material/fishing_rod/modern/built
	strung = FALSE

/obj/item/material/fishing_rod/modern/cheap //A rod sold by the fishing vendor. Done so that the rod sold by mining reward vendors doesn't loose its value.
	name = "cheap fishing rod"
	desc = "Mass produced, but somewhat reliable."
	default_material = MAT_PLASTIC

	toolspeed = 0.9


/obj/item/material/fishing_rod/modern/strong
	desc = "A extremely refined rod for catching fish."
	default_material = MAT_DURASTEEL

	toolspeed = 0.5

// The bait sits in the rod's contents.
/obj/item/material/fishing_rod/ownership()
	. = ..()
	. += owns(nameof(Bait), policy = OWN_CONTAINED)
