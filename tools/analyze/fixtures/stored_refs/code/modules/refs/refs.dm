// stored_refs fixture: one positive and one negative case per shape.

/obj/item/cell
/turf/floor
/datum/thing

/datum/holder
	var/obj/item/cell/cell          // declared below by owns_one: not counted
	var/datum/thing/raw_thing       // var: counted
	var/turf/floor/spot             // a turf is never deleted: not counted
	var/const/datum/thing/never = null  // const: not counted
	var/datum/thing/kept            // ALLOW(stored_refs): fixture keep with a long enough reason here
	var/datum/thing/legacy_rel      // declared in relations(): not counted
	var/list/things                 // list: filled with datums below
	var/list/numbers                // only numbers: not counted
	var/list/obj/item/cell/typed    // typed list of atoms: counted with no write
	var/list/declared_many          // ref_many: not counted
	var/list/keyed                  // a datum used as a key: counted

CAPABILITIES(/datum/holder)
	owns_one(nameof(cell), /obj/item/cell)
	ref_many(nameof(declared_many), /datum/thing)

/datum/holder/relations()
	. = list()
	. += rel_one(nameof(legacy_rel), /datum/thing)

/datum/holder/proc/fill(datum/thing/T)
	things += T
	numbers += 4
	declared_many += T
	keyed[src] = 1

/datum/holder/proc/cached(datum/thing/T)
	var/static/list/cache
	cache = list(T)
	var/list/scratch = list()
	scratch += T // a local list is scratch: not counted
	return scratch

/proc/rel_one(name, type)
	return name

/proc/owns_one(name, type)
	return name

/proc/ref_many(name, type)
	return name

/datum/proc/relations()
	return list()
