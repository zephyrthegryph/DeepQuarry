/obj/item/clothing/under/chameleon
//starts off as black
	name = "black jumpsuit"
	icon_state = "black"
	worn_state = "black"
	desc = "It's a plain jumpsuit. It seems to have a small dial on the wrist."

/// A pulse scrambles the disguise back to its base look (the cover is blown).
/obj/item/clothing/under/chameleon/proc/chameleon_emp_reveal(datum/act/A)
	name = "psychedelic"
	desc = "Groovy!"
	set_icon_state("psyche")
	set_item_state_slots_at(slot_w_uniform_str, "psyche")

CAPABILITIES(/obj/item/clothing/under/chameleon)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(chameleon_emp_reveal)))
	op("chameleon_change_verb", menu(), label("Change Jumpsuit Appearance"), needs(carried()), asks(/datum/prompt/choice, fields = list("question" = "Choose an appearance.", "title" = "Chameleon", "choices" = computed(PROC_REF(chameleon_change_verb_a1_choices)), "timeout" = 0), step = "a1"), then(PROC_REF(chameleon_change_verb)))

/// Old verb "Change Jumpsuit Appearance".
/obj/item/clothing/under/chameleon/proc/chameleon_change_verb_a1_choices(datum/act/op/A)
	return GLOB.chamelion_jumpsuit_choices

/obj/item/clothing/under/chameleon/proc/chameleon_change_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/picked = A.step_value("a1")
	if(get(src, /mob) != user)
		return
	if(!ispath(GLOB.chamelion_jumpsuit_choices[picked]))
		return

	disguise(GLOB.chamelion_jumpsuit_choices[picked])
