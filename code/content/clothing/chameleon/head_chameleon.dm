//*****************
//**Chameleon Hat**
//*****************

/obj/item/clothing/head/chameleon
	name = "grey cap"
	icon_state = "greysoft"
	desc = "It looks like a plain hat, but upon closer inspection, there's an advanced holographic array installed inside. It seems to have a small dial inside."

/// A pulse scrambles the disguise back to its base look (the cover is blown).
/obj/item/clothing/head/chameleon/proc/chameleon_emp_reveal(datum/act/A)
	name = "grey cap"
	desc = "It's a baseball hat in a tasteful grey colour."
	set_icon_state("greysoft")

CAPABILITIES(/obj/item/clothing/head/chameleon)
	configure(item_worn(covers = 0))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(chameleon_emp_reveal)))
	op("head_chameleon_change_verb", menu(), label("Change Hat/Helmet Appearance"), needs(carried()), asks(/datum/prompt/choice, fields = list("question" = "Choose an appearance.", "title" = "Chameleon", "choices" = computed(PROC_REF(head_chameleon_change_verb_a1_choices)), "timeout" = 0), step = "a1"), then(PROC_REF(head_chameleon_change_verb)))

/// Old verb "Change Hat/Helmet Appearance".
/obj/item/clothing/head/chameleon/proc/head_chameleon_change_verb_a1_choices(datum/act/op/A)
	return GLOB.chamelion_head_choices

/obj/item/clothing/head/chameleon/proc/head_chameleon_change_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/picked = A.step_value("a1")
	if(get(src, /mob) != user)
		return
	if(!ispath(GLOB.chamelion_head_choices[picked]))
		return

	disguise(GLOB.chamelion_head_choices[picked])
