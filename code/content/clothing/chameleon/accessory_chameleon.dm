//******************
//**Chameleon Tie**
//******************

/obj/item/clothing/accessory/chameleon
	name = "black tie"
	desc = "Looks like a black tie, but his one also has a dial inside."
	icon = 'icons/inventory/accessory/item.dmi'
	icon_state = "blacktie"

/// A pulse scrambles the disguise back to its base look (the cover is blown).
/obj/item/clothing/accessory/chameleon/proc/chameleon_emp_reveal(datum/act/A)
	name = "black tie"
	desc = "Looks like a black tie, but his one also has a dial inside."
	set_icon_state("blacktie")

CAPABILITIES(/obj/item/clothing/accessory/chameleon)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(chameleon_emp_reveal)))
	op("accessory_chameleon_change_verb", menu(), label("Change Accessory Appearance"), needs(carried()), asks(/datum/prompt/choice, fields = list("question" = "Choose an appearance.", "title" = "Chameleon", "choices" = computed(PROC_REF(accessory_chameleon_change_verb_a1_choices)), "timeout" = 0), step = "a1"), then(PROC_REF(accessory_chameleon_change_verb)))

/// Old verb "Change Accessory Appearance".
/obj/item/clothing/accessory/chameleon/proc/accessory_chameleon_change_verb_a1_choices(datum/act/op/A)
	return GLOB.chamelion_accessory_choices

/obj/item/clothing/accessory/chameleon/proc/accessory_chameleon_change_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/picked = A.step_value("a1")
	if(get(src, /mob) != user)
		return
	if(!ispath(GLOB.chamelion_accessory_choices[picked]))
		return

	disguise(GLOB.chamelion_accessory_choices[picked])
