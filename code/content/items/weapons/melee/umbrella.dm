/obj/item/melee/umbrella
	name = "umbrella"
	desc = "To keep the rain off you. Use with caution on windy days."
	icon = 'icons/obj/items.dmi'
	icon_state = "umbrella_closed"
	addblends = "umbrella_closed_a"
	w_class = ITEMSIZE_NORMAL
	var/open = FALSE


CAPABILITIES(/obj/item/melee/umbrella)
	configure(item_worn(slots = SLOT_BELT))
	configure(item_thrown(force = 5))
	configure(item_combat(force = 5))
	op("toggle", in_hand(), label("Open or close umbrella"), then(PROC_REF(umbrella_toggled)))

/// The native held-item activation preserves the complete equipment change.
/obj/item/melee/umbrella/proc/umbrella_toggled(datum/act/op/A)
	toggle_umbrella()
	return OP_OK

/obj/item/melee/umbrella/proc/toggle_umbrella()
	set_open(!open)
	set_icon_state("umbrella_[open ? "open" : "closed"]")
	set_addblends(icon_state + "_a")
	set_item_state(icon_state)

CAPABILITIES(/obj/item/melee/umbrella/random)
	rolls(nameof(color), PROC_REF(roll_color))

/// Rolled before init (rolls()): any colour (get_random_colour()'s distribution).
/obj/item/melee/umbrella/random/proc/roll_color(datum/roller/R)
	return R.hex_colour()
