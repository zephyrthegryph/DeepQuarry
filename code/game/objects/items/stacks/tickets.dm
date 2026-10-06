/obj/item/stack/arcadeticket
	name = "arcade tickets"
	desc = "Wow! With enough of these, you could buy a bike! ...Pssh, yeah right."
	singular_name = "arcade ticket"
	icon_state = "arcade-ticket"
	item_state = "tickets"
	w_class = ITEMSIZE_TINY
	max_amount = 30

/obj/item/stack/arcadeticket/Initialize(mapload)
	. = ..()

/// The pile shows how many tickets there are in steps.
/obj/item/stack/arcadeticket/look_state()
	switch(get_amount())
		if(12 to INFINITY)
			return "arcade-ticket_4"
		if(6 to 12)
			return "arcade-ticket_3"
		if(2 to 6)
			return "arcade-ticket_2"
	return "arcade-ticket"

/obj/item/stack/arcadeticket/proc/pay_tickets()
	return use(ARCADE_TICKETS_PER_PRIZE)

/obj/item/stack/arcadeticket/thirty
	amount = 30
