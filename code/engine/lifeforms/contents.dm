// OWNER in starts_args and make_args(), initial_contents(type, slot =, count =) for initial contents, owns_many(..., count =) and knows(LANGUAGE)
// (doc/rewrite/final_api.html section 6 "Lifecycle forms", form 6).
//
//	CAPABILITIES(/obj/item/storage/box/syringes)
//		initial_contents(/obj/item/reagent_containers/syringe, count = 7)
//	CAPABILITIES(/obj/item/clothing/suit/storage/vest/heavy)
//		initial_contents(/obj/item/clothing/accessory/armor, slot = SLOT_ACCESSORIES, when = nameof(starts_armored))
//	CAPABILITIES(/obj/item/implanter/loyalty)
//		owns_one(nameof(imp), starts = /obj/item/implant/loyalty, starts_args = list(OWNER))      // new /obj/item/implant/loyalty(loc, src)
//		owns_many(nameof(spares), /obj/item/cell, count = 2, starts = /obj/item/cell/high)
//	CAPABILITIES(/mob/living/carbon/alien/diona)
//		knows(LANGUAGE_ROOTGLOBAL)
//		knows(LANGUAGE_GALCOM)
//
// initial_contents() replaces an Initialize() that only did `new /T(src)`: the contents are made when the holder initializes (after its capabilities,
// so a storage slot exists), in nullspace, then moved into `slot` (a declared slot id) or plainly into the holder. `count` makes several; `args`
// are constructor arguments (OWNER is the holder); `when =` gates it on a condition read at init. What it makes rolls from the holder's stream
// (rolls.dm). knows(LANGUAGE) gives a mob a language when it initializes (add_language()).
//
// Rolled contents (init-objects lane). `type` may also be nameof(type_var), a var holding the type (`initial_contents(nameof(case_type))`); a
// pick_one(list), uniform or weighted by an associative list's values; or PROC_REF(x), a holder proc x(datum/roller/R) answering a type, a
// list of types, an associative list of type = count, or instances it made in nullspace (null makes nothing). `chance = p` makes the line at
// all only with p percent. Every draw comes from the holder's own stream (rolls.dm), so a closet's random scrubs or a kit's bundle are seeded
// like any roll:
//
//	CAPABILITIES(/obj/structure/closet/secure_closet/medical3)
//		initial_contents(pick_one(list(/obj/item/storage/backpack/medic, /obj/item/storage/backpack/satchel/med)))
//		initial_contents(/obj/item/storage/backpack/dufflebag/med, chance = 50)
//		initial_contents(PROC_REF(roll_scrubs))
//
// OWNER is a placeholder for the instance that does the creating: in starts_args, initial_contents(args =) and make_args() it becomes the holder; in
// a make(..., x = OWNER) call it becomes `by =`.

/proc/initial_contents(type, slot = null, count = 1, when = null, args = null, chance = null)
	if(!ispath(type) && !istext(type) && !(istype(type, /datum/entry) && type:kind == "pick_one"))
		declare_report("initial_contents(): the first argument is a type, a pick_one() or a PROC_REF, got [type]")
		return null
	return entry_make(ENTRY_CONTAINS, null, list("type" = type, "slot" = slot, "count" = count, "when" = when, "args" = args, "chance" = chance))

/// What one initial_contents() line makes on `holder`: type -> count, or an instance a roll proc made (rolled lines draw from the holder's stream).
/proc/contains_roll(datum/holder, datum/entry/E)
	var/type = E.args["type"]
	var/count = E.args["count"]
	if(istext(count))
		count = (count in holder.vars) ? holder.vars[count] : call(holder, count)()
	if(!isnull(E.args["chance"]) && !roller_of(holder).chance(E.args["chance"]))
		return null
	if(ispath(type))
		. = list()
		.[type] = count
		return
	var/rolled
	if(istext(type) && (type in holder.vars))
		rolled = holder.vars[type] // nameof(type_var): a var holding the type, so a mapper or a subtype can change it
	else if(istext(type))
		rolled = call(holder, type)(roller_of(holder))
	else
		var/datum/entry/spec = type
		rolled = roller_of(holder).weighted(spec.args["weights"]) // a missing weight counts 1: a plain list is uniform
	if(isnull(rolled))
		return null
	if(!islist(rolled))
		rolled = list(rolled)
	. = list()
	for(var/thing in rolled)
		if(!ispath(thing))
			. += thing // an instance the roll proc made
			continue
		var/n = rolled[thing]
		.[thing] += (isnum(n) ? n : 1) * count

/proc/knows(language, when = null)
	return entry_make(ENTRY_KNOWS, "knows:[language]", list("language" = language, "when" = when))

/// starts_args with OWNER resolved to `holder` (a make_args() record becomes a copy with its values resolved and `by` the holder).
/proc/starts_args_resolve(datum/holder, list/starts_args)
	if(isnull(starts_args))
		return null
	if(istype(starts_args, /datum/make_args))
		starts_args = list(starts_args)
	if(!islist(starts_args))
		return list(owner_resolve(starts_args, holder))
	. = list()
	for(var/value in starts_args)
		if(istype(value, /datum/make_args))
			var/datum/make_args/template = value
			var/datum/make_args/M = new
			M.by = holder // ALLOW(ownership): a make() record names its creator for one construction and is dropped after
			M.values = list()
			for(var/name in template.values)
				M.values[name] = owner_resolve(template.values[name], holder)
			. += M
		else
			. += list(owner_resolve(value, holder))

/proc/contains_init(atom/holder, datum/lifeform_plan/P)
	for(var/datum/centry/C as anything in P.contains)
		var/datum/entry/E = C.item
		if((C.whens && !op_whens_hold(holder, C.whens)) || (!isnull(E.args["when"]) && !condition_holds(holder, E.args["when"])))
			continue
		var/list/made = contains_roll(holder, E)
		var/list/ctor = starts_args_resolve(holder, E.args["args"])
		for(var/key in made)
			var/list/things = list()
			if(ispath(key))
				var/type = key
				for(var/i in 1 to max(made[key], 0))
					things += length(ctor) ? new type(arglist(list(null) + ctor)) : new type(null)
			else
				things += key
			if(!isatom(holder))
				continue
			for(var/atom/movable/thing as anything in things)
				if(E.args["slot"])
					if(move_into(holder, E.args["slot"], thing, force = TRUE))
						continue
				thing.lifeform_place(holder)

/proc/knows_init(datum/holder, datum/lifeform_plan/P)
	if(!ismob(holder))
		declare_report("knows() on [holder.type]: only mobs know languages")
		return
	var/mob/M = holder
	for(var/datum/centry/C as anything in P.knows)
		var/datum/entry/E = C.item
		if((C.whens && !op_whens_hold(holder, C.whens)) || (!isnull(E.args["when"]) && !condition_holds(holder, E.args["when"])))
			continue
		M.lifeform_learn(E.args["language"])

/// Placement of initial contents that did not enter a declared slot.
/atom/movable/proc/lifeform_place(atom/holder)
	return null

/// A language declaration is delivered by the mob implementation.
/mob/proc/lifeform_learn(language)
	return null
