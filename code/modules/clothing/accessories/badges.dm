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

CAPABILITIES(/obj/item/clothing/accessory/badge)
	op("badge_display_self", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Display"), then(PROC_REF(badge_display_self)))

/// Old attack_self: polish or display the badge. Returns FALSE where the old body returned nothing,
/// so subtypes' legacy attack_self bodies that ran after ..() still run.
/obj/item/clothing/accessory/badge/proc/badge_display_self(datum/act/op/A)
	var/mob/user = A.actor
	if(sheriff_badge)
		return OP_DECLINE
	if(fluff_badge)
		return OP_DECLINE
	if(!stored_name)
		if(holo)
			to_chat(user, "Waving around a holobadge before swiping an ID would be pretty pointless.")
			return OP_DECLINE
		else
			to_chat(user, "You polish your old badge fondly, shining up the surface.")
		set_name(user.real_name)
		return OP_DECLINE

	if(isliving(user))
		if(stored_name)
			act_message(user, null, MSG_SELF(span_notice("You display your [src.name].\nIt reads: [stored_name], [badge_string].")), \
				MSG_OTHERS(span_notice("%U% displays their [src.name].\nIt reads: [stored_name], [badge_string].")))
		else
			act_message(user, null, MSG_SELF(span_notice("You display your [src.name]. It reads: [badge_string].")), \
				MSG_OTHERS(span_notice("%U% displays their [src.name].\nIt reads: [badge_string].")))
	return OP_DECLINE

/obj/item/clothing/accessory/badge/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	act_message(user, M, MSG_SELF(span_danger("You invade %T%'s personal space, thrusting [src] into their face insistently.")), \
		MSG_OTHERS(span_danger("%U% invades %T%'s personal space, thrusting [src] into their face insistently.")))
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

	drop_sound = SFX_ITEMS_DROP_RUBBER
	pickup_sound = SFX_ITEMS_PICKUP_RUBBER

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

TRACKED(/obj/item/clothing/accessory/badge/holo, emagged)

/obj/item/clothing/accessory/badge/holo/cord
	icon_state = "holobadge-cord"
	slot_flags = SLOT_MASK | SLOT_TIE | SLOT_BELT

/obj/item/clothing/accessory/badge/holo/proc/on_emag(datum/act/op/A)
	set_emagged(TRUE)
	to_chat(A.actor, span_danger("You crack the holobadge security checks."))
	return OP_OK

CAPABILITIES(/obj/item/clothing/accessory/badge/holo)
	emag(then(PROC_REF(on_emag)), powered = FALSE)
	op("holobadge_imprint_item", item(/obj/item), needs(req(PROC_REF(imprint_credentials_holds))), then(PROC_REF(holobadge_imprint_item)))

/obj/item/clothing/accessory/badge/holo/proc/imprint_credentials_holds(datum/act/op/A)
	var/obj/item/card/id/id_card
	if(istype(A.held, /obj/item/card/id))
		id_card = A.held
	else if(istype(A.held, /obj/item/pda))
		var/obj/item/pda/pda = A.held
		id_card = pda.id
	else
		return null
	if(!id_card)
		return "The PDA has no ID card to imprint."
	for(var/access in valid_access)
		if((access in id_card.GetAccess()) || emagged)
			return null
	return "[src] rejects your insufficient access rights."

/// Old attackby: imprint ID details.
/obj/item/clothing/accessory/badge/holo/proc/holobadge_imprint_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if(istype(O, /obj/item/card/id) || istype(O, /obj/item/pda))
		to_chat(user, "You imprint your ID details onto the badge.")
		set_name(user.real_name)
		return OP_PASS
	return OP_DECLINE

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

CAPABILITIES(/obj/item/clothing/accessory/badge/sheriff)
	op("display", in_hand(), label("Flash sheriff badge"), then(PROC_REF(sheriff_badge_displayed)))

/obj/item/clothing/accessory/badge/sheriff/proc/sheriff_badge_displayed(datum/act/op/A)
	act_message(A.actor, null, MSG_SELF("You flash the sheriff badge to everyone around you!"), \
		MSG_OTHERS("%U% shows their sheriff badge. There's a new sheriff in town!"))
	return OP_OK

/obj/item/clothing/accessory/badge/sheriff/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	act_message(user, M, MSG_SELF(span_danger("You invade %T%'s personal space, thrusting the sheriff badge into their face insistently.")), \
		MSG_OTHERS(span_danger("%U% invades %T%'s personal space, the sheriff badge into their face!.")))
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

/obj/item/clothing/accessory/dosimeter
	name = "dosimeter"
	desc = "A small device used to measure body radiation and warning one after a certain threshold. \
	Read manual before use! Can be held, attached to the uniform or worn around the neck."
	w_class = ITEMSIZE_SMALL
	icon_state = "dosimeter"
	item_state = "dosimeter"
	overlay_state = "dosimeter"
	slot_flags = SLOT_TIE

/// The loaded film (set at init by its owns_one starts).
/obj/item/clothing/accessory/dosimeter/var/obj/item/dosimeter_film/current_film

CAPABILITIES(/obj/item/clothing/accessory/dosimeter)
	owns_one(nameof(current_film), /obj/item/dosimeter_film, starts = /obj/item/dosimeter_film)
	op("dosimeter_remove_film_hand", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Dosimeter remove film hand"), then(PROC_REF(dosimeter_remove_film_hand)))
	op("dosimeter_insert_film", item(/obj/item/dosimeter_film), priority(OP_PRIORITY_DEFAULT - 1), label("Insert film"), then(PROC_REF(dosimeter_insert_film)))
	every(2 SECONDS, then(PROC_REF(dosimeter_step)), when = PROC_REF(film_live))

/// A film that can still darken is loaded: it reads the wearer's radiation.
/obj/item/clothing/accessory/dosimeter/proc/film_live(datum/act/A)
	return current_film && current_film.state < 2

/obj/item/clothing/accessory/dosimeter/Initialize(mapload)
	. = ..()
	update_state(current_film.state)

/obj/item/clothing/accessory/dosimeter/proc/dosimeter_step(datum/act/timer/A)
	check_holder()

/// Old attack_hand: pull the film out while holding the dosimeter in the other hand.
/obj/item/clothing/accessory/dosimeter/proc/dosimeter_remove_film_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(user.get_inactive_hand() == src)
		if(current_film)
			user.put_in_hands(rel_take(src, nameof(current_film)))
			to_chat(user, span_notice("You pulled out the film out of \the [src]."))
			desc = "This seems like a dosimeter, but there is no film inside."
			update_state(0)
			return OP_OK
	return OP_DECLINE

/// Old attackby: insert a film.
/obj/item/clothing/accessory/dosimeter/proc/dosimeter_insert_film(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(!current_film)
		if(!move_into(src, nameof(src.current_film), I, user))
			return OP_PASS
		update_state(current_film.state)

		to_chat(user, span_notice("You inserted the film into \the [src]."))
		desc = "This seems like a dosimeter. It has a film inside."
	else
		to_chat(user, span_notice("\The [src] already has a film inside."))
	return OP_PASS

/obj/item/clothing/accessory/dosimeter/proc/check_holder()
	var/mob/living/carbon/human/H = wearer
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
	var/obj/item/dosimeter_film/film = current_film
	if(film)
		film.set_state(tostate)
		icon_state = "[initial(icon_state)][tostate]"
		current_film.icon_state = "dosimeter_film[tostate]"
	else
		icon_state = "[initial(icon_state)]-empty"

/obj/item/dosimeter_film
	name = "dosimeter film"
	desc = "These films can be inserted into dosimeters. It turns from white to black, depending on how much radiation it endured."
	w_class = ITEMSIZE_SMALL
	icon = 'icons/inventory/accessory/item.dmi'
	icon_state = "dosimeter_film0"

/// How dark the film is: 0 white, 1 darker, 2 black (same as the icon states). A dosimeter holding it
/// reads it as current_film.state.
/obj/item/dosimeter_film/var/state = 0
TRACKED(/obj/item/dosimeter_film, state)

/obj/item/dosimeter_film/proc/update_state(tostate)
	icon_state = tostate

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
	starts_with = list(
		/obj/item/paper/dosimeter_manual = 1,
		/obj/item/clothing/accessory/dosimeter = 1,
		/obj/item/dosimeter_film = 3,
	)
	name = "dosimeter case"
	desc = "This case can only hold the Dosimeter, a few films and a manual."
	icon = 'icons/inventory/accessory/item.dmi'
	icon_state = "dosimeter_case"
	item_state_slots = list(slot_r_hand_str = "syringe_kit", slot_l_hand_str = "syringe_kit")
	storage_slots = 5
	max_storage_space = (ITEMSIZE_COST_SMALL * 4) + (ITEMSIZE_COST_TINY * 1)
	w_class = ITEMSIZE_SMALL

CAPABILITIES(/obj/item/storage/box/dosimeter)
	configure(storage(accepts = list(
		/obj/item/paper/dosimeter_manual,
		/obj/item/clothing/accessory/dosimeter,
		/obj/item/dosimeter_film)))
