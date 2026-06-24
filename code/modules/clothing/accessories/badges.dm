/*
	Badges are worn on the belt or neck, and can be used to show that the holder is an authorized
	Security agent - the user details can be imprinted on holobadges with a Security-access ID card,
	or they can be emagged to accept any ID for use in disguises.
*/

/obj/item/clothing/accessory/badge
	name = "detective's badge"
	desc = "A corporate security badge, made from gold and set on false leather."
	icon_state = "marshalbadge"
	slot_flags = SLOT_BELT | SLOT_TIE
	slot = ACCESSORY_SLOT_MEDAL

	var/stored_name
	var/badge_string = "Corporate Security"
	special_handling = TRUE
	///var for attack_self chain
	var/sheriff_badge = FALSE
	///Another var for attack_self chain
	var/fluff_badge = FALSE
	var/holo = FALSE

/obj/item/clothing/accessory/badge/proc/set_name(new_name)
	stored_name = new_name
	name = "[initial(name)] ([stored_name])"

/obj/item/clothing/accessory/badge/proc/set_desc(mob/living/carbon/human/H)

/obj/item/clothing/accessory/badge/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	if(sheriff_badge)
		return FALSE
	if(fluff_badge)
		return FALSE
	if(!stored_name)
		if(holo)
			to_chat(user, "Waving around a holobadge before swiping an ID would be pretty pointless.")
			return
		else
			to_chat(user, "You polish your old badge fondly, shining up the surface.")
		set_name(user.real_name)
		return

	if(isliving(user))
		if(stored_name)
			user.visible_message(span_notice("[user] displays their [src.name].\nIt reads: [stored_name], [badge_string]."),span_notice("You display your [src.name].\nIt reads: [stored_name], [badge_string]."))
		else
			user.visible_message(span_notice("[user] displays their [src.name].\nIt reads: [badge_string]."),span_notice("You display your [src.name]. It reads: [badge_string]."))

/obj/item/clothing/accessory/badge/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	user.visible_message(span_danger("[user] invades [M]'s personal space, thrusting [src] into their face insistently."),span_danger("You invade [M]'s personal space, thrusting [src] into their face insistently."))
	user.do_attack_animation(M)
	user.setClickCooldown(DEFAULT_QUICK_COOLDOWN) //NO SPAM
	return ITEM_INTERACT_SUCCESS

// General Badges
/obj/item/clothing/accessory/badge/old
	name = "faded badge"
	desc = "A faded badge, backed with leather."
	icon_state = "badge_round"

/obj/item/clothing/accessory/badge/idbadge/nt
	name = "\improper NT ID badge"
	desc = "A descriptive identification badge with the holder's credentials. This one has red marks with the NanoTrasen logo on it."
	icon_state = "ntbadge"
	badge_string = null

/obj/item/clothing/accessory/badge/press
	name = "corporate press pass"
	desc = "A corporate reporter's pass, emblazoned with the NanoTrasen logo."
	icon_state = "pressbadge"
	item_state = "pbadge"
	badge_string = "Corporate Reporter"
	w_class = ITEMSIZE_TINY

	drop_sound = 'sound/items/drop/rubber.ogg'
	pickup_sound = 'sound/items/pickup/rubber.ogg'

/obj/item/clothing/accessory/badge/press/independent
	name = "press pass"
	desc = "A freelance journalist's pass."
	icon_state = "pressbadge-i"
	badge_string = "Freelance Journalist"

/obj/item/clothing/accessory/badge/press/plastic
	name = "plastic press pass"
	desc = "A journalist's 'pass' shaped, for whatever reason, like a security badge. It is made of plastic."
	icon_state = "pbadge"
	badge_string = "Sicurity Journelist"
	w_class = ITEMSIZE_SMALL

// Holobadges
/obj/item/clothing/accessory/badge/holo
	name = "holobadge"
	desc = "This glowing blue badge marks the holder as THE LAW."
	icon_state = "holobadge"
	var/emagged //Emagging removes Sec check.
	var/valid_access = list(ACCESS_SECURITY) //Default access is security, to be overriden or expanded as desired
	holo = TRUE

/obj/item/clothing/accessory/badge/holo/cord
	icon_state = "holobadge-cord"
	slot_flags = SLOT_MASK | SLOT_TIE | SLOT_BELT

