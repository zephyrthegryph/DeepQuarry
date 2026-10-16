// The compatibility table between the old body-factor ids (BF_*, code/__defines/body_factors.dm) and the stats that replace them (code/contracts/ids/
// body_stats.dm). doc/rewrite/proposals/stat_layer.md, section 4.1.
//
// The factor tables of the sources still key their values by BF_* id, and a legacy read is `L.factor(BF_X)`; both go through this table to the
// stat of the same factor. It is the one place the two id spaces meet, and goes with the last BF_ reference. A factor that was deleted
// (arrhythmia risk, vision, hearing) has no entry: its id translates to 0.

/// The stat id (STAT_*) of body factor `id` (BF_*), or 0 for an id that names no factor any more.
/proc/bf_stat_id(id)
	var/static/list/ids
	if(!ids)
		ids = new /list(BF_COUNT)
		ids[BF_AIRWAY] = STAT_AIRWAY
		ids[BF_RESP_DRIVE] = STAT_RESP_DRIVE
		ids[BF_LUNG_MECHANICS] = STAT_LUNG_MECHANICS
		ids[BF_GAS_EXCHANGE] = STAT_GAS_EXCHANGE
		ids[BF_PUMP] = STAT_PUMP
		ids[BF_CIRCULATION] = STAT_CIRCULATION
		ids[BF_DEMAND] = STAT_DEMAND
		ids[BF_PROGRESSION] = STAT_PROGRESSION
		ids[BF_METABOLISM] = STAT_METABOLISM_MULT
		ids[BF_BLEEDING] = STAT_BLEEDING
		ids[BF_HEALING] = STAT_HEALING
		ids[BF_ANALGESIA] = STAT_ANALGESIA
		ids[BF_PAIN] = STAT_PAIN
		ids[BF_SEDATION] = STAT_SEDATION
		ids[BF_HEART_RATE] = STAT_HEART_RATE
		ids[BF_TEMPERATURE] = STAT_TEMPERATURE
		ids[BF_BP_SYSTOLIC] = STAT_BP_SYSTOLIC
		ids[BF_BP_DIASTOLIC] = STAT_BP_DIASTOLIC
		ids[BF_O2_SAT] = STAT_O2_SAT
		ids[BF_RESP_RATE] = STAT_RESP_RATE
		ids[BF_SLOWDOWN] = STAT_SLOWDOWN
		ids[BF_PENALTY_SCALE] = STAT_PENALTY_SCALE
		ids[BF_HASTE] = STAT_HASTE
		ids[BF_ACCURACY] = STAT_ACCURACY
		ids[BF_DISPERSION] = STAT_DISPERSION
		ids[BF_EVASION] = STAT_EVASION
		ids[BF_ATTACK_SPEED] = STAT_ATTACK_SPEED
		ids[BF_MELEE_DAMAGE] = STAT_MELEE_DAMAGE
		ids[BF_MOTOR_CONTROL] = STAT_MOTOR_CONTROL
		ids[BF_DARKSIGHT] = STAT_DARKSIGHT
		ids[BF_SIGHT_FLAGS] = STAT_SIGHT_FLAGS
		ids[BF_ACTION_BLOCKS] = STAT_ACTION_BLOCKS
		ids[BF_INCOMING_ALL] = STAT_INCOMING_ALL
		ids[BF_INCOMING_PHYSICAL] = STAT_INCOMING_PHYSICAL
		ids[BF_INCOMING_THERMAL] = STAT_INCOMING_THERMAL
		ids[BF_INCOMING_TOXIC] = STAT_INCOMING_TOXIC
		ids[BF_INCOMING_GENETIC] = STAT_INCOMING_GENETIC
		ids[BF_INCOMING_NEURAL] = STAT_INCOMING_NEURAL
		ids[BF_INCOMING_PAIN] = STAT_INCOMING_PAIN
		ids[BF_DISABLE_DURATION] = STAT_DISABLE_DURATION
		ids[BF_HEALING_RECEIVED] = STAT_HEALING_RECEIVED
		ids[BF_ENDURANCE_FLAT] = STAT_ENDURANCE_FLAT
		ids[BF_ENDURANCE_MULT] = STAT_ENDURANCE_MULT
		ids[BF_PAIN_IMMUNITY] = STAT_PAIN_IMMUNITY
		ids[BF_PULSE_SHIFT] = STAT_PULSE_SHIFT
		ids[BF_PULSE_SET] = STAT_PULSE_SET
		ids[BF_EMP_SHIFT] = STAT_EMP_SHIFT
		ids[BF_EXPLOSION_SHIFT] = STAT_EXPLOSION_SHIFT
		ids[BF_HEAT_EXPOSURE] = STAT_HEAT_EXPOSURE
		ids[BF_COLD_EXPOSURE] = STAT_COLD_EXPOSURE
		ids[BF_SIEMENS] = STAT_SIEMENS
		ids[BF_STABILIZATION] = STAT_STABILIZATION
		ids[BF_ANTIMICROBIAL] = STAT_ANTIMICROBIAL
		ids[BF_BLOOD_REGEN] = STAT_BLOOD_REGEN
		ids[BF_INTOXICATION] = STAT_INTOXICATION
		ids[BF_HEPATOTOXICITY] = STAT_HEPATOTOXICITY
		ids[BF_ANTIEMETIC] = STAT_ANTIEMETIC
		ids[BF_ALLERGY] = STAT_ALLERGY
		ids[BF_WITHDRAWAL] = STAT_WITHDRAWAL
		ids[BF_NEURAL_REPAIR] = STAT_NEURAL_REPAIR
		ids[BF_IMMUNE_SUPPRESSION] = STAT_IMMUNE_SUPPRESSION
		ids[BF_O2_CARRIAGE] = STAT_O2_CARRIAGE
		ids[BF_TISSUE_UPTAKE] = STAT_TISSUE_UPTAKE
		ids[BF_STASIS] = STAT_STASIS
		ids[BF_CARDIAC_IRRITABILITY] = STAT_CARDIAC_IRRITABILITY
		ids[BF_ICON_SCALE_X] = STAT_SCALE_MULT_X
		ids[BF_ICON_SCALE_Y] = STAT_SCALE_MULT_Y
		ids[BF_ARMOR(1)] = STAT_ARMOR_BLUNT
		ids[BF_ARMOR(2)] = STAT_ARMOR_CUT
		ids[BF_ARMOR(3)] = STAT_ARMOR_PIERCE
		ids[BF_ARMOR(4)] = STAT_ARMOR_BURN
		ids[BF_ARMOR(5)] = STAT_ARMOR_FROSTBITE
		ids[BF_ARMOR(6)] = STAT_ARMOR_CORROSIVE
		ids[BF_ARMOR(7)] = STAT_ARMOR_ELECTRIC
		ids[BF_ARMOR(8)] = STAT_ARMOR_TOXIN
		ids[BF_ARMOR(9)] = STAT_ARMOR_RADIATION
		ids[BF_ARMOR(10)] = STAT_ARMOR_CELLULAR
		ids[BF_ARMOR(11)] = STAT_ARMOR_NEURAL
		ids[BF_ARMOR(12)] = STAT_ARMOR_PAIN
		ids[BF_ARMOR(13)] = STAT_ARMOR_DIGESTION
		ids[BF_ARMOR(14)] = STAT_ARMOR_BLAST
		for(var/slot in 1 to BF_COUNT)
			if(isnull(ids[slot]))
				ids[slot] = 0
	if(!isnum(id) || id < 1 || id > BF_COUNT)
		return 0
	return ids[id]

/// The stat of the incoming-injury multiplier of an INJURY_CATEGORY_*.
/proc/incoming_stat_id(category)
	return bf_stat_id(BF_INCOMING(category))

/// The stat of the armour of an armour kind (INJURY_* or ARMOR_BLAST).
/proc/armor_stat_id(kind)
	return bf_stat_id(BF_ARMOR(kind))

/// `table` (BF_* id -> value) rekeyed by stat id, for hold_table(). A factor that was deleted is dropped. Allocates the new table.
/proc/body_table_stat_keys(alist/table)
	var/alist/out = alist()
	for(var/id in table)
		var/stat_id = bf_stat_id(id)
		if(stat_id)
			out[stat_id] = table[id]
	return out

/// Holds `table` (BF_* -> value) as rows of `source` on `L` at `scale` and `stacks` (hold_table() of the same table keyed by stat). A source with
/// more than one table gives each a `part`. An empty or null table holds nothing; inside a pass (hold_tables_begin()) the rows the source held
/// before leave at its end.
/proc/body_hold(mob/living/L, source, alist/table, scale = 1, stacks = 1, part = null)
	if(!length(table))
		return
	hold_table(L, source, body_table_stat_keys(table), scale, stacks, part)
