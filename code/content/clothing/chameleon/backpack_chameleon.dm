//**********************
//**Chameleon Backpack**
//**********************
/obj/item/storage/backpack/chameleon
	name = "backpack"
	icon_state = "backpack"
	desc = "A backpack outfitted with cloaking tech. It seems to have a small dial inside, kept away from the storage."

/// A pulse scrambles the disguise back to its base look (the cover is blown).
/obj/item/storage/backpack/chameleon/proc/chameleon_emp_reveal(datum/act/A)
	name = "backpack"
	desc = "You wear this on your back and put items into it."
	set_icon_state("backpack")

CAPABILITIES(/obj/item/storage/backpack/chameleon)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(chameleon_emp_reveal)))
	op("backpack_chameleon_change_verb", menu(), label("Change Backpack Appearance"), needs(carried()), asks(/datum/prompt/choice, fields = list("question" = "Choose an appearance.", "title" = "Chameleon", "choices" = computed(PROC_REF(backpack_chameleon_change_verb_a1_choices)), "timeout" = 0), step = "a1"), then(PROC_REF(backpack_chameleon_change_verb)))

/// Old verb "Change Backpack Appearance".
/obj/item/storage/backpack/chameleon/proc/backpack_chameleon_change_verb_a1_choices(datum/act/op/A)
	return GLOB.chamelion_back_choices

/obj/item/storage/backpack/chameleon/proc/backpack_chameleon_change_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/picked = A.step_value("a1")
	if(get(src, /mob) != user)
		return
	if(!ispath(GLOB.chamelion_back_choices[picked]))
		return

	disguise(GLOB.chamelion_back_choices[picked])

	//so our overlays update.

/obj/item/storage/backpack/chameleon/full
	starts_with = list(
		/obj/item/clothing/under/chameleon,
		/obj/item/clothing/head/chameleon,
		/obj/item/clothing/suit/chameleon,
		/obj/item/clothing/shoes/chameleon,
		/obj/item/clothing/gloves/chameleon,
		/obj/item/clothing/mask/chameleon,
		/obj/item/clothing/glasses/chameleon,
		/obj/item/clothing/accessory/chameleon
	)