/obj/item/clothing/accessory/badge/holo/emag_act(remaining_charges, mob/user)
	if (emagged)
		to_chat(user, span_danger("\The [src] is already cracked."))
		return
	else
		emagged = 1
		to_chat(user, span_danger("You crack the holobadge security checks."))
		return 1

/obj/item/clothing/accessory/badge/holo/attackby(obj/item/O as obj, mob/user as mob)
	if(istype(O, /obj/item/card/id) || istype(O, /obj/item/pda))

		var/obj/item/card/id/id_card = null

		if(istype(O, /obj/item/card/id))
			id_card = O
		else
			var/obj/item/pda/pda = O
			id_card = pda.id

		var/found = FALSE
		for(var/access in valid_access)
			if((access in id_card.GetAccess()) || emagged)
				to_chat(user, "You imprint your ID details onto the badge.")
				set_name(user.real_name)
				found = TRUE
				break
		if(!found)
			to_chat(user, "[src] rejects your insufficient access rights.")
		return
	..()

/obj/item/storage/box/holobadge
	name = "holobadge box"
	desc = "A box claiming to contain holobadges."
	starts_with = list(
		/obj/item/clothing/accessory/badge/holo/officer = 2,
		/obj/item/clothing/accessory/badge/holo = 2,
		/obj/item/clothing/accessory/badge/holo/cord = 2
	)

/obj/item/clothing/accessory/badge/holo/officer
	name = "officer's badge"
	desc = "A bronze corporate security badge. Stamped with the words '" + JOB_SECURITY_OFFICER + ".'"
	icon_state = "bronzebadge"
	slot_flags = SLOT_TIE | SLOT_BELT

/obj/item/clothing/accessory/badge/holo/warden
	name = "warden's holobadge"
	desc = "A silver corporate security badge. Stamped with the words '" + JOB_WARDEN + ".'"
	icon_state = "silverbadge"
	slot_flags = SLOT_TIE | SLOT_BELT

/obj/item/clothing/accessory/badge/holo/hos
	name = "head of security's holobadge"
	desc = "An immaculately polished gold security badge. Stamped with the words '" + JOB_HEAD_OF_SECURITY + ".'"
	icon_state = "goldbadge"
	slot_flags = SLOT_TIE | SLOT_BELT

/obj/item/clothing/accessory/badge/holo/detective
	name = "detective's holobadge"
	desc = "An immaculately polished gold security badge on leather. Labeled '" + JOB_DETECTIVE + ".'"
	icon_state = "marshalbadge"
	slot_flags = SLOT_TIE | SLOT_BELT

/obj/item/clothing/accessory/badge/holo/investigator
	name = "\improper investigator holobadge"
	desc = "This badge marks the holder as an investigative agent."
	icon_state = "invbadge"
	badge_string = "Corporate Investigator"
	valid_access = list(ACCESS_SECURITY, ACCESS_LAWYER)	//Permitting both sec and IAA!
	slot_flags = SLOT_TIE | SLOT_BELT

/obj/item/clothing/accessory/badge/holo/sheriff
	name = "sheriff badge"
	desc = "A star-shaped brass badge denoting who the law is around these parts."
	icon_state = "sheriff"
	slot_flags = SLOT_TIE | SLOT_BELT

/obj/item/storage/box/holobadge/hos
	name = "holobadge box"
	desc = "A box claiming to contain holobadges."
	starts_with = list(
		/obj/item/clothing/accessory/badge/holo/officer = 2,
		/obj/item/clothing/accessory/badge/holo/warden = 1,
		/obj/item/clothing/accessory/badge/holo/detective = 2,
		/obj/item/clothing/accessory/badge/holo/hos = 1,
		/obj/item/clothing/accessory/badge/holo/cord = 1
	)

// Sheriff Badge (toy)
/obj/item/clothing/accessory/badge/sheriff
	name = "sheriff badge"
	desc = "This town ain't big enough for the two of us, pardner."
	icon_state = "sheriff_toy"
	item_state = "sheriff_toy"
	special_handling = TRUE
	sheriff_badge = TRUE

/obj/item/clothing/accessory/badge/sheriff/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	user.visible_message("[user] shows their sheriff badge. There's a new sheriff in town!",\
		"You flash the sheriff badge to everyone around you!")

