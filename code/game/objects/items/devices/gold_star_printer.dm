// Base object works similar to ticket printers, but produces gold star accessories.

/obj/item/gold_star_printer
	name = "gold star dispenser"
	desc = "It prints gold stickers to reward the crew for their excellent contributions!"
	icon = 'icons/obj/device.dmi'
	icon_state = "gold_star_printer"
	slot_flags = SLOT_BELT | SLOT_HOLSTER
	var/print_cooldown = 1 MINUTE
	COOLDOWN_DECLARE(print_cooldown_until)
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

DECLARE_INTERACTIONS(/obj/item/gold_star_printer, INTERACT_USE(null, PROC_REF(interaction_self)))

/obj/item/gold_star_printer/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(COOLDOWN_FINISHED(src, print_cooldown_until))
		make_star(user)
	else
		to_chat(user, span_warning("\The [src] is not ready to print another star yet."))

/obj/item/gold_star_printer/proc/make_star(mob/user)

	om_ask(user, /datum/om/prompt/text, PROC_REF(star_titled), title = "Title", message = "Choose a title for the star, this can be an action or name. The name of the star will read Gold Star for 'Title'.", max_length = 32, ask_flags = ASK_CARRIED | ASK_CAPABLE)

/datum/om/prompt/text/gold_star_desc
	title = "Ticket Details"
	max_length = 200
	ask_flags = ASK_CARRIED | ASK_CAPABLE
	var/star_title

/datum/om/prompt/text/gold_star_desc/prepare()
	message = "Choose the description of the 'Gold Star for [star_title]', this is what it will read on examination. (Max length: 200)"
	return TRUE

/obj/item/gold_star_printer/proc/star_titled(datum/om/prompt/text/ask)
	if(!ask.text)
		return
	om_ask(ask.answerer, /datum/om/prompt/text/gold_star_desc, PROC_REF(star_described), star_title = ask.text)

/obj/item/gold_star_printer/proc/star_described(datum/om/prompt/text/gold_star_desc/ask)
	var/mob/user = ask.answerer
	var/star_title = ask.star_title
	var/star_desc = ask.text
	if(!star_desc)
		return

	var/turf/our_turf = get_turf(user)

	var/obj/item/clothing/accessory/gold_sticker/p = new /obj/item/clothing/accessory/gold_sticker(our_turf)

	p.desc = "A gold star issued by [user] for [star_title], if you look closely, the fine print reads: [star_desc]"
	p.name = "Gold Star for [star_title]"
	play_sfx(user, SFX_ITEMS_TICKET_PRINTER)

	log_admin("[key_name(user)] has printed a Gold Star for [star_title] with the description: \"[star_desc]\"")
	COOLDOWN_START(src, print_cooldown_until, print_cooldown)

/obj/item/clothing/accessory/gold_sticker
	name = "Gold Star"
	desc = "A gold star!"
	icon_state = "gold_sticker"
	slot = ACCESSORY_SLOT_TIE

/// Asking a mob to be stuck with a sticker. Re-checked on the answer: face to face, and the
/// sticker is still the asker's. No, or a cancel, tells the asker.
/datum/om/prompt/confirm/gold_sticker
	title = "Sticker!"
	no_first = TRUE
	ask_flags = ASK_ADJACENT | ASK_CAPABLE

/datum/om/prompt/confirm/gold_sticker/prepare()
	message = "[asker] is attempting to stick a [subject] on you. Will you allow this?"
	return TRUE

/datum/om/prompt/confirm/gold_sticker/valid()
	var/obj/item/clothing/accessory/gold_sticker/S = subject
	return S.loc == asker ? null : "not holding it"

/datum/om/prompt/confirm/gold_sticker/declined()
	var/obj/item/clothing/accessory/gold_sticker/S = subject
	S?.sticker_refused(answerer, asker)

/datum/om/prompt/confirm/gold_sticker/cancelled()
	var/obj/item/clothing/accessory/gold_sticker/S = subject
	S?.sticker_refused(answerer, asker)

/obj/item/clothing/accessory/gold_sticker/proc/sticker_refused(mob/living/M, mob/user)
	to_chat(user, span_warning("\The [M] does not allow you to stick the [src] on them."))

/obj/item/clothing/accessory/gold_sticker/proc/sticker_answered(datum/om/prompt/confirm/gold_sticker/ask)
	var/mob/living/M = ask.answerer
	var/mob/user = ask.asker
	apply_sticker(M,user)
	to_chat(M, span_notice("\The [user] stuck \the [src] to you!"))

/obj/item/clothing/accessory/gold_sticker/afterattack(atom/target, mob/user)
	if(!user)
		return
	if(!user.Adjacent(target))
		return
	if(isobj(target) && !istype(target,/obj/item/clothing/under))
		var/obj/O = target
		apply_sticker(O,user)
		return
	if(isanimal(target) || issilicon(target))
		var/mob/living/M = target
		if(M.client)
			om_ask(M, /datum/om/prompt/confirm/gold_sticker, PROC_REF(sticker_answered), asker = user)
			return
		else
			apply_sticker(M,user)
			return
	. = ..()

/obj/item/clothing/accessory/gold_sticker/proc/apply_sticker(atom/target, mob/user)
	if(!user)
		return
	if(!user.Adjacent(target))
		return
	if(user.get_active_hand() != src)
		to_chat(user, span_warning("You need to have \the [src] in your active hand to apply it to something."))
		return
	var/sticker_name = "[src]"
	var/sticker_article = "\the [src]"
	var/sticker_desc = desc
	if(!consume(src, user))
		return
	target.desc = "[target.desc] It has a [sticker_name] stuck to it!"
	target.description_fluff = "[target.description_fluff] Attached to it is [sticker_desc]"
	to_chat(user, span_notice("You stick [sticker_article] to \the [target]."))
	return
