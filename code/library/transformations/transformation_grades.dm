// What a transformation does with the contaminants of its reagents (code/domains/world_model/reagents/contaminants.dm; the `needs_grade` argument is documented in
// transformation_entry.dm): the average carried into the product, and the grade test of xform_matches().

/// The volume-weighted average contaminants of the reactants `X` consumes at `progress` reaction units, weighted by the units used (a pure reactant
/// dilutes). Null when no reactant carries any. Read before the reactants are removed.
/proc/xform_carried_contaminants(datum/xform/X, datum/reagents/holder, progress)
	var/total_used = 0
	var/list/sums
	for(var/reactant in X.reagent_takes)
		var/used = LAZYACCESS(X.reagent_takes, reactant) * progress
		if(used <= 0)
			continue
		total_used += used
		var/datum/reagent/R = holder.get_reagent(reactant)
		if(!R?.contaminants)
			continue
		for(var/contaminant_id in R.contaminants)
			LAZYSET(sums, contaminant_id, (sums?[contaminant_id] || 0) + R.contaminants[contaminant_id] * used)
	if(!sums || total_used <= 0)
		return null
	var/list/average
	for(var/contaminant_id in sums)
		var/fraction = sums[contaminant_id] / total_used
		if(fraction >= CONTAMINANT_EPSILON)
			LAZYSET(average, contaminant_id, fraction)
	if(average && GLOB.chem_trace)
		log_world("CHEM: reaction [X.rule_type] carries contaminants [contaminants_text(average)] into [X.result]")
	return average

/// Does every ingredient `X` asks a grade of (needs_grade) meet it in `holder`? A reagent that is not there fails.
/proc/xform_grades_met(datum/xform/X, datum/reagents/holder)
	for(var/reagent_id in X.needs_grade)
		var/datum/reagent/R = holder.get_reagent(reagent_id)
		if(!R || R.grade() < X.needs_grade[reagent_id])
			return FALSE
	return TRUE

