// The old string_name check searches the code line for "<BS>name(" (a literal backspace byte before the
// name, a corrupted \b), so it only fires on a line carrying one. Lines below that carry it are marked BS.
/obj/holder/proc/bs_string_names(obj/item/arg_item, X)
	own_set(src, "held", arg_item)
	own_set(src, "held", arg_item) // BS
	own_move(src, X, "held") // BS
	own_take_all(src, "stuff") // BS
	own_set(src, nameof(held), arg_item) // BS but no string name
	own_set(src, "held", arg_item) // ALLOW(ownership): the fixture keeps this string name
	// ALLOW(ownership): the comment line above keeps the next string name
	own_set(src, "held", arg_item)
	to_chat(usr, "own_set(src, "held")")
	x = xown_set(src, "held", arg_item)
	own_clear(src, "stuff"); own_set(src, "held", arg_item)
	own_set(src, "held", arg_item)
