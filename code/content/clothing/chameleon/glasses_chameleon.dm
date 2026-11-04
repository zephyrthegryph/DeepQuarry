//*********************
//**Chameleon Glasses**
//*********************

/obj/item/clothing/glasses/chameleon
	name = "Optical Meson Scanner"
	icon_state = "meson"
	item_state_slots = list(slot_r_hand_str = "meson", slot_l_hand_str = "meson")
	desc = "It looks like a plain set of mesons, but on closer inspection, it seems to have a small dial inside."
	var/list/global/clothing_choices

/obj/item/clothing/glasses/chameleon/on_materialize()
	if(!clothing_choices)
		clothing_choices = generate_chameleon_choices(/obj/item/clothing/glasses, list(src.type))
	. = ..()

/// A pulse scrambles the disguise back to its base look (the cover is blown).
/obj/item/clothing/glasses/chameleon/proc/chameleon_emp_reveal(datum/act/A)
	name = "Optical Meson Scanner"
	desc = "It's a set of mesons."
	set_icon_state("meson")

CAPABILITIES(/obj/item/clothing/glasses/chameleon)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(chameleon_emp_reveal)))
	op("glasses_chameleon_change_verb", menu(), label("Change Glasses Appearance"), needs(carried()), asks(/datum/prompt/choice, fields = list("question" = "Choose an appearance.", "title" = "Chameleon", "choices" = nameof(clothing_choices), "timeout" = 0), step = "a1"), then(PROC_REF(glasses_chameleon_change_verb)))

/// Old verb "Change Glasses Appearance".
/obj/item/clothing/glasses/chameleon/proc/glasses_chameleon_change_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/picked = A.step_value("a1")
	if(get(src, /mob) != user)
		return
	if(!ispath(clothing_choices[picked]))
		return

	disguise(clothing_choices[picked])
