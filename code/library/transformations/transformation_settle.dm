// The matcher and the settle of the reagents medium (doc/rewrite/proposals/transformations.md section 5).
//
// A subject's reagents settle to a fixed point: gather the rules that are candidates for what the holder holds (the bucket of each reagent it contains,
// in the holder's own order, each rule once), test them cheap to expensive, step each one that holds, and repeat until a pass fires nothing. Then every rule
// that fired is announced once (its message and sound, a /datum/notice/transformed). The loop, the order and the arithmetic are chemistry's, ported from
// /datum/reagents/proc/handle_reactions() and /datum/decl/chemical_reaction/proc/react_step(); the pins of code/modules/unit_tests/dq_xform_pins.dm hold the
// outcome identical.
//
// Debug and audit: GLOB.xform_trace logs every step (rule, subject, extent, product) to the world log; a settle that hits XFORM_MAX_PASSES is logged
// with the rules still firing; each product still emits CONTRACT_EVENT_CHEMISTRY_RESULT.

/// TRUE: every step of every settle is written to the world log. Set by an admin or a test to follow a reaction that behaves strangely.
GLOBAL_VAR_INIT(xform_trace, FALSE)

/// What a notice of a rule that went carries (code/library/transformations/transformation_settle.dm): the rule, the subject, how far it went in this
/// settle (reaction units, summed over the steps), what it took (reagent id => units) and what it made (units of its product).
/datum/notice/transformed
	var/rule
	var/subject
	var/extent
	var/took
	var/made

/datum/notice/transformed/fill(rule, subject, extent, took, made)
	src.rule = rule
	src.subject = subject
	src.extent = extent
	src.took = took
	src.made = made

/// The regime a reagent holder runs: the rules of that regime are its candidates. A holder with another regime overrides this.
/datum/reagents/proc/xform_regime()
	return REGIME_INSTANT

/// The air whose heat and gas a rule books into for XFORM_HEAT_AIR: the atom's own air. A test atom that must not take heat overrides this.
/atom/proc/xform_air_sink()
	return return_air()

/// Whether `X` holds for `holder` now: the subject, the amounts, the catalysts, the blockers, then its conditions. The same tests as the old can_happen()
/// in the same order, cheapest first; nothing here writes.
/proc/xform_matches(datum/xform/X, datum/reagents/holder)
	if(X.subject_type && !istype(holder.my_atom, X.subject_type))
		return FALSE
	if(!holder.has_all_reagents(X.reagent_takes))
		return FALSE
	if(!holder.has_all_reagents(X.reagent_catalysts))
		return FALSE
	if(holder.has_any_reagent(X.reagent_blocked))
		return FALSE
	if(!isnull(X.holds) && !xform_cond_holds(X, holder, X.holds))
		return FALSE
	return TRUE

/// One step of `X` in `holder`: the reactants go, the product comes, the rule's energy, gas and tail run, the product is audited. Returns how far it went in
/// reaction units (0: nothing happened). `belly_reagent` is the belly-reagent state the product inherits.
/proc/xform_step(datum/xform/X, datum/reagents/holder, belly_reagent, list/ledger)
	//determine how far the reaction can proceed
	var/list/reaction_limits = list()
	for(var/reactant in X.reagent_takes)
		reaction_limits += holder.get_reagent_amount(reactant) / LAZYACCESS(X.reagent_takes, reactant)

	//determine how far the reaction proceeds
	var/reaction_limit = min(reaction_limits)
	var/progress_limit = X.progress(holder, reaction_limit)
	var/reaction_progress = min(reaction_limit, progress_limit) //no matter what, the reaction progress cannot exceed the stoichiometric limit.

	//need to obtain the new reagent's data before anything is altered
	var/datum/owner = X.owner_of()
	var/data = X.data_proc ? call(owner, X.data_proc)(holder, reaction_progress) : null

	//remove the reactants
	for(var/reactant in X.reagent_takes)
		var/amt_used = LAZYACCESS(X.reagent_takes, reactant) * reaction_progress
		holder.remove_reagent(reactant, amt_used, safety = 1)

	//add the product
	var/amt_produced = X.result_amount * reaction_progress
	if(X.result)
		holder.add_reagent(X.result, amt_produced, data, safety = 1, was_from_belly = belly_reagent)

	xform_effects(X, holder, owner, amt_produced)
	if(SScontracts && X.result && amt_produced > 0)
		emit_contract_event(CONTRACT_EVENT_CHEMISTRY_RESULT, list(
			"department" = DEPARTMENT_RESEARCH,
			"reaction_id" = X.rule_type,
			"product_id" = X.result,
			"amount" = amt_produced,
			"reactant_count" = length(X.reagent_takes),
			"detail" = "Produced [round(amt_produced, 0.1)] units of [X.result] through [X.name].",
		), "chemistry-result:[REF(holder)]:[X.rule_type]:[world.time]:[round(amt_produced, 0.01)]", holder.my_atom)

	if(reaction_progress)
		var/list/seen = ledger[X]
		if(!seen)
			seen = list(0, 0)
			ledger[X] = seen
		seen[1] += reaction_progress
		seen[2] += amt_produced
	if(GLOB.xform_trace)
		log_world("XFORM: [X.rule_type] stepped [reaction_progress] in [holder.my_atom] ([holder.my_atom?.type]); made [amt_produced] of [X.result || "nothing"]")
	return reaction_progress

