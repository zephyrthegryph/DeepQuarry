/obj/item/clothing/mask/smokable/cigarette
	name = "cigarette"
	desc = "A roll of tobacco and nicotine."
	icon_state = "cig"
	item_state = "cig"
	w_class = ITEMSIZE_TINY
	type_butt = /obj/item/trash/cigbutt
	chem_volume = 15
	max_smoketime = 300
	smoketime = 300
	matchmes = span_notice("USER lights their NAME with their FLAME.")
	lightermes = span_notice("USER manages to light their NAME with FLAME.")
	zippomes = span_notice(span_rose("With a flick of their wrist, USER lights their NAME with their FLAME."))
	weldermes = span_notice("USER casually lights the NAME with FLAME.")
	ignitermes = span_notice("USER fiddles with FLAME, and manages to light their NAME.")
	special_handling = TRUE

CAPABILITIES(/obj/item/clothing/mask/smokable/cigarette/joint/blunt)
	configure(reagents(add = list(REAGENT_ID_NICOTINE = 2))) // 4 total

CAPABILITIES(/obj/item/clothing/mask/smokable/cigarette)
	configure(movable_motion(throw_speed = 0.5))
	configure(item_handling(cavity_implantable = FALSE))
	configure(item_worn(slots = SLOT_EARS | SLOT_MASK))
	configure(item_combat(attack_verbs = list("burnt", "singed")))
	configure(reagents(add = list(REAGENT_ID_NICOTINE = 2)))
	op("put_out", in_hand(), stance(I_HELP, I_DISARM, I_GRAB), then(PROC_REF(put_out)))
	op("tread_out", in_hand(), stance(I_HURT), priority(OP_PRIORITY_ATTACK), then(PROC_REF(tread_out)))

/// A cigarette takes an active energy sword's flame too, after what any smokable takes.
/obj/item/clothing/mask/smokable/cigarette/item_applied(datum/act/op/A)
	..()
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/melee/energy/sword))
		var/obj/item/melee/energy/sword/S = W
		if(S.active)
			light(span_warning("[user] swings their [W], barely missing their nose. They light their [name] in the process."), user)

	return OP_OK

/obj/item/clothing/mask/smokable/cigarette/afterattack(obj/item/reagent_containers/glass/glass, mob/user as mob, proximity)
	..()
	if(!proximity)
		return
	if(istype(glass)) //you can dip cigarettes into beakers
		var/transfered = glass.reagents.trans_to_obj(src, chem_volume)
		if(transfered)	//if reagents were transfered, show the message
			to_chat(user, span_notice("You dip \the [src] into \the [glass]."))
		else			//if not, either the beaker was empty, or the cigarette was full
			if(!glass.reagents.total_volume)
				to_chat(user, span_notice("[glass] is empty."))
			else
				to_chat(user, span_notice("[src] is full."))

/// Using a lit cigarette in the hand puts it out. The clothing's own self-use still follows, as the old ..() did.
/obj/item/clothing/mask/smokable/cigarette/proc/put_out(datum/act/op/A)
	var/mob/user = A.actor
	if(lit == 1)
		act_message(user, src, others = span_notice("%U% puts out %T%."))
		quench()
	return OP_DECLINE

/// In the hurt stance the lit cigarette is dropped and trodden on.
/obj/item/clothing/mask/smokable/cigarette/proc/tread_out(datum/act/op/A)
	var/mob/user = A.actor
	if(lit == 1)
		act_message(user, src, others = span_notice("%U% drops and treads on the lit [src], putting it out instantly."))
		play_sfx(src, SFX_ITEMS_CIGS_LIGHTERS_CIG_SNUFF)
		die(1)
	return OP_DECLINE

///////////////
//CUSTOM CIGS//
///////////////
//and by custom cigs i mean craftable joints. smoke weed every day

/obj/item/clothing/mask/smokable/cigarette/joint
	name = "joint"
	desc = "A joint lovingly rolled and crafted with care. Blaze it."
	icon_state = "joint"
	max_smoketime = 400
	smoketime = 400
	chem_volume = 25

/obj/item/clothing/mask/smokable/cigarette/joint/blunt
	name = "blunt"
	desc = "A blunt lovingly rolled and crafted with care. Blaze it."
	icon_state = "cigar"
	max_smoketime = 500
	smoketime = 500
	chem_volume = 45
