//********************
//**Chameleon Gloves**
//********************

/obj/item/clothing/gloves/chameleon
	name = "black gloves"
	icon_state = "black"
	desc = "It looks like a pair of gloves, but it seems to have a small dial inside."

/// A pulse scrambles the disguise back to its base look (the cover is blown).
/obj/item/clothing/gloves/chameleon/proc/chameleon_emp_reveal(datum/act/A)
	name = "black gloves"
	desc = "It looks like a pair of gloves, but it seems to have a small dial inside."
	set_icon_state("black")

CAPABILITIES(/obj/item/clothing/gloves/chameleon)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(chameleon_emp_reveal)))
	op("gloves_chameleon_change_verb", menu(), label("Change Gloves Appearance"), needs(carried()), asks(/datum/prompt/choice, fields = list("question" = "Choose an appearance.", "title" = "Chameleon", "choices" = computed(PROC_REF(gloves_chameleon_change_verb_a1_choices)), "timeout" = 0), step = "a1"), then(PROC_REF(gloves_chameleon_change_verb)))

/// Old verb "Change Gloves Appearance".
/obj/item/clothing/gloves/chameleon/proc/gloves_chameleon_change_verb_a1_choices(datum/act/op/A)
	return GLOB.chamelion_glove_choices

/obj/item/clothing/gloves/chameleon/proc/gloves_chameleon_change_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/picked = A.step_value("a1")
	if(get(src, /mob) != user)
		return
	if(!ispath(GLOB.chamelion_glove_choices[picked]))
		return

	disguise(GLOB.chamelion_glove_choices[picked])