/// What a step does besides moving reagents, in the order the old on_reaction() ran it: the gas taken from the air, the energy booked, the rule's tail.
/proc/xform_effects(datum/xform/X, datum/reagents/holder, datum/owner, amt_produced)
	if(length(X.takes_ambient))
		var/datum/gas_mixture/air = holder.my_atom?.return_air()
		if(air)
			for(var/gas_id in X.takes_ambient)
				air.adjust_gas(gas_id, -X.takes_ambient[gas_id])
	if(X.energy)
		xform_book_energy(X, holder)
	if(X.then_proc)
		call(owner, X.then_proc)(holder, amt_produced)

/// Books a rule's energy where it goes: into the air around the subject (heat_add() on its air) or the subject's own heat body.
/proc/xform_book_energy(datum/xform/X, datum/reagents/holder)
	var/atom/thing = holder.my_atom
	if(!thing)
		return
	if(X.heat_to == XFORM_HEAT_SUBJECT)
		heat_add(thing, X.energy, XFORM_HEAT_SOURCE)
		return
	var/datum/gas_mixture/air = thing.xform_air_sink()
	if(air)
		heat_add(air, X.energy, XFORM_HEAT_SOURCE)

/// Settles the reagents of `holder`: steps every rule that holds until none does. Returns the rules that fired, in the order they first did.
/// Announces them (says, plays, notice) before returning; the caller updates the holder's totals and publishes what it publishes.
/proc/xform_settle_reagents(datum/reagents/holder)
	var/list/lookup = xform_bucket_table(MEDIUM_REAGENTS, holder.xform_regime())
	var/belly_tracking = holder.supports_belly_reagents()
	var/list/eligible = list()
	var/list/fired = list()
	var/list/ledger = list()
	var/occurred
	var/from_belly
	var/passes = 0
	do
		from_belly = FALSE
		occurred = FALSE
		for(var/datum/reagent/R as anything in holder.reagent_list)
			if(lookup[R.id])
				eligible |= lookup[R.id]
				if(belly_tracking && !from_belly)
					from_belly = R.from_belly
		for(var/datum/xform/X as anything in eligible)
			if(xform_matches(X, holder) && xform_step(X, holder, from_belly, ledger))
				fired |= X
				occurred = TRUE
		eligible.len = 0
		if(++passes >= XFORM_MAX_PASSES)
			var/list/names = list()
			for(var/datum/xform/X as anything in fired)
				names += "[X.rule_type]"
			log_world("XFORM: settle of [holder.my_atom] ([holder.my_atom?.type]) stopped after [passes] passes; fired: [jointext(names, ", ")]")
			break
	while(occurred)
	for(var/datum/xform/X as anything in fired)
		xform_announce(X, holder, ledger[X])
	return fired

/// A rule that fired in a settle: its message to the people watching, its sound, and its notice. Once per settle, as post_reaction() was.
/proc/xform_announce(datum/xform/X, datum/reagents/holder, list/went)
	var/atom/container = holder.my_atom
	if(X.says && container && !ismob(container))
		var/turf/T = get_turf(container)
		var/list/seen = viewers(4, T)
		for(var/mob/M in seen)
			if(M.client)
				M.show_message(span_notice("[icon2html(container,M.client)] [X.says]"), 1)
		playsound(T, X.plays, 80, 1)
	if(!notice_wanted(holder, X.notice_type))
		return
	var/extent = went ? went[1] : 0
	var/made = went ? went[2] : 0
	var/list/took = list()
	for(var/reactant in X.reagent_takes)
		took[reactant] = X.reagent_takes[reactant] * extent
	notice_publish(holder, take_notice(X.notice_type, X, holder, extent, took, made))

// ---- outputs through the containment ledger (D10) ----

/// Makes an item or stack product of a rule and checks that its place takes it, before anything is spent. Returns the product (in nullspace) or null; a
/// `why` list given gets the refusal reason. Items and stacks never truncate: a refused insert refuses the whole step, as slots always did.
/proc/xform_prepare_item(datum/holder, slot_id, product_type, amount = 1, list/why = null)
	var/atom/movable/product
	if(ispath(product_type, /obj/item/stack))
		product = new product_type(null, amount)
	else
		product = new product_type(null)
	var/reason = move_into_refusal(holder, slot_id, product)
	if(reason)
		why?.Add(reason)
		spent(product)
		return null
	return product

/// Puts a prepared product into its place: the ledger's one transfer. TRUE when it is there. A refusal here (the place changed since the check) deletes
/// the product and is logged: the step that spent its inputs for it is a bug of the rule's reservation.
/proc/xform_commit_item(datum/holder, slot_id, atom/movable/product)
	var/refused = move_into_reason(holder, slot_id, product)
	if(!refused)
		return TRUE
	log_world("XFORM: [product] was refused by [holder] ([slot_id || "default"]) after its inputs were spent: [reason_text(refused)]")
	spent(product)
	return FALSE
