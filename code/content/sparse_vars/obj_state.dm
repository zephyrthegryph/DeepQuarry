// Rare and scratch per-instance state of objects, items and machines: sparse slots (code/engine/declare/sparse_slots.dm), nothing on the type until one is set.
// The default each slot reads as is the one the var it replaced was declared with (sparse_get_or(O, slot, default)); a write of null clears it.
// Read and write them through sparse_get() / sparse_get_or() / sparse_set(), never through a var of the same name.

// /obj

// /obj/item
sparse(/obj/item, user_vars_to_edit, type = list)
sparse(/obj/item, user_vars_remembered, type = list)
sparse(/obj/item, warned_of_possession, type = list)

// /obj/machinery

// base_vars wave 3
sparse(/obj/item, ckeys_allowed_itemspawn, type = list)
