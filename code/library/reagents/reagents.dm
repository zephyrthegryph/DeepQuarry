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
//   holder       the /datum/reagents subtype of the holder (the distillery's /datum/reagents/distilling), or nameof(var) holding it.
//   starts_from  list(nameof(id var) = amount): a reagent named by a holder var (a shower's spray, a blood pack's blood), put in first. The
//                amount is a number, nameof(var) or a PROC_REF; its data is keyed by nameof(id var) in `data` (or by the id).
//   contents_from  nameof(var) or PROC_REF(x): a list(REAGENT_ID_X = amount) the holder answers at init, added after `add` (a rolled recipe:
//                rolls() runs before this, so a proc reading a rolled var sees its value). Data as for the other contents.
//   last         list(REAGENT_ID_X = amount): contents added after everything else, so they take what room the rest left (a snack's own
//                nutriment tops up after its recipe's reagents). Amounts and configure() merging as for `add`.
//   data         list(REAGENT_ID_X = data): the data the reagent is added with (a food's taste list, a culture's blood data). The value is a
//                list, nameof(var) read from the holder at init (a type's `nutriment_desc`), or a PROC_REF of a holder proc answering it
//                (made per instance). Under configure() it merges per reagent id.
// An amount in `starts` or `add` may also be nameof(var) or a PROC_REF answered at init (a food's `nutriment_amt`); an amount of 0 or
// less adds nothing. Under configure() a computed amount and a number both count: their sum is added.
//
// Timing: the holder is made in the capability's preinit hook, which runs at the root of /atom/Initialize() where the old declaration table
// ran: a subtype's Initialize() sees the filled holder right after `. = ..()`, and reagent_container()'s init (later) finds it made.
// Memory: one interned definition per distinct declaration; an instance owns only its /datum/reagents.

CAPABILITY_TYPE(reagents, CAP_REAGENTS, /datum/capability/lib/reagents, key = NONE, volume = 0, starts = null, add = null, tint = FALSE, holder = null, starts_from = null, data = null, last = null, contents_from = null)

/datum/capability/lib/reagents
	holder_hooks = HOLDER_HOOK_PREINIT
	/// starting_template()'s answer for `template_regime`: the shared id -> amount list, FALSE when this declaration can't have one, null unasked.
	var/tmp/template_cache
	var/tmp/template_regime
	/// The template's units: a holder smaller than this is filled add by add (each add clamps to the space left).
	var/tmp/template_total = 0

/// configure(reagents(...)): `add` merges into the inherited adds (amounts sum), `starts` replaces the contents and drops inherited adds.
/datum/capability/lib/reagents/reconfigure_ctor(list/ctor, list/changes)
	for(var/name in changes)
		var/value = changes[name]
		switch(name)
			if("add", "last")
				var/list/inherited = ctor[name]
				var/list/merged = islist(inherited) ? inherited.Copy() : list()
				for(var/id in value)
					var/amount = value[id] || 1
					var/list/had = merged[id]
					if(isnull(had))
						merged[id] = amount
					else if(isnum(had) && isnum(amount))
						merged[id] = had + amount
					else
						// A computed amount (nameof() or PROC_REF) and another part: keep both, summed at init.
						merged[id] = (islist(had) ? had.Copy() : list(had)) + list(amount)
				ctor[name] = merged
			if("data")
				var/list/inherited_data = ctor["data"]
				var/list/merged_data = islist(inherited_data) ? inherited_data.Copy() : list()
				for(var/id in value)
					merged_data[id] = value[id]
				ctor["data"] = merged_data
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
	var/holder_type = (istext(src.holder) && (src.holder in holder.vars)) ? holder.vars[src.holder] : src.holder // nameof(var): the holder's own type var
	holder.create_reagents(max_volume, ispath(holder_type, /datum/reagents) ? holder_type : /datum/reagents)
	// A starting set no transformation can take (every rule needs a reagent or catalyst it lacks) settles to nothing: each add skips its settle.
	var/list/template = starting_template(holder, max_volume)
	if(template)
		if(length(template)) // an empty declaration starts empty: nothing was added, so nothing is told of a change
			holder.reagents.fill_from_template(template)
			if(tint)
				holder.set_color(holder.reagents.get_color())
		return
	var/list/ids = declared_ids(holder)
	var/inert = !isnull(ids) && reagents_set_inert(holder.reagents.xform_regime(), ids)
	var/total = 0
	for(var/id_var in starts_from)
		var/id = holder.vars[id_var]
		var/amount = reagents_amount_of(holder, starts_from[id_var])
		if(!id || amount <= 0)
			continue
		total += amount
		// The data of a reagent named by a var is keyed by that var's name (data = list(nameof(id var) = ...)), or by the id itself.
		holder.reagents.add_reagent(id, amount, (data && !isnull(data[id_var])) ? reagents_data_of(holder, id_var) : reagents_data_of(holder, id), inert)
	var/declared = FALSE
	for(var/id in starts)
		var/amount = reagents_amount_of(holder, starts[id])
		if(amount <= 0)
			continue
		total += amount
		declared = TRUE
		holder.reagents.add_reagent(id, amount, reagents_data_of(holder, id), inert)
	for(var/id in add)
		var/amount = reagents_amount_of(holder, add[id])
		if(amount <= 0)
			continue
		total += amount
		declared = TRUE
		holder.reagents.add_reagent(id, amount, reagents_data_of(holder, id), inert)
	if(contents_from)
		var/list/rolled = istext(contents_from) && (contents_from in holder.vars) ? holder.vars[contents_from] : holder_call(holder, contents_from)
		for(var/id in rolled)
			var/amount = reagents_amount_of(holder, rolled[id])
			if(amount <= 0)
				continue
			total += amount
			declared = TRUE
			holder.reagents.add_reagent(id, amount, reagents_data_of(holder, id), inert)
	for(var/id in last)
		var/amount = reagents_amount_of(holder, last[id])
		if(amount <= 0)
			continue
		total += amount
		declared = TRUE
		holder.reagents.add_reagent(id, amount, reagents_data_of(holder, id), inert)
	if(tint && declared)
		holder.set_color(holder.reagents.get_color())
	if(total > max_volume)
		WARNING("[holder]([holder.type]) declares more reagents ([total]) than its volume ([max_volume])")

