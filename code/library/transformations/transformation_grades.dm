// The grade test of a transformation (code/domains/world_model/reagents/contaminants.dm; the `needs_grade` argument is documented in transformation_entry.dm).
// Contaminants are reagents no rule takes, so a rule's reactants and products never carry or gain any: they stay in the holder and the mixture's purity
// moves with the volumes.

/// Does the mixture in `holder` meet the minimum grade `X` asks for (needs_grade)?
/proc/xform_grades_met(datum/xform/X, datum/reagents/holder)
	var/grade = holder.grade()
	if(grade < X.needs_grade)
		if(GLOB.chem_trace)
			log_world("CHEM: reaction [X.rule_type] refused in [holder.my_atom]: the mixture is [grade_name(grade)] and it needs [grade_name(X.needs_grade)]")
		return FALSE
	return TRUE
