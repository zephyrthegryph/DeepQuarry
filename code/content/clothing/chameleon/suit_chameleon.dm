//******************
//**Chameleon Suit**
//******************

/obj/item/clothing/suit/chameleon
	name = "armor"
	icon_state = "armor"
	desc = "It appears to be a vest of standard armor, except this is embedded with a hidden holographic cloaker, allowing it to change it's appearance, but offering no protection.. It seems to have a small dial inside."

/// A pulse scrambles the disguise back to its base look (the cover is blown).
/obj/item/clothing/suit/chameleon/proc/chameleon_emp_reveal(datum/act/A)
	name = "armor"
	desc = "An armored vest that protects against some damage."
	set_icon_state("armor")

CAPABILITIES(/obj/item/clothing/suit/chameleon)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(chameleon_emp_reveal)))
	op("suit_chameleon_change_verb", menu(), label("Change Oversuit Appearance"), needs(carried()), asks(/datum/prompt/choice, fields = list("question" = "Choose an appearance.", "title" = "Chameleon", "choices" = computed(PROC_REF(suit_chameleon_change_verb_a1_choices)), "timeout" = 0), step = "a1"), then(PROC_REF(suit_chameleon_change_verb)))

/// Old verb "Change Oversuit Appearance".
/obj/item/clothing/suit/chameleon/proc/suit_chameleon_change_verb_a1_choices(datum/act/op/A)
	return GLOB.chamelion_suit_choices

/obj/item/clothing/suit/chameleon/proc/suit_chameleon_change_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/picked = A.step_value("a1")
	if(get(src, /mob) != user)
		return
	if(!ispath(GLOB.chamelion_suit_choices[picked]))
		return

	disguise(GLOB.chamelion_suit_choices[picked])
