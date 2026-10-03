// rel_set / rel_add / rel_remove / rel_clear are the writers that replace own_*: they count as the owner's write.
/obj/relw_holder
	var/obj/item/owned_a
	var/obj/item/owned_b
	var/obj/item/mixed_ab
	var/obj/item/linked
	var/datum/reg_thing/shared_x
	var/datum/gas_mixture/gas_a
	var/obj/item/decl_rel
	var/obj/item/decl_own
	var/list/obj/item/bag

/obj/relw_holder/ownership()
	. = ..()
	. += owns(nameof(decl_own))
	. += shares(nameof(shared_x))

/obj/relw_holder/relations()
	. = ..()
	. += rel_one(nameof(decl_rel))

/obj/relw_holder/proc/own_form()
	own_set(src, nameof(owned_a), src)
	own_add(src, nameof(bag), src)

/obj/relw_holder/proc/rel_form()
	rel_set(src, nameof(owned_b), src)
	rel_add(src, nameof(bag), src)
	rel_remove(src, nameof(bag), src)
	rel_clear(src, nameof(owned_b))

/obj/relw_holder/proc/mixed()
	own_set(src, nameof(mixed_ab), src)
	rel_set(src, nameof(mixed_ab), src)

/obj/relw_holder/proc/gas()
	rel_set(src, nameof(gas_a), src)
	own_set(src, nameof(gas_a), src)

/obj/relw_holder/proc/declared()
	rel_set(src, nameof(decl_own), src)
	own_set(src, nameof(decl_own), src)
	rel_set(src, nameof(decl_rel), src)
	own_set(src, nameof(decl_rel), src)
	rel_set(src, nameof(shared_x), src)

/obj/relw_holder/proc/true_relation()
	rel_link(src, nameof(linked), src)
	own_set(src, nameof(linked), src)
