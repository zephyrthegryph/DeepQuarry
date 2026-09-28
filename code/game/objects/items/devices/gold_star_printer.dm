// Base object works similar to ticket printers, but produces gold star accessories.

/obj/item/gold_star_printer
	name = "gold star dispenser"
	desc = "It prints gold stickers to reward the crew for their excellent contributions!"
	icon = 'icons/obj/device.dmi'
	icon_state = "gold_star_printer"
	slot_flags = SLOT_BELT | SLOT_HOLSTER
	var/print_cooldown = 1 MINUTE
	COOLDOWN_DECLARE(print_cooldown_until)
	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'

DECLARE_INTERACTIONS(/obj/item/gold_star_printer, INTERACT_USE(null, PROC_REF(interaction_self)))

/obj/item/gold_star_printer/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(COOLDOWN_FINISHED(src, print_cooldown_until))
		make_star(user)
	else
		to_chat(user, span_warning("\The [src] is not ready to print another star yet."))

/obj/item/gold_star_printer/proc/make_star(mob/user)

	om_prompt(src, user, list("kind" = "text", "message" = "Choose a title for the star, this can be an action or name. The name of the star will read Gold Star for 'Title'.", "title" = "Title", "max_length" = 32, "requires" = PROMPT_HELD), PROC_REF(star_titled))

/obj/item/gold_star_printer/proc/star_titled(mob/user, star_title, datum/om/prompt/ask)
	if(!star_title)
		return
	ask.put("title", star_title)
	ask.chain(list("kind" = "text", "message" = "Choose the description of the 'Gold Star for [star_title]', this is what it will read on examination. (Max length: 200)", "title" = "Ticket Details", "max_length" = 200), PROC_REF(star_described))

/obj/item/gold_star_printer/proc/star_described(mob/user, star_desc, datum/om/prompt/ask)
	var/star_title = ask.get("title")
	if(!star_desc)
		return

	var/turf/our_turf = get_turf(user)

	var/obj/item/clothing/accessory/gold_sticker/p = new /obj/item/clothing/accessory/gold_sticker(our_turf)

	p.desc = "A gold star issued by [user] for [star_title], if you look closely, the fine print reads: [star_desc]"
	p.name = "Gold Star for [star_title]"
	playsound(user, 'sound/items/ticket_printer.ogg', 75, 1)

	log_admin("[key_name(user)] has printed a Gold Star for [star_title] with the description: \"[star_desc]\"")
	COOLDOWN_START(src, print_cooldown_until, print_cooldown)

/obj/item/clothing/accessory/gold_sticker
	name = "Gold Star"
	desc = "A gold star!"
	icon_state = "gold_sticker"
	slot = ACCESSORY_SLOT_TIE

/obj/item/clothing/accessory/gold_sticker/proc/sticker_refused(mob/living/M, datum/om/prompt/ask)
	to_chat(ask.get("sticker"), span_warning("\The [M] does not allow you to stick the [src] on them."))

/obj/item/clothing/accessory/gold_sticker/proc/sticker_answered(mob/living/M, accepting, datum/om/prompt/ask)
	var/mob/user = ask.get("sticker")
	if(accepting != "Yes")
		sticker_refused(M, ask)
		return
	if(loc != user)
		return
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
			om_prompt(src, M, list("message" = "[user] is attempting to stick a [src] on you. Will you allow this?", "title" = "Sticker!", "choices" = list("No","Yes"), "target" = user, "requires" = PROMPT_ADJACENT, "on_cancel" = PROC_REF(sticker_refused), "data" = list("sticker" = user)), PROC_REF(sticker_answered))
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
	target.desc = "[target.desc] It has a [src] stuck to it!"
	target.description_fluff = "[target.description_fluff] Attached to it is [desc]"
	to_chat(user, span_notice("You stick \the [src] to \the [target]."))
	user.drop_item()
	consume(src, user)
	return
