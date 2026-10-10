/obj/item/ticket_printer
	name = "ticket printer"
	desc = "It prints security citations!"
	icon = 'icons/obj/device.dmi'
	icon_state = "sec_ticket_printer"
	slot_flags = SLOT_BELT | SLOT_HOLSTER
	var/print_cooldown = 1 MINUTE
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE
	w_class = ITEMSIZE_SMALL //because something so small, trivial, and used for silly RP should not be practically gigantic.

CAPABILITIES(/obj/item/ticket_printer)
	op("print", in_hand(), label("Print ticket"), cooldown(print_cooldown), needs(carried()),
		asks(/datum/prompt/text, keeps = 0, step = "recipient", fields = list("timeout" = 0, "title" = "Name", "question" = "The Name of the person you are issuing the ticket to.", "max_len" = 100)),
		asks(/datum/prompt/text/ticket_printer_details, fields = list("timeout" = 0), keeps = 0, step = "details", when = PROC_REF(has_recipient)),
		then(PROC_REF(ticket_printed)))

/obj/item/ticket_printer/proc/has_recipient(datum/act/op/A)
	var/datum/prompt/text/recipient = A.step_answer("recipient")
	return !!recipient?.value

/datum/prompt/text/ticket_printer_details
	title = "Ticket Details"
	max_len = 200

/datum/prompt/text/ticket_printer_details/prepare(datum/act/A)
	. = ..()
	if(istype(A, /datum/act/op))
		var/datum/act/op/asking = A
		var/obj/item/ticket_printer/printer = asking.holder // ALLOW(check_grep): the operation holder is the printer providing its ticket question, not an admin credential
		if(istype(printer))
			question = printer.ticket_details_prompt()

/// The permit printer retains its distinct question through this existing override.
/obj/item/ticket_printer/proc/ticket_details_prompt()
	return "What is the ticket for? Avoid entering personally identifiable information in this section. This information should not be used to harrass or otherwise make the person feel uncomfortable. (Max length: 200)"

/obj/item/ticket_printer/proc/ticket_printed(datum/act/op/A)
	var/datum/prompt/text/recipient = A.step_answer("recipient")
	var/datum/prompt/text/details = A.step_answer("details")
	if(!recipient?.value || !details?.value)
		return OP_REFUSED
	print_ticket_paper(A.actor, recipient.value, details.value)
	return OP_OK

/obj/item/ticket_printer/proc/print_ticket_paper(mob/user, ticket_name, details)

	var/turf/our_turf = get_turf(user)

	var/final = "<head><style>body {font-family: Verdana; background-color: #C1BDA3;}</style></head><center><h3>Nanotrasen Security Citation</h3><hr>This security citation has been issued to <br><big>[capitalize(ticket_name)]</big></center><b>Reason</b>:<br><i>[details]</i><hr><center><small>See your local representative at Central Command after the shift is over to resolve this issue.</small><br><img src=\ref['html/images/ntlogo.png']></center>"

	var/obj/item/paper/sec_ticket/p = new /obj/item/paper/sec_ticket(our_turf)

	p.set_info(final)
	p.name = "Security Citation: [ticket_name]"
	play_sfx(user, SFX_ITEMS_TICKET_PRINTER)

	GLOB.security_printer_tickets |= details
	log_and_message_admins("has issued '[ticket_name]' a security citation: \"[details]\"", user)

/obj/item/paper/sec_ticket
	name = "Security Citation"
	desc = "A citation issued by security for some kind of infraction!"
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "sec_ticket"

/// A ticket keeps the state its creation gave it.
/obj/item/paper/sec_ticket/look_parts(datum/look/look)
	return


/obj/item/ticket_printer/train
	name = "permission ticket printer"
	desc = "It prints permit tickets!"
	icon = 'icons/obj/device.dmi'
	icon_state = "train_ticket_printer"

/obj/item/ticket_printer/train/ticket_details_prompt()
	return "What is the ticket for? This could be anything like travel to a destination or permission to do something! This is not official and does not override any rules or authorities on the station."

/obj/item/ticket_printer/train/print_ticket_paper(mob/user, ticket_name, details)

	var/turf/our_turf = get_turf(user)

	var/final = "<head><style>body {font-family: Verdana; background-color: #ffa1ef;}</style></head><center><h3>Permit Ticket</h3><hr>This ticket has been issued to <br><big>[capitalize(ticket_name)]</big></center><b>This permits them to</b>:<br><i>[details]</i><br>Issued by:<i>[user]</i><hr><center><small>This ticket is non-refundable from the time of receipt. This ticket holds the authority of the issuer only and does not hold any authority over persons nor entities that were not involved in this transaction.</small><br></center>"

	var/obj/item/paper/permit_ticket/p = new /obj/item/paper/permit_ticket(our_turf)

	p.set_info(final)
	p.name = "Permit Ticket: [ticket_name]"
	play_sfx(user, SFX_ITEMS_TICKET_PRINTER)

	log_and_message_admins("has issued '[ticket_name]' a permit ticket: \"[details]\"", user)

/obj/item/paper/permit_ticket
	name = "Permit Ticket"
	desc = "A ticket issued to permit someone to do something!"
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "permit_ticket"

/// A ticket keeps the state its creation gave it.
/obj/item/paper/permit_ticket/look_parts(datum/look/look)
	return
