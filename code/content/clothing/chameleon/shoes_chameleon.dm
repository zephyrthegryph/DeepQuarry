//*******************
//**Chameleon Shoes**
//*******************
/obj/item/clothing/shoes/chameleon
	name = "black shoes"
	icon_state = "black"
	desc = "They're comfy black shoes, with clever cloaking technology built in. It seems to have a small dial on the back of each shoe."

/// A pulse scrambles the disguise back to its base look (the cover is blown).
/obj/item/clothing/shoes/chameleon/proc/chameleon_emp_reveal(datum/act/A)
	name = "black shoes"
	desc = "A pair of black shoes."
	set_icon_state("black")

CAPABILITIES(/obj/item/clothing/shoes/chameleon)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(chameleon_emp_reveal)))
	op("shoes_chameleon_change_verb", menu(), label("Change Footwear Appearance"), needs(carried()), asks(/datum/prompt/choice, fields = list("question" = "Choose an appearance.", "title" = "Chameleon", "choices" = computed(PROC_REF(shoes_chameleon_change_verb_a1_choices)), "timeout" = 0), step = "a1"), then(PROC_REF(shoes_chameleon_change_verb)))

/// Old verb "Change Footwear Appearance".
/obj/item/clothing/shoes/chameleon/proc/shoes_chameleon_change_verb_a1_choices(datum/act/op/A)
	return GLOB.chamelion_shoe_choices

/obj/item/clothing/shoes/chameleon/proc/shoes_chameleon_change_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/picked = A.step_value("a1")
	if(get(src, /mob) != user)
		return
	if(!ispath(GLOB.chamelion_shoe_choices[picked]))
		return

	disguise(GLOB.chamelion_shoe_choices[picked])
