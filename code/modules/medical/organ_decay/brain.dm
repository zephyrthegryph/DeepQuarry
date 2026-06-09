// Brain damage decay & alkysine cap.
//
// In CHOMP, alkysine flat-heals brain loss at -8/removed regardless of
// how damaged the brain is. In DQ we treat the brain in three bands:
//
//   damage < 20%               minor injury, heals slowly on its own
//   20% ≤ damage < 60%         stable; needs alkysine to recover
//   damage ≥ 60%               unsalvageable; tissue decays faster than
//                              alkysine can repair, surgery doesn't help
//
// Numbers:
//   - DQ_BRAIN_NATURAL_HEAL_CEILING: below this damage fraction, the
//     brain heals on its own at DQ_BRAIN_NATURAL_HEAL_RATE per tick.
//   - DQ_BRAIN_SALVAGE_THRESHOLD: at or above this damage fraction the
//     brain decays at DQ_BRAIN_DECAY_RATE per tick. Matches the staged
//     /datum/medical_issue/condition/brain_damage Significant boundary
//     (60% organ damage per code/modules/medical/causes/causes.dm).
//   - DQ_BRAIN_DECAY_RATE: damage added per organ tick once over the
//     salvage threshold. Calibrated so a patient at 70% damage with NO
//     alkysine takes ~5 minutes to die from this alone; alkysine slows
//     but doesn't reverse it.
//   - DQ_ALKYSINE_HEAL_PER_REMOVED: brainloss reduction per `removed`
//     of alkysine when the brain is below the salvage threshold.
//     Matches the upstream -8/removed; we only nerf the high-damage case.

#define DQ_BRAIN_NATURAL_HEAL_CEILING 0.2
#define DQ_BRAIN_NATURAL_HEAL_RATE 0.05
#define DQ_BRAIN_SALVAGE_THRESHOLD 0.6
#define DQ_BRAIN_DECAY_RATE 0.4
// Terminal-decay threshold: above this, the brain is degenerating
// fast enough that no combination of medication can keep up. Even
// peak synaptizine + alkysine fails. ~90% of max_damage in code, but
// configurable here.
#define DQ_BRAIN_TERMINAL_THRESHOLD 0.9
#define DQ_BRAIN_TERMINAL_DECAY_RATE 2.5
#define DQ_ALKYSINE_HEAL_PER_REMOVED 8

/// Called from /datum/reagent/alkysine/affect_blood. Splits the chem's
/// effect into below-threshold (heal) and above-threshold (slow decay)
/// halves. Above the salvage threshold the chem still reduces brainloss,
/// but the per-tick organ decay (see brain.process below) outpaces it.
/proc/dq_alkysine_brain_effect(mob/living/carbon/M, removed, chem_effective)
	if(!ishuman(M))
		// Non-human carbons (vore prey, monkeys) keep the simple flat
		// heal — they don't have internal organs for the threshold check.
		M.adjustBrainLoss(-DQ_ALKYSINE_HEAL_PER_REMOVED * removed * chem_effective)
		return
	var/mob/living/carbon/human/H = M
	var/obj/item/organ/internal/brain/B = H.internal_organs_by_name[O_BRAIN]
	if(!B || B.robotic >= ORGAN_ROBOT)
		// Robotic brains shrug off chemistry, but we leave the mob's
		// general brainloss alone — the upstream behaviour (no-op for
		// robotic brains) is preserved.
		return
	if(B.damage < B.max_damage * DQ_BRAIN_SALVAGE_THRESHOLD)
		// Below the salvage threshold: full healing. Matches the
		// upstream value precisely so a player on alkysine for a mild
		// concussion still recovers at the rate they're used to.
		H.adjustBrainLoss(-DQ_ALKYSINE_HEAL_PER_REMOVED * removed * chem_effective)
		return
	// Above the threshold: the chem still scrubs some brainloss, but
	// at a fraction of the normal rate. The brain organ itself keeps
	// decaying in process() — the player sees alkysine "working" via
	// dropping brainloss while the organ damage rises around them.
	H.adjustBrainLoss(-DQ_ALKYSINE_HEAL_PER_REMOVED * 0.35 * removed * chem_effective)


// --- Organ tick ---------------------------------------------------------
//
// Each time the brain organ process()es:
//   - damage < 20%: drift down at DQ_BRAIN_NATURAL_HEAL_RATE.
//   - damage in [20%, 60%): no change here (chems / surgery handle it).
//   - damage ≥ 60%: drift up at DQ_BRAIN_DECAY_RATE. Alkysine slows
//     the rate but doesn't reverse it.

/obj/item/organ/internal/brain/process()
	. = ..()
	dq_brain_decay_tick()

/obj/item/organ/internal/brain/proc/dq_brain_decay_tick()
	if(!owner || !ishuman(owner))
		return
	if(robotic >= ORGAN_ROBOT)
		return
	var/heal_ceiling = max_damage * DQ_BRAIN_NATURAL_HEAL_CEILING
	var/decay_floor = max_damage * DQ_BRAIN_SALVAGE_THRESHOLD

	if(damage <= 0)
		// Already healed; nothing to do (and nothing to drop into the
		// negatives via the natural-heal path).
		return

	if(damage < heal_ceiling)
		// Minor injury: slow natural recovery. No chem needed.
		damage = max(0, damage - DQ_BRAIN_NATURAL_HEAL_RATE)
		return

	if(damage < decay_floor)
		// Mid-range: stable. Chem / surgery only.
		return

	var/mob/living/carbon/human/H = owner
	var/terminal_floor = max_damage * DQ_BRAIN_TERMINAL_THRESHOLD
	var/decay
	if(damage >= terminal_floor)
		// Past the terminal threshold: decay races ahead of any
		// possible medication. Even the synaptizine OD upside can't
		// keep up here — this is the unrecoverable zone by design.
		decay = DQ_BRAIN_TERMINAL_DECAY_RATE
	else
		decay = DQ_BRAIN_DECAY_RATE
		// Alkysine slows decay but doesn't reverse it. Check both
		// bloodstream and gut, same reason as dq_reagent_present —
		// ingested chems flicker through bloodstr too fast for a
		// single snapshot to catch.
		if(H.bloodstr?.has_reagent(REAGENT_ID_ALKYSINE) || H.ingested?.has_reagent(REAGENT_ID_ALKYSINE))
			decay *= 0.4
	damage = min(max_damage, damage + decay)
	// OD boosts can subtract from the decay each tick — synaptizine
	// overdose pushes brain damage back below the salvage threshold,
	// but ONLY in the 60–90% band. Past the terminal floor the
	// repair gets eaten by the accelerated decay above, by design.
	// The boost is scaled by the OD condition's severity automatically.
	if(damage < terminal_floor)
		var/repair = H.dq_od_boost_value("brain_repair")
		if(repair > 0)
			damage = max(0, damage - repair)
