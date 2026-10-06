// reagents(...) (doc/rewrite/final_api.html, section 11 "Reagents and food"; doc/rewrite/reagents.md): the holder's reagent holder and what
// it starts with. The final form of the old DECLARE_REAGENTS family (deleted), written in the type's CAPABILITIES block:
//
//   CAPABILITIES(/obj/item/reagent_containers)
//       reagents(nameof(volume))                                          // a holder as big as the type's `volume` var
//
//   CAPABILITIES(/obj/item/reagent_containers/food/snacks/donut)
//       configure(reagents(add = list(REAGENT_ID_NUTRIMENT = 3, REAGENT_ID_SUGAR = 2)))   // adds to what the type inherits
//
//   CAPABILITIES(/obj/item/extinguisher/mini)
//       configure(reagents(starts = list(REAGENT_ID_FIREFOAM = 150)))     // replaces the inherited contents
//
//   CAPABILITIES(/obj/item/thing/dry)
//       without(CAP_REAGENTS)                                             // no holder at all
//
// Params:
//   volume       units: a number, or nameof(var) read from the holder at init (a mapped or edited volume), or a PROC_REF of a holder proc
//                answering it.
//   starts       list(REAGENT_ID_X = amount): the contents. Under configure() it REPLACES what was inherited (and drops inherited `add`s).
//   add          list(REAGENT_ID_X = amount): more contents. Under configure() it MERGES into what was inherited, amounts summing, the way
//                every DECLARE_REAGENTS line added to its parent's.
//   tint         colour the holder from its starting contents (pills, patches). Only when it starts with declared contents.
//   holder       the /datum/reagents subtype of the holder (the distillery's /datum/reagents/distilling).
//   starts_from  list(nameof(id var) = amount or nameof(amount var)): a reagent named by holder vars (a shower's spray), put in first.
//
// Timing: the holder is made in the capability's preinit hook, which runs at the root of /atom/Initialize() where the old declaration table
// ran: a subtype's Initialize() sees the filled holder right after `. = ..()`, and reagent_container()'s init (later) finds it made.
// Memory: one interned definition per distinct declaration; an instance owns only its /datum/reagents.

CAPABILITY_TYPE(reagents, CAP_REAGENTS, /datum/capability/lib/reagents, key = NONE, volume = 0, starts = null, add = null, tint = FALSE, holder = null, starts_from = null)

/datum/capability/lib/reagents
	holder_hooks = HOLDER_HOOK_PREINIT

/// configure(reagents(...)): `add` merges into the inherited adds (amounts sum), `starts` replaces the contents and drops inherited adds.
/datum/capability/lib/reagents/reconfigure_ctor(list/ctor, list/changes)
	for(var/name in changes)
		var/value = changes[name]
		switch(name)
			if("add")
				var/list/inherited = ctor["add"]
				var/list/merged = islist(inherited) ? inherited.Copy() : list()
				for(var/id in value)
					merged[id] += value[id] || 1
				ctor["add"] = merged
			if("starts")
				ctor["starts"] = value
				ctor -= "add"
			else
				ctor[name] = value

/datum/capability/lib/reagents/on_holder_preinit(datum/act/eval/A)
	var/atom/holder = A.holder
	if(!isatom(holder))
		stack_trace("reagents(): [holder] ([holder?.type]) is not an atom; only atoms have reagents")
		return
	var/max_volume = reagents_volume_of(holder)
	holder.create_reagents(max_volume, ispath(src.holder, /datum/reagents) ? src.holder : /datum/reagents)
	var/total = 0
	for(var/id_var in starts_from)
		var/id = holder.vars[id_var]
		var/amount = starts_from[id_var]
		if(istext(amount))
			amount = holder.vars[amount]
		if(!id || !isnum(amount) || amount <= 0)
			continue
		total += amount
		holder.reagents.add_reagent(id, amount)
	var/declared = FALSE
	for(var/id in starts)
		var/amount = starts[id] || 1
		total += amount
		declared = TRUE
		holder.reagents.add_reagent(id, amount)
	for(var/id in add)
		var/amount = add[id] || 1
		total += amount
		declared = TRUE
		holder.reagents.add_reagent(id, amount)
	if(tint && declared)
		holder.color = holder.reagents.get_color()
	if(total > max_volume)
		WARNING("[holder]([holder.type]) declares more reagents ([total]) than its volume ([max_volume])")

/// The volume the declaration gives this holder: a number, a holder var named by nameof(), or a holder proc's answer.
/datum/capability/lib/reagents/proc/reagents_volume_of(atom/holder)
	var/value = volume
	if(istext(value))
		value = (value in holder.vars) ? holder.vars[value] : holder_call(holder, value)
	return isnum(value) ? value : 0
