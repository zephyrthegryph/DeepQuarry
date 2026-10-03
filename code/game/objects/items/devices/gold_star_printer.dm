// Base object works similar to ticket printers, but produces gold star accessories.

/obj/item/gold_star_printer
	name = "gold star dispenser"
	desc = "It prints gold stickers to reward the crew for their excellent contributions!"
	icon = 'icons/obj/device.dmi'
	icon_state = "gold_star_printer"
	slot_flags = SLOT_BELT | SLOT_HOLSTER
	var/print_cooldown = 1 MINUTE
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

CAPABILITIES(/obj/item/gold_star_printer)
	op("print", in_hand(), label("Print gold star"), cooldown(print_cooldown), needs(carried()),
		asks(/datum/prompt/text, keeps = 0, step = "title", fields = list("timeout" = 0, "title" = "Title", "question" = "Choose a title for the star, this can be an action or name. The name of the star will read Gold Star for 'Title'.", "max_len" = 32, "name_text" = TRUE)),
		asks(/datum/prompt/text/gold_star_description, fields = list("timeout" = 0), keeps = 0, step = "description", when = PROC_REF(has_title)),
		then(PROC_REF(star_printed)))

/obj/item/gold_star_printer/proc/has_title(datum/act/op/A)
	var/datum/prompt/text/title_answer = A.step_answer("title")
	return !!title_answer?.value

/datum/prompt/text/gold_star_description
	title = "Ticket Details"
	max_len = 200

/datum/prompt/text/gold_star_description/prepare(datum/act/A)
	. = ..()
	if(istype(A, /datum/act/op))
		var/datum/act/op/asking = A
		var/datum/prompt/text/title_answer = asking.step_answer("title")
		question = "Choose the description of the 'Gold Star for [title_answer.value]', this is what it will read on examination. (Max length: 200)"

/obj/item/gold_star_printer/proc/star_printed(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/prompt/text/title_answer = A.step_answer("title")
	var/datum/prompt/text/description_answer = A.step_answer("description")
	var/star_title = title_answer?.value
	var/star_desc = description_answer?.value
	if(!star_title || !star_desc)
		return OP_REFUSED
	var/turf/our_turf = get_turf(user)
	var/obj/item/clothing/accessory/gold_sticker/p = new /obj/item/clothing/accessory/gold_sticker(our_turf)
	p.desc = "A gold star issued by [user] for [star_title], if you look closely, the fine print reads: [star_desc]"
	p.name = "Gold Star for [star_title]"
	play_sfx(user, SFX_ITEMS_TICKET_PRINTER)
	log_admin("[key_name(user)] has printed a Gold Star for [star_title] with the description: \"[star_desc]\"")
	return OP_OK

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
