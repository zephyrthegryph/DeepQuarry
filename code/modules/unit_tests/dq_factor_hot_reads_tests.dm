// Every read of a body factor is a plain read of the stat var now (doc/rewrite/proposals/stat_layer.md, wave 2): whatever sources a mob carries, the stat
// vars hold what the oracle folds from them. Twenty humans, each given a few sources picked at random (a body effect with stacks, reagents at a
// dose, afflictions with a factor table at a severity), must read the oracle's vector on every factor.

/datum/unit_test/dq_factor_hot_reads

/datum/unit_test/dq_factor_hot_reads/Run()
	test_rng(7)
	var/list/effects = list()
	for(var/path in subtypesof(/datum/body_effect))
		var/datum/body_effect/def = body_effect_def(path)
		if(def && length(def.factors) && !ispath(path, /datum/body_effect/stasis))
			effects += path
	var/list/reagents = list()
	for(var/reagent_id in SSchemistry.ready().chemical_reagents)
		var/datum/reagent/R = SSchemistry.ready().chemical_reagents[reagent_id]
		if(length(R.factors) && !R.affects_dead)
			reagents += reagent_id
	var/list/afflictions = list()
	for(var/path in subtypesof(/datum/affliction))
		var/datum/affliction/typed = path
		if(!initial(typed.catalogued))
			continue
		var/datum/affliction/proto = dq_proto(path)
		if(proto && proto.abstract_type != path && length(proto.factors))
			afflictions += path
	TEST_ASSERT(length(effects) && length(reagents) && length(afflictions), "the pools are not empty ([length(effects)], [length(reagents)], [length(afflictions)])")
	for(var/round in 1 to 20)
		var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
		var/list/applied = list()
		for(var/i in 1 to rand(1, 3))
			switch(rand(1, 3))
				if(1)
					var/path = pick(effects)
					var/stacks = rand(1, 3)
					for(var/s in 1 to stacks)
						H.apply_body_effect(path)
					applied += "[path] x[stacks]"
				if(2)
					var/reagent_id = pick(reagents)
					var/dose = DQ_CHEM_STANDARD_DOSE * pick(0.25, 0.5, 1, 2, 4)
					H.bloodstr.add_reagent(reagent_id, dose)
					applied += "[reagent_id] [dose]u"
				if(3)
					var/path = pick(afflictions)
					var/severity = rand(10, 100)
					var/datum/affliction/A = H.body.afflict(path, null, severity)
					if(A)
						applied += "[path] at [severity]"
		// An affliction's contribution follows its severity at the band edge: re-read inside a band before comparing the composition.
		if(LAZYLEN(H.body.afflictions))
			H.body.refresh_factors()
		var/list/diff = factor_oracle_diff(H)
		TEST_ASSERT(!length(diff), "round [round] ([jointext(applied, ", ")]): [jointext(diff, "; ")]")
		qdel(H)
