/mob/living/simple_mob/animal
	mob_class = MOB_CLASS_ANIMAL
	meat_type = /obj/item/reagent_containers/food/snacks/meat

	response_help  = "pets"
	response_disarm = "shoos"
	response_harm   = "hits"

	organ_names = /datum/decl/mob_organ_names/quadruped

	butchery_loot = list(\
		/obj/item/stack/animalhide = 3\
		)

TYPE_TABLE(/mob/living/simple_mob/animal, butchery_organ_types, list( \
		/obj/item/organ/internal/brain, \
		/obj/item/organ/internal/heart, \
		/obj/item/organ/internal/liver, \
		/obj/item/organ/internal/stomach, \
		/obj/item/organ/internal/intestine, \
		/obj/item/organ/internal/lungs, \
		))

/datum/decl/mob_organ_names/quadruped //Most subtypes have this basic body layout.
TYPE_TABLE(/datum/decl/mob_organ_names/quadruped, mob_organ_hit_zones, list("head", "torso", "left foreleg", "right foreleg", "left hind leg", "right hind leg", "tail"))

/mob/living/simple_mob/animal/get_examine_desc()
	return flavor_text || desc

/mob/living/simple_mob/animal/verb/set_flavour_text()
	set name = "Set Flavour Text"
	set category = "IC.Settings"
	set desc = "Set your flavour text."
	set src = usr
	om_ask(src, /datum/om/prompt/text, PROC_REF(flavour_text_entered), title = "Flavour Text", message = "Please describe yourself.", default = flavor_text, multiline = TRUE)

/mob/living/simple_mob/animal/proc/flavour_text_entered(datum/om/prompt/text/ask)
	var/new_flavour_text = ask.text
	if(length(new_flavour_text))
		flavor_text = new_flavour_text
		to_chat(src, span_notice("Your flavour text has been updated."))
