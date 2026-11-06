//******************
//**Chameleon Belt**
//******************

/obj/item/storage/belt/chameleon
	name = "belt"
	desc = "Can hold various things.  It also has a small dial inside one of the pouches."
	icon_state = "utilitybelt"

/// A pulse scrambles the disguise back to its base look (the cover is blown).
/obj/item/storage/belt/chameleon/proc/chameleon_emp_reveal(datum/act/A)
	name = "belt"
	desc = "Can hold various things."
	set_icon_state("utilitybelt")

CAPABILITIES(/obj/item/storage/belt/chameleon)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(chameleon_emp_reveal)))
	op("belt_chameleon_change_verb", menu(), label("Change Belt Appearance"), needs(carried()), asks(/datum/prompt/choice, fields = list("question" = "Choose an appearance.", "title" = "Chameleon", "choices" = computed(PROC_REF(belt_chameleon_change_verb_a1_choices)), "timeout" = 0), step = "a1"), then(PROC_REF(belt_chameleon_change_verb)))

/// Old verb "Change Belt Appearance".
/obj/item/storage/belt/chameleon/proc/belt_chameleon_change_verb_a1_choices(datum/act/op/A)
	return GLOB.chamelion_belt_choices

/obj/item/storage/belt/chameleon/proc/belt_chameleon_change_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/picked = A.step_value("a1")
	if(get(src, /mob) != user)
		return
	if(!ispath(GLOB.chamelion_belt_choices[picked]))
		return

	disguise(GLOB.chamelion_belt_choices[picked])
