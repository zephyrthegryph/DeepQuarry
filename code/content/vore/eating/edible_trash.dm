/// Whether `O` is edible trash to the vore eating rules: one of the types in GLOB.edible_trash, or a burnt out circuit board (a row of the
/// circuit board family, which is a variant of a type and not a type of its own).
/proc/edible_trash_item(atom/O)
	return is_type_in_list(O, GLOB.edible_trash) || variant_is(O, VARIANT(/obj/item/circuitboard/broken))
