/datum/ledger
	var/list/slots = list()
	var/amount = 0

/datum/ledger/proc/own_slots()
	return src.slots

/obj/belly
	var/static/list/slots = list()
	var/global/list/modes = list()

/datum/holder
	var/datum/ledger/ledger
	var/loose

/proc/make_ledger() as /datum/ledger
	return new /datum/ledger()

/proc/untyped_param(x)
	return x.slots

/proc/untyped_write(x)
	x.slots = list()

/proc/untyped_local()
	var/y = new /datum/ledger()
	return y.slots

/proc/return_type_is_not_a_type()
	return make_ledger().slots

/proc/untyped_field(datum/holder/H)
	return H.loose.slots

/proc/untyped_index(list/L)
	return L[1].modes

/proc/untyped_parens(x)
	return (x).modes

/proc/untyped_loop(list/L)
	for(var/e in L)
		e.slots += 1

/proc/not_a_static_name(x)
	return x.amount

/proc/typed_local(x)
	var/datum/ledger/L = x
	return L.slots

/proc/typed_param(datum/ledger/L)
	return L.slots

/proc/typed_field(datum/holder/H)
	return H.ledger.slots

/proc/typed_new()
	return new /obj/belly().slots

/proc/typed_belly(obj/belly/B)
	return B.slots

/proc/typed_for(list/L)
	for(var/obj/belly/B in L)
		return B.modes

/proc/global_namespace()
	return global.some_global.slots

/var/datum/ledger/some_global