/obj/item/clothing/accessory/badge/sheriff/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	user.visible_message(span_danger("[user] invades [M]'s personal space, the sheriff badge into their face!."),span_danger("You invade [M]'s personal space, thrusting the sheriff badge into their face insistently."))
	user.do_attack_animation(M)
	user.setClickCooldown(DEFAULT_QUICK_COOLDOWN) //NO SPAM
	return ITEM_INTERACT_SUCCESS

// Synthmorph bag / Corporation badges. Primarily used on the robobag, but can be worn. Default is NT.
/obj/item/clothing/accessory/badge/corporate_tag
	name = "NanoTrasen Badge"
	desc = "A plain metallic plate that might denote the wearer as a member of NanoTrasen."
	icon_state = "tag_nt"
	item_state = "badge"
	badge_string = "NanoTrasen"

/obj/item/clothing/accessory/badge/corporate_tag/morpheus
	name = "Morpheus Badge"
	desc = "A plain metallic plate that might denote the wearer as a member of Morpheus Cyberkinetics."
	icon_state = "tag_blank"
	badge_string = "Morpheus"

/obj/item/clothing/accessory/badge/corporate_tag/wardtaka
	name = "Ward-Takahashi Badge"
	desc = "A plain metallic plate that might denote the wearer as a member of Ward-Takahashi."
	icon_state = "tag_ward"
	badge_string = "Ward-Takahashi"

/obj/item/clothing/accessory/badge/corporate_tag/zenghu
	name = "Zeng-Hu Badge"
	desc = "A plain metallic plate that might denote the wearer as a member of Zeng-Hu."
	icon_state = "tag_zeng"
	badge_string = "Zeng-Hu"

/obj/item/clothing/accessory/badge/corporate_tag/gilthari
	name = "Gilthari Badge"
	desc = "An opulent metallic plate that might denote the wearer as a member of Gilthari."
	icon_state = "tag_gil"
	badge_string = "Gilthari"

/obj/item/clothing/accessory/badge/corporate_tag/veymed
	name = "Vey-Medical Badge"
	desc = "A plain metallic plate that might denote the wearer as a member of Vey-Medical."
	icon_state = "tag_vey"
	badge_string = "Vey-Medical"

/obj/item/clothing/accessory/badge/corporate_tag/hephaestus
	name = "Hephaestus Badge"
	desc = "A rugged metallic plate that might denote the wearer as a member of Hephaestus."
	icon_state = "tag_heph"
	badge_string = "Hephaestus"

/obj/item/clothing/accessory/badge/corporate_tag/grayson
	name = "Grayson Badge"
	desc = "A rugged metallic plate that might denote the wearer as a member of Grayson."
	icon_state = "tag_grayson"
	badge_string = "Grayson"

/obj/item/clothing/accessory/badge/corporate_tag/xion
	name = "Xion Badge"
	desc = "A rugged metallic plate that might denote the wearer as a member of Xion."
	icon_state = "tag_xion"
	badge_string = "Xion"

/obj/item/clothing/accessory/badge/corporate_tag/bishop
	name = "Bishop Badge"
	desc = "A sleek metallic plate that might denote the wearer as a member of Bishop."
	icon_state = "tag_bishop"
	badge_string = "Bishop"


// === merged from badges_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/clothing/accessory/dosimeter
	name = "dosimeter"
	desc = "A small device used to measure body radiation and warning one after a certain threshold. \
	Read manual before use! Can be held, attached to the uniform or worn around the neck."
	w_class = ITEMSIZE_SMALL
	icon_state = "dosimeter"
	item_state = "dosimeter"
	overlay_state = "dosimeter"
	slot_flags = SLOT_TIE
	var/obj/item/dosimeter_film/current_film = null

/obj/item/clothing/accessory/dosimeter/Initialize(mapload)
	. = ..()
	current_film = new /obj/item/dosimeter_film(src)
	update_state(current_film.state)
	START_PROCESSING(SSobj, src)

/obj/item/clothing/accessory/dosimeter/Destroy()
	STOP_PROCESSING(SSobj, src)
	QDEL_NULL(current_film)
	return ..()

/obj/item/clothing/accessory/dosimeter/process()
	check_holder()
	if(current_film.state > 1)
		STOP_PROCESSING(SSobj, src)

