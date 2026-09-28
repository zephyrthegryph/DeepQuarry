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

/mob/living/simple_mob/animal/butchery_organ_types()
	var/static/list/types = list(
		/obj/item/organ/internal/brain,
		/obj/item/organ/internal/heart,
		/obj/item/organ/internal/liver,
		/obj/item/organ/internal/stomach,
		/obj/item/organ/internal/intestine,
		/obj/item/organ/internal/lungs,
		)
	return types

/datum/decl/mob_organ_names/quadruped //Most subtypes have this basic body layout.
	hit_zones = list("head", "torso", "left foreleg", "right foreleg", "left hind leg", "right hind leg", "tail")

/mob/living/simple_mob/animal/get_examine_desc()
	return flavor_text || desc

/mob/living/simple_mob/animal/verb/set_flavour_text()
	set name = "Set Flavour Text"
	set category = "IC.Settings"
	set desc = "Set your flavour text."
	set src = usr
	om_prompt(src, src, list("kind" = "text", "message" = "Please describe yourself.", "title" = "Flavour Text", "default" = flavor_text, "max_length" = MAX_MESSAGE_LEN, "multiline" = TRUE), PROC_REF(flavour_text_entered))

/mob/living/simple_mob/animal/proc/flavour_text_entered(mob/user, new_flavour_text, datum/om/prompt/ask)
	if(length(new_flavour_text))
		flavor_text = new_flavour_text
		to_chat(src, span_notice("Your flavour text has been updated."))
