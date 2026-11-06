//******************
//**Chameleon Mask**
//******************

/obj/item/clothing/mask/chameleon
	name = "gas mask"
	icon_state = "gas_alt" // file change
	desc = "It looks like a plain gask mask, but on closer inspection, it seems to have a small dial inside."

/// A pulse scrambles the disguise back to its base look (the cover is blown).
/obj/item/clothing/mask/chameleon/proc/chameleon_emp_reveal(datum/act/A)
	name = "gas mask"
	desc = "It's a gas mask."
	set_icon_state("gas_alt") // file change

CAPABILITIES(/obj/item/clothing/mask/chameleon)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(chameleon_emp_reveal)))
	op("mask_chameleon_change_verb", menu(), label("Change Mask Appearance"), needs(carried()), asks(/datum/prompt/choice, fields = list("question" = "Choose an appearance.", "title" = "Chameleon", "choices" = computed(PROC_REF(mask_chameleon_change_verb_a1_choices)), "timeout" = 0), step = "a1"), then(PROC_REF(mask_chameleon_change_verb)))

/// Old verb "Change Mask Appearance".
/obj/item/clothing/mask/chameleon/proc/mask_chameleon_change_verb_a1_choices(datum/act/op/A)
	return GLOB.chamelion_mask_choices

/obj/item/clothing/mask/chameleon/proc/mask_chameleon_change_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/picked = A.step_value("a1")
	if(get(src, /mob) != user)
		return
	if(!ispath(GLOB.chamelion_mask_choices[picked]))
		return

	disguise(GLOB.chamelion_mask_choices[picked])