/// The starting reagents as one ordered id -> amount list when they are the same for every holder of this declaration (numbers only: no var or
/// proc amounts, no data, no starts_from or contents_from), fit this holder's volume and settle to nothing; else null and the holder is filled
/// add by add. Worked out once per declaration and regime, and shared: fill_from_template() only reads it.
/datum/capability/lib/reagents/proc/starting_template(atom/holder, max_volume)
	if(starts_from || contents_from || data)
		return null
	var/regime = holder.reagents.xform_regime()
	if(template_regime != regime || isnull(template_cache))
		build_template(regime)
	// One reagent is no cheaper in one pass (making the reagent datum is the cost; bench tmp A/B: 424 us add vs 527 us filled): it goes add by add.
	if(!template_cache || length(template_cache) == 1 || template_total > max_volume)
		return null
	return template_cache

/datum/capability/lib/reagents/proc/build_template(regime)
	var/list/built = list()
	var/total = 0
	for(var/list/part in list(starts, add, last))
		for(var/id in part)
			var/amount = part[id]
			if(isnull(amount))
				amount = 1
			if(!isnum(amount) || (id in built))
				return remember_template(regime, FALSE)
			if(amount <= 0)
				continue
			built[id] = amount
			total += amount
	if(!reagents_set_inert(regime, built))
		return remember_template(regime, FALSE)
	template_total = total
	return remember_template(regime, built)

/datum/capability/lib/reagents/proc/remember_template(regime, list/built)
	template_regime = regime
	template_cache = built
	return built || null

/// The ids this declaration puts in `holder`, or null when it takes a computed contents_from list.
/datum/capability/lib/reagents/proc/declared_ids(atom/holder)
	. = list()
	for(var/id_var in starts_from)
		var/id = holder.vars[id_var]
		if(id)
			. |= id
	for(var/id in starts)
		. |= id
	for(var/id in add)
		. |= id
	if(contents_from)
		return null // a recipe answered at init is read once, by the add: such a holder settles after every add as it always did
	for(var/id in last)
		. |= id

/// The volume the declaration gives this holder: a number, a holder var named by nameof(), or a holder proc's answer.
/datum/capability/lib/reagents/proc/reagents_volume_of(atom/holder)
	var/value = volume
	if(istext(value))
		value = (value in holder.vars) ? holder.vars[value] : holder_call(holder, value)
	return isnum(value) ? value : 0

/// One declared amount: a number (null means 1), nameof(var) or a PROC_REF read from the holder, or a list of such parts summed.
/datum/capability/lib/reagents/proc/reagents_amount_of(atom/holder, value)
	if(isnull(value))
		return 1
	if(islist(value))
		var/sum = 0
		for(var/part in value)
			sum += reagents_amount_of(holder, part)
		return sum
	if(istext(value))
		value = (value in holder.vars) ? holder.vars[value] : holder_call(holder, value)
	return isnum(value) ? value : 0

/// The data reagent `id` is added with: `data[id]`, a list as written, or read from the holder (nameof(var) or a PROC_REF).
/datum/capability/lib/reagents/proc/reagents_data_of(atom/holder, id)
	if(!data)
		return null
	var/value = data[id]
	if(istext(value))
		value = (value in holder.vars) ? holder.vars[value] : holder_call(holder, value)
	return value

/// A mob that does not take what a belly made refuses a holder whose contents came from one (a dose, a drink, an injection, a feeding).
/proc/belly_liquid_refused(atom/holder, atom/target)
	var/mob/M = target
	if(!istype(M))
		return FALSE
	return M.refuses_belly_liquid(holder)

/// Whether this mob refuses a holder whose contents came from a belly. Nothing is a belly's before the content layer says so.
/mob/proc/refuses_belly_liquid(atom/holder)
	return FALSE

/// Whether no transformation of `regime` can fire on a holder holding only `ids`: every rule indexed under one of them needs a reagent or a catalyst
/// outside the set (xform_matches() asks for all of them), so the settle after each add would find nothing. Cached per regime and set.
/proc/reagents_set_inert(regime, list/ids)
	if(!length(ids))
		return TRUE
	var/list/sorted = sortList(ids.Copy())
	return CACHED(reagents_set_inert, "[regime]|[jointext(sorted, ",")]")

DECLARE_SHARED_CACHE(reagents_set_inert, GLOBAL_PROC_REF(reagents_set_inert_build), SC_NEVER)

/proc/reagents_set_inert_build(key)
	var/bar = findtext(key, "|")
	var/regime = copytext(key, 1, bar)
	if(isnum(text2num(regime)))
		regime = text2num(regime)
	var/list/ids = splittext(copytext(key, bar + 1), ",")
	var/list/lookup = xform_bucket_table(MEDIUM_REAGENTS, regime)
	for(var/id in ids)
		for(var/datum/xform/X as anything in lookup[id])
			var/possible = TRUE
			for(var/need in X.reagent_takes)
				if(!(need in ids))
					possible = FALSE
					break
			if(possible)
				for(var/need in X.reagent_catalysts)
					if(!(need in ids))
						possible = FALSE
						break
			if(possible)
				return FALSE
	return TRUE
