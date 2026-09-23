/mob/living/carbon/human/examine(mob/user)
	SHOULD_CALL_PARENT(FALSE)
	// . = ..() //Note that we don't call parent. We build the list by ourselves.

	var/skip_gear = 0
	var/skip_body = 0

	if(alpha <= EFFECTIVE_INVIS)
		return src.loc.examine(user) // Returns messages as if they examined wherever the human was

	var/looks_synth = looksSynthetic()

	//exosuits and helmets obscure our view and stuff.
	if(get_equipped_item(SLOT_ID_SUIT))
		if(get_equipped_item(SLOT_ID_SUIT).flags_inv & HIDESUITSTORAGE)
			skip_gear |= EXAMINE_SKIPSUITSTORAGE

		if(get_equipped_item(SLOT_ID_SUIT).flags_inv & HIDEJUMPSUIT)
			skip_body |= EXAMINE_SKIPARMS | EXAMINE_SKIPLEGS | EXAMINE_SKIPBODY | EXAMINE_SKIPGROIN
			skip_gear |= EXAMINE_SKIPJUMPSUIT | EXAMINE_SKIPTIE | EXAMINE_SKIPHOLSTER

		else if(get_equipped_item(SLOT_ID_SUIT).flags_inv & HIDETIE)
			skip_gear |= EXAMINE_SKIPTIE | EXAMINE_SKIPHOLSTER

		else if(get_equipped_item(SLOT_ID_SUIT).flags_inv & HIDEHOLSTER)
			skip_gear |= EXAMINE_SKIPHOLSTER

		if(get_equipped_item(SLOT_ID_SUIT).flags_inv & HIDESHOES)
			skip_gear |= EXAMINE_SKIPSHOES
			skip_body |= EXAMINE_SKIPFEET

		if(get_equipped_item(SLOT_ID_SUIT).flags_inv & HIDEGLOVES)
			skip_gear |= EXAMINE_SKIPGLOVES
			skip_body |= EXAMINE_SKIPHANDS

	if(get_equipped_item(SLOT_ID_UNIFORM))
		if(get_equipped_item(SLOT_ID_UNIFORM).body_parts_covered & LEGS)
			skip_body |= EXAMINE_SKIPLEGS
		if(get_equipped_item(SLOT_ID_UNIFORM).body_parts_covered & ARMS)
			skip_body |= EXAMINE_SKIPARMS
		if(get_equipped_item(SLOT_ID_UNIFORM).body_parts_covered & UPPER_TORSO)
			skip_body |= EXAMINE_SKIPBODY
		if(get_equipped_item(SLOT_ID_UNIFORM).body_parts_covered & LOWER_TORSO)
			skip_body |= EXAMINE_SKIPGROIN

	if(get_equipped_item(SLOT_ID_GLOVES) && (get_equipped_item(SLOT_ID_GLOVES).body_parts_covered & HANDS))
		skip_body |= EXAMINE_SKIPHANDS

	if(get_equipped_item(SLOT_ID_SHOES) && (get_equipped_item(SLOT_ID_SHOES).body_parts_covered & FEET))
		skip_body |= EXAMINE_SKIPFEET

	if(get_equipped_item(SLOT_ID_HEAD))
		if(get_equipped_item(SLOT_ID_HEAD).flags_inv & HIDEMASK)
			skip_gear |= EXAMINE_SKIPMASK
		if(get_equipped_item(SLOT_ID_HEAD).flags_inv & HIDEEYES)
			skip_gear |= EXAMINE_SKIPEYEWEAR
			skip_body |= EXAMINE_SKIPEYES
		if(get_equipped_item(SLOT_ID_HEAD).flags_inv & HIDEEARS)
			skip_gear |= EXAMINE_SKIPEARS
		if(get_equipped_item(SLOT_ID_HEAD).flags_inv & HIDEFACE)
			skip_body |= EXAMINE_SKIPFACE

	if(get_equipped_item(SLOT_ID_MASK) && (get_equipped_item(SLOT_ID_MASK).flags_inv & HIDEFACE))
		skip_body |= EXAMINE_SKIPFACE

	//This is what hides what
	var/list/hidden = list(
		BP_GROIN = skip_body & EXAMINE_SKIPGROIN,
		BP_TORSO = skip_body & EXAMINE_SKIPBODY,
		BP_HEAD  = skip_body & EXAMINE_SKIPHEAD,
		BP_L_ARM = skip_body & EXAMINE_SKIPARMS,
		BP_R_ARM = skip_body & EXAMINE_SKIPARMS,
		BP_L_HAND= skip_body & EXAMINE_SKIPHANDS,
		BP_R_HAND= skip_body & EXAMINE_SKIPHANDS,
		BP_L_FOOT= skip_body & EXAMINE_SKIPFEET,
		BP_R_FOOT= skip_body & EXAMINE_SKIPFEET,
		BP_L_LEG = skip_body & EXAMINE_SKIPLEGS,
		BP_R_LEG = skip_body & EXAMINE_SKIPLEGS)

	var/name_ender = ""
	if(!((skip_gear & EXAMINE_SKIPJUMPSUIT) && (skip_body & EXAMINE_SKIPFACE)))
		if(custom_species)
			name_ender = ", a " + span_bold("[src.custom_species]")
		else if(looks_synth)
			var/use_gender = "a synthetic"
			if(gender == MALE)
				use_gender = "an android"
			else if(gender == FEMALE)
				use_gender = "a gynoid"

			name_ender = ", " + span_bold(span_gray("[use_gender]!")) + "[species.get_additional_examine_text(src)]"

		else if(species.name != "Human")
			name_ender = ", " + span_bold("<font color='[species.get_flesh_colour(src)]'>\a [species.get_examine_name()]!</font>") + "[species.get_additional_examine_text(src)]"

	var/list/msg = list("This is [icon2html(src, user.client)] <EM>[src.name]</EM>[name_ender]")

	//uniform
	if(get_equipped_item(SLOT_ID_UNIFORM) && !(skip_gear & EXAMINE_SKIPJUMPSUIT) && get_equipped_item(SLOT_ID_UNIFORM).show_examine)
		//Ties
		var/tie_msg
		if(istype(get_equipped_item(SLOT_ID_UNIFORM),/obj/item/clothing/under) && !(skip_gear & EXAMINE_SKIPTIE))
			var/obj/item/clothing/under/U = get_equipped_item(SLOT_ID_UNIFORM)
			if(LAZYLEN(U.accessories))
				tie_msg += ". Attached to it is"
				var/list/accessory_descs = list()
				if(skip_gear & EXAMINE_SKIPHOLSTER)
					for(var/obj/item/clothing/accessory/A in U.accessories)
						if(A.show_examine && !istype(A, /obj/item/clothing/accessory/holster)) // If we're supposed to skip holsters, actually skip them
							accessory_descs += "\a [A]"
				else
					for(var/obj/item/clothing/accessory/A in U.accessories)
						if(A.concealed_holster == 0 && A.show_examine)
							accessory_descs += "<a href='byond://?src=\ref[src];lookitem_desc_only=\ref[A]'>\a [A]</a>"

				tie_msg += " [lowertext(english_list(accessory_descs))]."
		if(get_equipped_item(SLOT_ID_UNIFORM).forensic_data?.has_blooddna())
			msg += span_warning("[p_Theyre()] wearing [icon2html(get_equipped_item(SLOT_ID_UNIFORM),user.client)] [get_equipped_item(SLOT_ID_UNIFORM).gender==PLURAL?"some":"a"] [(dq_get_blood_color(get_equipped_item(SLOT_ID_UNIFORM)) != "#030303") ? "blood" : "oil"]-stained <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_UNIFORM)]'>[get_equipped_item(SLOT_ID_UNIFORM).name]</a>![tie_msg]")
		else
			msg += "[p_Theyre()] wearing [icon2html(get_equipped_item(SLOT_ID_UNIFORM),user.client)] <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_UNIFORM)]'>\a [get_equipped_item(SLOT_ID_UNIFORM)]</a>.[tie_msg]"

	//head
	if(get_equipped_item(SLOT_ID_HEAD) && !(skip_gear & EXAMINE_SKIPHELMET) && get_equipped_item(SLOT_ID_HEAD).show_examine)
		if(get_equipped_item(SLOT_ID_HEAD).forensic_data?.has_blooddna())
			msg += span_warning("[p_Theyre()] wearing [icon2html(get_equipped_item(SLOT_ID_HEAD),user.client)] [get_equipped_item(SLOT_ID_HEAD).gender==PLURAL?"some":"a"] [(dq_get_blood_color(get_equipped_item(SLOT_ID_HEAD)) != "#030303") ? "blood" : "oil"]-stained <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_HEAD)]'>[get_equipped_item(SLOT_ID_HEAD).name]</a> on [p_their()] head!")
		else
			msg += "[p_Theyre()] wearing [icon2html(get_equipped_item(SLOT_ID_HEAD),user.client)] <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_HEAD)]'>\a [get_equipped_item(SLOT_ID_HEAD)]</a> on [p_their()] head."

	//suit/armour
	if(get_equipped_item(SLOT_ID_SUIT))
		var/tie_msg
		if(istype(get_equipped_item(SLOT_ID_SUIT),/obj/item/clothing/suit))
			var/obj/item/clothing/suit/U = get_equipped_item(SLOT_ID_SUIT)
			if(LAZYLEN(U.accessories))
				tie_msg += ". Attached to it is"
				var/list/accessory_descs = list()
				for(var/accessory in U.accessories)
					accessory_descs += "<a href='byond://?src=\ref[src];lookitem_desc_only=\ref[accessory]'>\a [accessory]</a>"
				tie_msg += " [lowertext(english_list(accessory_descs))]."

		if(get_equipped_item(SLOT_ID_SUIT).forensic_data?.has_blooddna())
			msg += span_warning("[p_Theyre()] wearing [icon2html(get_equipped_item(SLOT_ID_SUIT),user.client)] [get_equipped_item(SLOT_ID_SUIT).gender==PLURAL?"some":"a"] [(dq_get_blood_color(get_equipped_item(SLOT_ID_SUIT)) != "#030303") ? "blood" : "oil"]-stained <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_SUIT)]'>[get_equipped_item(SLOT_ID_SUIT).name]</a>![tie_msg]")
		else
			msg += "[p_Theyre()] wearing [icon2html(get_equipped_item(SLOT_ID_SUIT),user.client)] <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_SUIT)]'>\a [get_equipped_item(SLOT_ID_SUIT)]</a>.[tie_msg]"

		//suit/armour storage
		if(get_equipped_item(SLOT_ID_SUIT_STORAGE) && !(skip_gear & EXAMINE_SKIPSUITSTORAGE) && get_equipped_item(SLOT_ID_SUIT_STORAGE).show_examine)
			if(get_equipped_item(SLOT_ID_SUIT_STORAGE).forensic_data?.has_blooddna())
				msg += span_warning("[p_Theyre()] carrying [icon2html(get_equipped_item(SLOT_ID_SUIT_STORAGE),user.client)] [get_equipped_item(SLOT_ID_SUIT_STORAGE).gender==PLURAL?"some":"a"] [(dq_get_blood_color(get_equipped_item(SLOT_ID_SUIT_STORAGE)) != "#030303") ? "blood" : "oil"]-stained <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_SUIT_STORAGE)]'>[get_equipped_item(SLOT_ID_SUIT_STORAGE).name]</a> on [p_their()] [get_equipped_item(SLOT_ID_SUIT).name]!")
			else
				msg += "[p_Theyre()] carrying [icon2html(get_equipped_item(SLOT_ID_SUIT_STORAGE),user.client)] <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_SUIT_STORAGE)]'>\a [get_equipped_item(SLOT_ID_SUIT_STORAGE)]</a> on [p_their()] [get_equipped_item(SLOT_ID_SUIT).name]."

	//back
	if(get_equipped_item(SLOT_ID_BACK) && !(skip_gear & EXAMINE_SKIPBACKPACK) && get_equipped_item(SLOT_ID_BACK).show_examine)
		if(get_equipped_item(SLOT_ID_BACK).forensic_data?.has_blooddna())
			msg += span_warning("[p_They()] [p_have()] [icon2html(get_equipped_item(SLOT_ID_BACK),user.client)] [get_equipped_item(SLOT_ID_BACK).gender==PLURAL?"some":"a"] [(dq_get_blood_color(get_equipped_item(SLOT_ID_BACK)) != "#030303") ? "blood" : "oil"]-stained <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_BACK)]'>[get_equipped_item(SLOT_ID_BACK)]</a> on [p_their()] back.")
		else
			msg += "[p_They()] [p_have()] [icon2html(get_equipped_item(SLOT_ID_BACK),user.client)] <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_BACK)]'>\a [get_equipped_item(SLOT_ID_BACK)]</a> on [p_their()] back."

	//left hand
	if(get_equipped_item(SLOT_ID_HAND_L) && get_equipped_item(SLOT_ID_HAND_L).show_examine)
		if(get_equipped_item(SLOT_ID_HAND_L).forensic_data?.has_blooddna())
			msg += span_warning("[p_Theyre()] holding [icon2html(get_equipped_item(SLOT_ID_HAND_L),user.client)] [get_equipped_item(SLOT_ID_HAND_L).gender==PLURAL?"some":"a"] [(dq_get_blood_color(get_equipped_item(SLOT_ID_HAND_L)) != "#030303") ? "blood" : "oil"]-stained <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_HAND_L)]'>[get_equipped_item(SLOT_ID_HAND_L).name]</a> in [p_their()] left hand!")
		else
			msg += "[p_Theyre()] holding [icon2html(get_equipped_item(SLOT_ID_HAND_L),user.client)] <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_HAND_L)]'>\a [get_equipped_item(SLOT_ID_HAND_L)]</a> in [p_their()] left hand."

	//right hand
	if(get_equipped_item(SLOT_ID_HAND_R) && get_equipped_item(SLOT_ID_HAND_R).show_examine)
		if(get_equipped_item(SLOT_ID_HAND_R).forensic_data?.has_blooddna())
			msg += span_warning("[p_Theyre()] holding [icon2html(get_equipped_item(SLOT_ID_HAND_R),user.client)] [get_equipped_item(SLOT_ID_HAND_R).gender==PLURAL?"some":"a"] [(dq_get_blood_color(get_equipped_item(SLOT_ID_HAND_R)) != "#030303") ? "blood" : "oil"]-stained <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_HAND_R)]'>[get_equipped_item(SLOT_ID_HAND_R).name]</a> in [p_their()] right hand!")
		else
			msg += "[p_Theyre()] holding [icon2html(get_equipped_item(SLOT_ID_HAND_R),user.client)] <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_HAND_R)]'>\a [get_equipped_item(SLOT_ID_HAND_R)]</a> in [p_their()] right hand."

	//gloves
	if(get_equipped_item(SLOT_ID_GLOVES) && !(skip_gear & EXAMINE_SKIPGLOVES) && get_equipped_item(SLOT_ID_GLOVES).show_examine)
		var/gloves_acc_msg
		if(istype(get_equipped_item(SLOT_ID_GLOVES),/obj/item/clothing/gloves))
			var/obj/item/clothing/gloves/G = get_equipped_item(SLOT_ID_GLOVES)
			if(LAZYLEN(G.accessories))
				gloves_acc_msg += ". Attached to it is"
				var/list/accessory_descs = list()
				for(var/obj/item/clothing/accessory/A in G.accessories)
					accessory_descs += "<a href='byond://?src=\ref[src];lookitem_desc_only=\ref[A]'>\a [A]</a>"

				gloves_acc_msg += " [lowertext(english_list(accessory_descs))]."
		if(get_equipped_item(SLOT_ID_GLOVES).forensic_data?.has_blooddna())
			msg += span_warning("[p_They()] [p_have()] [icon2html(get_equipped_item(SLOT_ID_GLOVES),user.client)] [get_equipped_item(SLOT_ID_GLOVES).gender==PLURAL?"some":"a"] [(dq_get_blood_color(get_equipped_item(SLOT_ID_GLOVES)) != "#030303") ? "blood" : "oil"]-stained <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_GLOVES)]'>[get_equipped_item(SLOT_ID_GLOVES).name]</a> on [p_their()] hands![gloves_acc_msg]")
		else
			msg += "[p_They()] [p_have()] [icon2html(get_equipped_item(SLOT_ID_GLOVES),user.client)] <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_GLOVES)]'>\a [get_equipped_item(SLOT_ID_GLOVES)]</a> on [p_their()] hands.[gloves_acc_msg]"

	else if(forensic_data?.has_blooddna() && !(skip_body & EXAMINE_SKIPHANDS))
		msg += span_warning("[p_They()] [p_have()] [(hand_blood_color != SYNTH_BLOOD_COLOUR) ? "blood" : "oil"]-stained hands!")

	//handcuffed?
	if(get_equipped_item(SLOT_ID_HANDCUFFED) && get_equipped_item(SLOT_ID_HANDCUFFED).show_examine)
		if(istype(get_equipped_item(SLOT_ID_HANDCUFFED), /obj/item/handcuffs/cable))
			msg += span_warning("[p_Theyre()] [icon2html(get_equipped_item(SLOT_ID_HANDCUFFED),user.client)] restrained with cable!")
		else
			msg += span_warning("[p_Theyre()] [icon2html(get_equipped_item(SLOT_ID_HANDCUFFED),user.client)] handcuffed!")

	//buckled
	if(buckled)
		msg += span_warning("[p_Theyre()] [icon2html(buckled,user.client)] buckled to [buckled]!")

	//belt
	if(get_equipped_item(SLOT_ID_BELT) && !(skip_gear & EXAMINE_SKIPBELT) && get_equipped_item(SLOT_ID_BELT).show_examine)
		if(get_equipped_item(SLOT_ID_BELT).forensic_data?.has_blooddna())
			msg += span_warning("[p_They()] [p_have()] [icon2html(get_equipped_item(SLOT_ID_BELT),user.client)] [get_equipped_item(SLOT_ID_BELT).gender==PLURAL?"some":"a"] [(dq_get_blood_color(get_equipped_item(SLOT_ID_BELT)) != "#030303") ? "blood" : "oil"]-stained <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_BELT)]'>[get_equipped_item(SLOT_ID_BELT).name]</a> about [p_their()] waist!")
		else
			msg += "[p_They()] [p_have()] [icon2html(get_equipped_item(SLOT_ID_BELT),user.client)] <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_BELT)]'>\a [get_equipped_item(SLOT_ID_BELT)]</a> about [p_their()] waist."

	//shoes
	if(get_equipped_item(SLOT_ID_SHOES) && !(skip_gear & EXAMINE_SKIPSHOES) && get_equipped_item(SLOT_ID_SHOES).show_examine)
		if(get_equipped_item(SLOT_ID_SHOES).forensic_data?.has_blooddna())
			msg += span_warning("[p_Theyre()] wearing [icon2html(get_equipped_item(SLOT_ID_SHOES),user.client)] [get_equipped_item(SLOT_ID_SHOES).gender==PLURAL?"some":"a"] [(dq_get_blood_color(get_equipped_item(SLOT_ID_SHOES)) != "#030303") ? "blood" : "oil"]-stained <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_SHOES)]'>[get_equipped_item(SLOT_ID_SHOES).name]</a> on [p_their()] feet!")
		else
			msg += "[p_Theyre()] wearing [icon2html(get_equipped_item(SLOT_ID_SHOES),user.client)] <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_SHOES)]'>\a [get_equipped_item(SLOT_ID_SHOES)]</a> on [p_their()] feet."
	else if(feet_blood_DNA && !(skip_body & EXAMINE_SKIPHANDS))
		msg += span_warning("[p_They()] [p_have()] [(feet_blood_color != SYNTH_BLOOD_COLOUR) ? "blood" : "oil"]-stained feet!")

	//mask
	if(get_equipped_item(SLOT_ID_MASK) && !(skip_gear & EXAMINE_SKIPMASK) && get_equipped_item(SLOT_ID_MASK).show_examine)
		var/descriptor = "on [p_their()] face"
		if(istype(get_equipped_item(SLOT_ID_MASK), /obj/item/grenade) && check_has_mouth())
			descriptor = "in [p_their()] mouth"

		if(get_equipped_item(SLOT_ID_MASK).forensic_data?.has_blooddna())
			msg += span_warning("[p_They()] [p_have()] [icon2html(get_equipped_item(SLOT_ID_MASK),user.client)] [get_equipped_item(SLOT_ID_MASK).gender==PLURAL?"some":"a"] [(dq_get_blood_color(get_equipped_item(SLOT_ID_MASK)) != "#030303") ? "blood" : "oil"]-stained <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_MASK)]'>[get_equipped_item(SLOT_ID_MASK).name]</a> [descriptor]!")
		else
			msg += "[p_They()] [p_have()] [icon2html(get_equipped_item(SLOT_ID_MASK),user.client)] <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_MASK)]'>\a [get_equipped_item(SLOT_ID_MASK)]</a> [descriptor]."

	//eyes
	if(get_equipped_item(SLOT_ID_EYES) && !(skip_gear & EXAMINE_SKIPEYEWEAR) && get_equipped_item(SLOT_ID_EYES).show_examine)
		if(get_equipped_item(SLOT_ID_EYES).forensic_data?.has_blooddna())
			msg += span_warning("[p_They()] [p_have()] [icon2html(get_equipped_item(SLOT_ID_EYES),user.client)] [get_equipped_item(SLOT_ID_EYES).gender==PLURAL?"some":"a"] [(dq_get_blood_color(get_equipped_item(SLOT_ID_EYES)) != "#030303") ? "blood" : "oil"]-stained <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_EYES)]'>[get_equipped_item(SLOT_ID_EYES)]</a> covering [p_their()] eyes!")
		else
			msg += "[p_They()] [p_have()] [icon2html(get_equipped_item(SLOT_ID_EYES),user.client)] <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_EYES)]'>\a [get_equipped_item(SLOT_ID_EYES)]</a> covering [p_their()] eyes."

	//left ear
	if(get_equipped_item(SLOT_ID_EAR_L) && !(skip_gear & EXAMINE_SKIPEARS) && get_equipped_item(SLOT_ID_EAR_L).show_examine)
		msg += "[p_They()] [p_have()] [icon2html(get_equipped_item(SLOT_ID_EAR_L),user.client)] <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_EAR_L)]'>\a [get_equipped_item(SLOT_ID_EAR_L)]</a> on [p_their()] left ear."

	//right ear
	if(get_equipped_item(SLOT_ID_EAR_R) && !(skip_gear & EXAMINE_SKIPEARS) && get_equipped_item(SLOT_ID_EAR_R).show_examine)
		msg += "[p_They()] [p_have()] [icon2html(get_equipped_item(SLOT_ID_EAR_R),user.client)] <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_EAR_R)]'>\a [get_equipped_item(SLOT_ID_EAR_R)]</a> on [p_their()] right ear."

	//ID
	if(get_equipped_item(SLOT_ID_ID) && get_equipped_item(SLOT_ID_ID).show_examine)
		msg += "[p_Theyre()] wearing [icon2html(get_equipped_item(SLOT_ID_ID),user.client)]<a href='byond://?src=\ref[src];lookitem_desc_only=\ref[get_equipped_item(SLOT_ID_ID)]'>\a [get_equipped_item(SLOT_ID_ID)]</a>."

	//Jitters
	var/jitter = get_jittery()
	if(jitter)
		if(jitter >= 300)
			msg += span_boldwarning("[p_Theyre()] convulsing violently!")
		else if(jitter >= 200)
			msg += span_warning("[p_Theyre()] extremely jittery.")
		else if(jitter >= 100)
			msg += span_warning("[p_Theyre()] twitching ever so slightly.")

	//splints
	for(var/organ in BP_ALL)
		var/obj/item/organ/external/o = get_organ(organ)
		if(o && o.splinted && o.splinted.loc == o)
			msg += span_warning("[p_They()] [p_have()] \a [o.splinted] on [p_their()] [o.name]!")

	if(suiciding)
		msg += span_warning("[p_They()] appears to have commited suicide... there is no hope of recovery.")

	var/list/vorestrings = list()
	vorestrings += examine_weight()
	vorestrings += examine_nutrition()
	vorestrings += formatted_vore_examine()
	vorestrings += examine_pickup_size()
	vorestrings += examine_step_size()
	vorestrings += examine_nif()
	vorestrings += examine_chimera()
	vorestrings += examine_body_writing(hidden)
	for(var/entry in vorestrings)
		if(entry == "" || entry == null)
			vorestrings -= entry
	msg += vorestrings

	if(has_mutation(mSmallsize))
		msg += "[p_Theyre()] very short!"

	if (src.stat || (status_flags & FAKEDEATH))
		msg += span_warning("[p_Theyre()] not responding to anything around [p_them()] and seems to be asleep.")
		var/obj/item/organ/internal/lungs/L = internal_organs_by_name[O_LUNGS]
		if(((stat == DEAD || losebreath || !L || (status_flags & FAKEDEATH)) && get_dist(user, src) <= 3))
			msg += span_warning("[p_They()] [user.p_do()] not appear to be breathing.")
		if(ishuman(user) && !user.stat && Adjacent(user))
			user.visible_message(span_infoplain(span_bold("[user]") + " checks [src]'s pulse."), span_infoplain("You check [src]'s pulse."))
		spawn(15)
			if(isobserver(user) || (Adjacent(user) && !user.stat)) // If you're a corpse then you can't exactly check their pulse, but ghosts can see anything
				if(pulse == PULSE_NONE)
					to_chat(user, span_deadsay("[p_They()] [p_have()] no pulse[src.client ? "" : " and [p_their()] soul has departed"]..."))
				else
					to_chat(user, span_deadsay("[p_They()] [p_have()] a pulse!"))

	if(fire_stacks)
		msg += "[p_Theyre()] covered in some liquid."
	if(on_fire)
		msg += span_warning("[p_Theyre()] on fire!.")

	var/ssd_msg = species.get_ssd(src)
	if(ssd_msg && (!should_have_organ(O_BRAIN) || has_brain()) && stat != DEAD && !(status_flags & FAKEDEATH))
		if(!key)
			msg += span_deadsay("[p_Theyre()] [ssd_msg]. It doesn't look like [p_theyre()] waking up anytime soon.")
		else if(!client)
			msg += span_deadsay("[p_Theyre()] [ssd_msg].")
		if(client && away_from_keyboard && manual_afk)
			msg += "\[Away From Keyboard for [round((client.inactivity/10)/60)] minutes\]"
		else if(client && ((client.inactivity / 10) / 60 > 10)) //10 Minutes
			msg += "\[Inactive for [round((client.inactivity/10)/60)] minutes\]"
		else if(disconnect_time)
			msg += "\[Disconnected/ghosted [round(((world.realtime - disconnect_time)/10)/60)] minutes ago\]"

	var/list/wound_flavor_text = list()
	var/list/is_bleeding = list()
	var/applying_pressure = ""

	for(var/organ_tag in species.has_limbs)

		var/list/organ_data = species.has_limbs[organ_tag]
		var/organ_descriptor = organ_data["descriptor"]

		var/obj/item/organ/external/E = organs_by_name[organ_tag]
		if(!E)
			wound_flavor_text["[organ_descriptor]"] = span_boldwarning("[p_Theyre()] missing [p_their()] [organ_descriptor].")
		else if(E.is_stump())
			wound_flavor_text["[organ_descriptor]"] = span_boldwarning("[p_They()] [p_have()] a stump where [p_their()] [organ_descriptor] should be.")
		else
			continue

	for(var/obj/item/organ/external/temp in organs)
		if(temp)
			if((temp.organ_tag in hidden) && hidden[temp.organ_tag])
				continue //Organ is hidden, don't talk about it
			if(temp.status & ORGAN_DESTROYED)
				wound_flavor_text["[temp.name]"] = span_boldwarning("[p_Theyre()] missing [p_their()] [temp.name].")
				continue

			if(!looks_synth && temp.robotic == ORGAN_ROBOT)
				if(!(temp.get_trauma() + temp.get_burn()))
					wound_flavor_text["[temp.name]"] = "[p_They()] [p_have()] a [temp.name]."
				else
					wound_flavor_text["[temp.name]"] = span_warning("[p_They()] [p_have()] a [temp.name] with [temp.get_wounds_desc()]!")
				continue
			else if(length(temp.get_wounds()) || temp.open)
				if(temp.is_stump() && temp.parent_organ && organs_by_name[temp.parent_organ])
					var/obj/item/organ/external/parent = organs_by_name[temp.parent_organ]
					wound_flavor_text["[temp.name]"] = span_warning("[p_They()] [p_have()] [temp.get_wounds_desc()] on [p_their()] [parent.name].")
				else
					wound_flavor_text["[temp.name]"] = span_warning("[p_They()] [p_have()] [temp.get_wounds_desc()] on [p_their()] [temp.name].")
			else
				wound_flavor_text["[temp.name]"] = ""
			if(temp.dislocated == 1)
				wound_flavor_text["[temp.name]"] += span_warning("[p_Their()] [temp.joint] is dislocated!")
			if(temp.get_trauma() > temp.min_broken_damage || (temp.status & (ORGAN_BROKEN | ORGAN_MUTATED)))
				wound_flavor_text["[temp.name]"] += span_warning("[p_Their()] [temp.name] is dented and swollen!")

			if(temp.germ_level > INFECTION_LEVEL_TWO && !(temp.status & ORGAN_DEAD))
				wound_flavor_text["[temp.name]"] += span_warning("[p_Their()] [temp.name] looks very infected!")
			else if(temp.status & ORGAN_DEAD)
				wound_flavor_text["[temp.name]"] += span_warning("[p_Their()] [temp.name] looks rotten!")

			if(temp.status & ORGAN_BLEEDING)
				is_bleeding["[temp.name]"] += span_danger("[p_Their()] [temp.name] is bleeding!")

			if(temp.applied_pressure == src)
				applying_pressure = span_info("[p_They()] is applying pressure to [p_their()] [temp.name].")

	for(var/limb in wound_flavor_text)
		var/flavor = wound_flavor_text[limb]
		if(flavor)
			msg += flavor
	for(var/limb in is_bleeding)
		var/blood = is_bleeding[limb]
		if(blood)
			msg += blood
	for(var/implant in get_visible_implants(0))
		msg += span_danger("[src] [user.p_have()] \a [implant] sticking out of [p_their()] flesh!")
	if(digitalcamo)
		msg += "[p_Theyre()] repulsively uncanny!"

	// What the naked eye sees: the glance diagnosis profile (bleeding,
	// pallor, blue lips, laboured breathing). Patient-only sensations
	// (pain, dizziness) stay hidden.
	var/datum/diagnosis/glance = diagnose(/datum/diagnostic_profile/glance)
	for(var/line in glance?.examine_lines())
		msg += span_warning(line)
	qdel(glance)

	if(hasHUD(user,"security"))
		var/perpname = name
		var/criminal = "None"

		if(get_equipped_item(SLOT_ID_ID))
			if(istype(get_equipped_item(SLOT_ID_ID), /obj/item/card/id))
				var/obj/item/card/id/I = get_equipped_item(SLOT_ID_ID)
				perpname = I.registered_name
			else if(istype(get_equipped_item(SLOT_ID_ID), /obj/item/pda))
				var/obj/item/pda/P = get_equipped_item(SLOT_ID_ID)
				perpname = P.owner

		for (var/datum/data/record/R in GLOB.data_core.security)
			if(R.fields["name"] == perpname)
				criminal = R.fields["criminal"]

		msg += "Criminal status: <a href='byond://?src=\ref[src];criminal=1'>\[[criminal]\]</a>"
		msg += "Security records: <a href='byond://?src=\ref[src];secrecord=`'>\[View\]</a>  <a href='byond://?src=\ref[src];secrecordadd=`'>\[Add comment\]</a>"

	if(hasHUD(user,"medical"))
		var/perpname = name
		var/medical = "None"

		if(get_equipped_item(SLOT_ID_ID))
			if(istype(get_equipped_item(SLOT_ID_ID), /obj/item/card/id))
				var/obj/item/card/id/I = get_equipped_item(SLOT_ID_ID)
				perpname = I.registered_name
			else if(istype(get_equipped_item(SLOT_ID_ID), /obj/item/pda))
				var/obj/item/pda/P = get_equipped_item(SLOT_ID_ID)
				perpname = P.owner

		for (var/datum/data/record/R in GLOB.data_core.medical)
			if (R.fields["name"] == perpname)
				medical = R.fields["p_stat"]

		msg += "Physical status: <a href='byond://?src=\ref[src];medical=1'>\[[medical]\]</a>"
		msg += "Medical records: <a href='byond://?src=\ref[src];medrecord=`'>\[View\]</a> <a href='byond://?src=\ref[src];medrecordadd=`'>\[Add comment\]</a>"

	if(hasHUD(user,"best"))
		msg += "Employment records: <a href='byond://?src=\ref[src];emprecord=`'>\[View\]</a> <a href='byond://?src=\ref[src];emprecordadd=`'>\[Add comment\]</a>"


	var/flavor_text = print_flavor_text()
	if(flavor_text)
		flavor_text = replacetext(flavor_text, "||", "")
		msg += "[flavor_text]"

	if(custom_link)
		msg += "Custom link: " + span_linkify("[custom_link]")

	if(identity.ooc_notes)
		msg += "OOC Notes: <a href='byond://?src=\ref[src];ooc_notes=1'>\[View\]</a> - <a href='byond://?src=\ref[src];print_ooc_notes_chat=1'>\[Print\]</a>"
	msg += "<a href='byond://?src=\ref[src];vore_prefs=1'>\[Mechanical Vore Preferences\]</a>"
	msg = list(span_info(jointext(msg, "<br>")))
	if(applying_pressure)
		msg += applying_pressure

	if(pose)
		if(!findtext(pose, regex("\[.?!]$"))) // Will be zero if the last character is not a member of [.?!]
			pose = addtext(pose,".") //Makes sure all emotes end with a period.
		msg += "<br>[p_They()] [pose]" //<br> intentional, extra gap.

	return msg

//Helper procedure. Called by /mob/living/carbon/human/examine() and /mob/living/carbon/human/Topic() to determine HUD access to security and medical records.
/proc/hasHUD(mob/M as mob, hudtype)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(hasHUD_vr(H,hudtype)) return 1 //Added records access for certain modes of omni-hud glasses
		switch(hudtype)
			if("security")
				return istype(H.get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses/hud/security) || istype(H.get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses/sunglasses/sechud)
			if("medical")
				return istype(H.get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses/hud/health)
	else if(isrobot(M))
		var/mob/living/silicon/robot/R = M
		return R.sensor_type //Borgo sensors are now binary so just have them on or off


/mob/living/carbon/human/proc/examine_weight()
	if(!show_pudge() || !weight_message_visible) //Some clothing or equipment can hide this.
		return ""
	var/message = ""
	var/weight_examine = round(weight)
	switch(weight_examine)
		if(0 to 74)
			message = weight_messages[1]
		if(75 to 99)
			message = weight_messages[2]
		if(100 to 124)
			message = weight_messages[3]
		if(125 to 174)
			message = weight_messages[4]
		if(175 to 224)
			message = weight_messages[5]
		if(225 to 274)
			message = weight_messages[6]
		if(275 to 325)
			message = weight_messages[7]
		if(325 to 374)
			message = weight_messages[8]
		if(375 to 474)
			message = weight_messages[9]
		else
			message = weight_messages[10]
	if(message)
		message = span_notice("[message]")
	return message //Credit to Aronai for helping me actually get this working!

/mob/living/carbon/human/proc/examine_nutrition()
	if(!show_pudge() || !nutrition_message_visible) //Some clothing or equipment can hide this.
		return ""
	if(nutrition_hidden) // Chomp Edit
		return ""
	var/message = ""
	var/nutrition_examine = round(nutrition)
	switch(nutrition_examine)
		if(0 to 49)
			message = nutrition_messages[1]
		if(50 to 99)
			message = nutrition_messages[2]
		if(100 to 499)
			message = nutrition_messages[3]
		if(500 to 999) // Fat.
			message = nutrition_messages[4]
		if(1000 to 1399)
			message = nutrition_messages[5]
		if(1400 to 1934) // One person fully digested.
			message = nutrition_messages[6]
		if(1935 to 3004) // Two people.
			message = nutrition_messages[7]
		if(3005 to 4074) // Three people.
			message = nutrition_messages[8]
		if(4075 to 5124) // Four people.
			message = nutrition_messages[9]
		if(5125 to INFINITY) // More.
			message = nutrition_messages[10]
	if(message)
		message = span_notice("[message]")
	return message

//For OmniHUD records access for appropriate models
/proc/hasHUD_vr(mob/living/carbon/human/H, hudtype)
	if(H.nif)
		switch(hudtype)
			if("security")
				if(H.nif.flag_check(NIF_V_AR_SECURITY,NIF_FLAGS_VISION))
					return TRUE
			if("medical")
				if(H.nif.flag_check(NIF_V_AR_MEDICAL,NIF_FLAGS_VISION))
					return TRUE

	if(istype(H.get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses/omnihud))
		var/obj/item/clothing/glasses/omnihud/omni = H.get_equipped_item(SLOT_ID_EYES)
		switch(hudtype)
			if("security")
				if(omni.mode == "sec" || omni.mode == "best")
					return TRUE
			if("medical")
				if(omni.mode == "med" || omni.mode == "best")
					return TRUE
			if("best")
				if(omni.mode == "best")
					return TRUE

	return FALSE

/mob/living/carbon/human/proc/examine_pickup_size(mob/living/H)
	var/message = ""
	if(istype(H) && (H.get_effective_size(FALSE) - src.get_effective_size(TRUE)) >= 0.50)
		message = span_blue("They are small enough that you could easily pick them up!")
	return message

/mob/living/carbon/human/proc/examine_step_size(mob/living/H)
	var/message = ""
	if(istype(H) && (H.get_effective_size(FALSE) - src.get_effective_size(TRUE)) >= 0.75)
		message = span_red("They are small enough that you could easily trample them!")
	return message

/mob/living/carbon/human/proc/examine_nif(mob/living/carbon/human/H)
	if(nif && nif.examine_msg) //If you have one set, anyway.
		return span_notice("[nif.examine_msg]")

/mob/living/carbon/human/proc/examine_chimera(mob/living/carbon/human/H)
	var/t_He 	= "It" //capitalised for use at the start of each line.
	var/t_his 	= "its"
	var/t_His 	= "Its"
	var/t_appear 	= "appears"
	var/t_has 	= "has"
	switch(identifying_gender) //Gender is their "real" gender. Identifying_gender is their "chosen" gender.
		if(MALE)
			t_He 	= "He"
			t_His 	= "His"
			t_his 	= "his"
		if(FEMALE)
			t_He 	= "She"
			t_His 	= "Her"
			t_his 	= "her"
		if(PLURAL)
			t_He	= "They"
			t_His 	= "Their"
			t_his 	= "their"
			t_appear 	= "appear"
			t_has 	= "have"
		if(NEUTER)
			t_He 	= "It"
			t_His 	= "Its"
			t_his 	= "its"
		if(HERM)
			t_He 	= "Shi"
			t_His 	= "Hir"
			t_his 	= "hir"
	var/datum/component/xenochimera/xc = get_xenochimera_component()
	if(xc)
		if((xc.revive_ready == REVIVING_NOW || xc.revive_ready == REVIVING_DONE))
			if(stat == DEAD)
				return span_warning("[t_His] body is twitching subtly.")
			else
				return span_notice("[t_He] [t_appear] to be in some sort of torpor.")
		else if(xc.feral)
			return span_warning("[t_He] [t_has] a crazed, wild look in [t_his] eyes!")

/mob/living/carbon/human/proc/examine_body_writing(list/hidden)
	. = list()

	for(var/bodypart in hidden)
		var/is_hidden = hidden[bodypart]
		if(is_hidden)
			continue

		var/writing = LAZYACCESS(body_writing, bodypart)
		if(writing)
			var/obj/item/organ/external/affecting = get_organ(bodypart)
			if(!affecting || affecting.is_stump())
				LAZYREMOVE(body_writing, bodypart)
				continue

			. += span_notice("[p_They()] [p_have()] \"[writing]\" written on [p_their()] [parse_zone(bodypart)].")