/obj/item/clothing/accessory/dosimeter/attack_hand(mob/user as mob)
	if(user.get_inactive_hand() == src)
		if(current_film)
			user.put_in_hands(current_film)
			current_film = null
			to_chat(user, span_notice("You pulled out the film out of \the [src]."))
			desc = "This seems like a dosimeter, but there is no film inside."
			STOP_PROCESSING(SSobj, src)
			update_state(0)
			return
		..()
	else
		return ..()

/obj/item/clothing/accessory/dosimeter/attackby(obj/item/I, mob/user)
	if(istype(I, /obj/item/dosimeter_film))
		if(!current_film)
			user.drop_item()
			I.loc = src
			current_film = I
			update_state(current_film.state)

			to_chat(user, span_notice("You inserted the film into \the [src]."))
			desc = "This seems like a dosimeter. It has a film inside."

			if(current_film.state < 2)
				START_PROCESSING(SSobj, src)
		else
			to_chat(user, span_notice("\The [src] already has a film inside."))
	else
		return ..()

/obj/item/clothing/accessory/dosimeter/proc/check_holder()
	var/mob/living/carbon/human/H = wearer?.resolve()
	if(H)
		if(current_film && (H.radiation >= 25) && (current_film.state == 0))
			update_state(1)
			visible_message(span_warning("The film of \the [src] starts to darken."))
			desc = "This seems like a dosimeter, but the film has darkened."
		else if(current_film && (H.radiation >= 50) && (current_film.state == 1))
			visible_message(span_warning("The film of \the [src] has turned black!"))
			update_state(2)
			desc = "This seems like a dosimeter, but the film has turned black."

/obj/item/clothing/accessory/dosimeter/proc/update_state(tostate)
	if(current_film)
		current_film.state = tostate
		icon_state = "[initial(icon_state)][tostate]"
		current_film.icon_state = "dosimeter_film[tostate]"
	else
		icon_state = "[initial(icon_state)]-empty"
	update_icon()

/obj/item/dosimeter_film
	name = "dosimeter film"
	desc = "These films can be inserted into dosimeters. It turns from white to black, depending on how much radiation it endured."
	w_class = ITEMSIZE_SMALL
	icon = 'icons/inventory/accessory/item.dmi'
	icon_state = "dosimeter_film0"
	var/state = 0 //0 - White, 1 - Darker, 2 - Black (same as iconstates)

/obj/item/dosimeter_film/proc/update_state(tostate)
	icon_state = tostate
	update_icon()

/obj/item/paper/dosimeter_manual
	name = "Dosimeter manual"
	info = {"<h4>Dosimeter</h4>
	<h5>Usage</h5>
	<ol>
		<li>Insert film into dosimeter.</li>
		<li>Attach dosimeter to clothing or carry it.</li>
		<li>Replace film if current film turned black.</li>
	</ol>
	<br />
	<h5>Purpose</h5>
	<p>This device will let you know about any dangerous radiation levels, that your body is exposed to.
	A white film indicates that everything is alright. A darker film indicates, that the radiation level is starting to get dangerous for your body.
	The body has absorbed too much radiation if the film turned black.</p>"}

/obj/item/storage/box/dosimeter
	name = "dosimeter case"
	desc = "This case can only hold the Dosimeter, a few films and a manual."
	icon = 'icons/inventory/accessory/item.dmi'
	icon_state = "dosimeter_case"
	item_state_slots = list(slot_r_hand_str = "syringe_kit", slot_l_hand_str = "syringe_kit")
	storage_slots = 5
	can_hold = list(/obj/item/paper/dosimeter_manual, /obj/item/clothing/accessory/dosimeter, /obj/item/dosimeter_film)
	max_storage_space = (ITEMSIZE_COST_SMALL * 4) + (ITEMSIZE_COST_TINY * 1)
	w_class = ITEMSIZE_SMALL

/obj/item/storage/box/dosimeter/Initialize(mapload)
	. = ..()
	new /obj/item/paper/dosimeter_manual(src)
	new /obj/item/clothing/accessory/dosimeter(src)
	new /obj/item/dosimeter_film(src)
	new /obj/item/dosimeter_film(src)
	new /obj/item/dosimeter_film(src)
