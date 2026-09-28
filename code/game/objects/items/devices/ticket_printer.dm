/obj/item/ticket_printer
	name = "ticket printer"
	desc = "It prints security citations!"
	icon = 'icons/obj/device.dmi'
	icon_state = "sec_ticket_printer"
	slot_flags = SLOT_BELT | SLOT_HOLSTER
	var/print_cooldown = 1 MINUTE
	COOLDOWN_DECLARE(print_cooldown_until)
	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'
	w_class = ITEMSIZE_SMALL //because something so small, trivial, and used for silly RP should not be practically gigantic.

DECLARE_INTERACTIONS(/obj/item/ticket_printer, INTERACT_USE(null, PROC_REF(interaction_self)))

/obj/item/ticket_printer/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(COOLDOWN_FINISHED(src, print_cooldown_until))
		print_a_ticket(user)
	else
		to_chat(user, span_warning("\The [src] is not ready to print another ticket yet."))

/obj/item/ticket_printer/proc/print_a_ticket(mob/user)
	om_ask(user, /datum/om/prompt/text, PROC_REF(ticket_named), title = "Name", message = "The Name of the person you are issuing the ticket to.", max_length = 100, ask_flags = ASK_CARRIED | ASK_CAPABLE)

/// What the ticket is for, carrying the name already given.
/datum/om/prompt/text/ticket_details
	title = "Ticket Details"
	message = "What is the ticket for? Avoid entering personally identifiable information in this section. This information should not be used to harrass or otherwise make the person feel uncomfortable. (Max length: 200)"
	max_length = 200
	ask_flags = ASK_CARRIED | ASK_CAPABLE
	var/ticket_name

/obj/item/ticket_printer/proc/ticket_named(datum/om/prompt/text/ask)
	if(!ask.text)
		return
	om_ask(ask.answerer, /datum/om/prompt/text/ticket_details, PROC_REF(ticket_written), ticket_name = ask.text, message = ticket_details_prompt())

/// The details question's text (the permit printer asks it differently).
/obj/item/ticket_printer/proc/ticket_details_prompt()
	return initial(/datum/om/prompt/text/ticket_details::message)

/obj/item/ticket_printer/proc/ticket_written(datum/om/prompt/text/ticket_details/ask)
	if(!ask.ticket_name || !ask.text)
		return
	print_ticket_paper(ask.answerer, ask.ticket_name, ask.text)

/obj/item/ticket_printer/proc/print_ticket_paper(mob/user, ticket_name, details)

	var/turf/our_turf = get_turf(user)

	var/final = "<head><style>body {font-family: Verdana; background-color: #C1BDA3;}</style></head><center><h3>Nanotrasen Security Citation</h3><hr>This security citation has been issued to <br><big>[capitalize(ticket_name)]</big></center><b>Reason</b>:<br><i>[details]</i><hr><center><small>See your local representative at Central Command after the shift is over to resolve this issue.</small><br><img src=\ref['html/images/ntlogo.png']></center>"

	var/obj/item/paper/sec_ticket/p = new /obj/item/paper/sec_ticket(our_turf)

	p.info = final
	p.name = "Security Citation: [ticket_name]"
	playsound(user, 'sound/items/ticket_printer.ogg', 75, 1)

	GLOB.security_printer_tickets |= details
	log_and_message_admins("has issued '[ticket_name]' a security citation: \"[details]\"", user)
	COOLDOWN_START(src, print_cooldown_until, print_cooldown)

/obj/item/paper/sec_ticket
	name = "Security Citation"
	desc = "A citation issued by security for some kind of infraction!"
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "sec_ticket"

/obj/item/paper/sec_ticket/Initialize(mapload, text, title)
	. = ..()
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "sec_ticket"

/obj/item/paper/sec_ticket/update_icon()
		icon = icon
		icon_state = icon_state


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

	p.info = final
	p.name = "Permit Ticket: [ticket_name]"
	playsound(user, 'sound/items/ticket_printer.ogg', 75, 1)

	log_and_message_admins("has issued '[ticket_name]' a permit ticket: \"[details]\"", user)
	COOLDOWN_START(src, print_cooldown_until, print_cooldown)

/obj/item/paper/permit_ticket
	name = "Permit Ticket"
	desc = "A ticket issued to permit someone to do something!"
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "permit_ticket"

/obj/item/paper/permit_ticket/Initialize(mapload, text, title)
	. = ..()
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "permit_ticket"

/obj/item/paper/permit_ticket/update_icon()
		icon = icon
		icon_state = icon_state
