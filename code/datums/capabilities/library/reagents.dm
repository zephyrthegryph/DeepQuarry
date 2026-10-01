// reagents(): the holder's reagent holder and what it starts with (doc/rewrite/lifecycle.md "Starting state").
// Replaces DECLARE_REAGENTS / DECLARE_REAGENTS_TINTED / DECLARE_REAGENTS_TYPED / DECLARE_REAGENT_FROM_VAR /
// DECLARE_NO_REAGENTS (code/__defines/lifecycle_decl.dm, which stay until the codemod has moved their sites).
//
//	/obj/item/reagent_containers/food/snacks/donut/capabilities()
//		. = ..()
//		. += reagents(20, starts = list(REAGENT_ID_NUTRIMENT = 3, REAGENT_ID_SUGAR = 2))
//
//	/obj/item/reagent_containers/food/snacks/donut/jelly/capabilities()
//		. = ..()
//		. += refine(CAP_REAGENTS, starts = list(REAGENT_ID_BERRYJUICE = 5))	// adds to the donut's
//
//	/obj/item/reagent_containers/food/snacks/donut/plain/capabilities()
//		. = ..()
//		. = without(., CAP_REAGENTS)										// no holder at all
//
// Semantics, the old macros' exactly:
//   - reagents(volume, starts): a holder of `volume` (a number, or nameof() a holder var read per instance at
//     init) filled with `starts`. A subtype declaring reagents() again replaces the whole capability.
//   - refine(CAP_REAGENTS, starts =, volume =): the inherited capability with `starts` ADDED to its contents
//     (DECLARE_REAGENTS' "contents add to the parent's", the old `. = ..(); reagents.add_reagent()` chain) and,
//     when given, a new volume.
//   - `starts_from = list(nameof(reagent_id) = nameof(amount_var))`: a reagent whose id (and amount) come from
//     holder vars (DECLARE_REAGENT_FROM_VAR). `tint`: colour the holder from its reagents (pills, patches).
//     `holder`: a /datum/reagents subtype (DECLARE_REAGENTS_TYPED).
// Memory: the capability is one shared flyweight per distinct declaration (caps_intern_list()); an instance
// owns only the /datum/reagents holder it always had. A type without the capability allocates nothing.
// Timing: on_holder_init() runs in caps_init() at the end of /atom/Initialize(), so a subtype's Initialize()
// sees the reagents right after `. = ..()`, as with the macros.

/datum/capability/reagents
	/// Units, or the name of a holder var (nameof(volume)) read per instance at init.
	var/volume = 0
	/// list(REAGENT_ID_X = amount) the holder starts with. Shared: never written after construction.
	var/list/starts
	/// Reagents named by holder vars: id var name -> amount (a number, or the name of a holder var).
	var/list/starts_from
	/// The /datum/reagents type of the holder.
	var/holder_type = /datum/reagents
	/// Colour the holder from its reagents once filled.
	var/tint = FALSE

/**
 * The holder's reagents. volume: units or nameof() a holder var; starts: list(REAGENT_ID_X = amount);
 * holder: the /datum/reagents type; tint: colour from the reagents; starts_from: list(nameof(id var) = amount or
 * nameof(amount var)). Subtypes add with refine(CAP_REAGENTS, starts = ...), drop it with without(., CAP_REAGENTS).
 */
/proc/reagents(volume = 0, list/starts = null, holder = /datum/reagents, tint = FALSE, list/starts_from = null)
	var/datum/capability/reagents/C = new
	C.volume = isnull(volume) ? 0 : volume
	C.starts = length(starts) ? starts.Copy() : null
	C.starts_from = length(starts_from) ? starts_from.Copy() : null
	C.holder_type = ispath(holder, /datum/reagents) ? holder : /datum/reagents
	C.tint = !!tint
	return C

/// refine(CAP_REAGENTS, ...): `starts` adds to the contents, `volume` replaces the volume.
/datum/capability/reagents/refined(list/overrides)
	var/datum/capability/reagents/C = new
	C.volume = volume
	C.starts = starts
	C.starts_from = starts_from
	C.holder_type = holder_type
	C.tint = tint
	for(var/field in overrides)
		var/value = overrides[field]
		switch(field)
			if("volume")
				C.volume = value
			if("starts")
				var/list/merged = C.starts ? C.starts.Copy() : list()
				for(var/id in value)
					merged[id] += value[id] || 1
				C.starts = merged
			else
				stack_trace("refine(CAP_REAGENTS): the reagents capability has no refinable '[field]'")
	return C

/datum/capability/reagents/on_holder_init(atom/holder, mapload)
	var/max_volume = istext(volume) ? holder.vars[volume] : volume
	if(!isnum(max_volume))
		max_volume = 0
	holder.create_reagents(max_volume, holder_type)
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
	for(var/id in starts)
		var/amount = starts[id] || 1
		total += amount
		holder.reagents.add_reagent(id, amount)
	if(tint && length(starts))
		holder.color = holder.reagents.get_color()
	if(total > max_volume)
		WARNING("[holder]([holder.type]) starts with more reagents ([total]) than its volume ([max_volume])")
