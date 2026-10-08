// The body clock (doc/rewrite/body_migration.md, slice 1): wound healing, bleeding and blood are rates over time.
//
// Nothing here counts Life ticks. A wound carries its damage and the state that decides its rates (dressed, clamped,
// its size and age); the body integrates those rates over the time that passed, on the mob's own clock (stasis
// stops it). One work item per human runs while `body_clock_active` holds: the body raises it when a wound opens,
// changes or is treated, or when the blood is below full, and drops it when nothing heals, bleeds or refills.
// A healed wound's fade is a timer (wound_fade_due()), not something the clock polls for.
//
// Rates, per Life cycle (LIFE_CYCLE) of body time:
//   autoheal   WOUND_AUTOHEAL_PER_CYCLE x organ_regeneration_multiplier, shared by the limb's wounds (+1): a dressed or
//              small old wound under WOUND_AUTOHEAL_MAX_DAMAGE closes on its own
//   bleeding   wound damage / divisor (blood_loss_divisor(): 30.01 / species rate / BF_BLEEDING, +5 for limbs, +10 for
//              hands and feet, -5 for punctures, +5 for bruises, +10 stabilised; pressure helps)
//   arterial   damage / (divisor + 10), and the tear grows ARTERIAL_TEAR_PER_CYCLE until clotted or controlled
//   refill     BLOOD_REGEN_PER_CYCLE + BF_BLOOD_REGEN while below the species volume
//   bleed clock  a small wound's bleed_timer runs down one per cycle of bleeding

/// Integration step of the body clock. Rates are scaled by the time that actually passed, so the step length only
/// sets how often blood drips.
#define BODY_CLOCK_STEP LIFE_CYCLE
/// Natural healing of an eligible wound per Life cycle, before sharing between the limb's wounds.
#define WOUND_AUTOHEAL_PER_CYCLE 0.5
/// A wound carrying this much per merged instance won't close on its own within a round.
#define WOUND_AUTOHEAL_MAX_DAMAGE 50
/// A healed wound fades this long after it was made.
#define WOUND_FADE_DELAY (10 MINUTES)
/// Blood the body makes per Life cycle while below its volume, before BF_BLOOD_REGEN.
#define BLOOD_REGEN_PER_CYCLE 0.1
/// How much further an untreated arterial tear rips per Life cycle.
#define ARTERIAL_TEAR_PER_CYCLE 0.1
/// A move this recent counts as moving about (open wounds get dirty, broken bones jolt).
#define BODY_MOVING_WINDOW (1.5 SECONDS)
/// Below this body temperature (cryo) blood neither moves nor refills.
#define BODY_CLOCK_CRYO_TEMPERATURE 170

/// TRUE while something on the body clock has work (a wound heals or bleeds, the blood is below full): the body holds it.
STAT(/mob/living/carbon/human, body_clock_active, ANY)

/// The body clock's entries, for the human's CAPABILITIES block: `active` is STAT_BODY_CLOCK_ACTIVE.
/proc/body_clock(active)
	return every(BODY_CLOCK_STEP, then(TYPE_PROC_REF(/mob/living/carbon/human, body_clock_step)), when = active)

/mob/living/carbon/human/proc/body_clock_step(datum/act/timer/A)
	body_clock_advance(body_clock_span(A.dt))

/// The span a clock step integrates: the time since its last run, but never more than one step. A clock that was parked
/// (nothing healing or bleeding) and starts again must not integrate the idle time it slept through.
/proc/body_clock_span(dt)
	return clamp(dt, 0, BODY_CLOCK_STEP)

/// Advances the wounds and the blood by `dt` deciseconds of body time.
/mob/living/carbon/human/proc/body_clock_advance(dt)
	if(dt > 0 && is_alive())
		var/cycles = dt / LIFE_CYCLE
		wounds_advance(cycles)
		blood_advance(cycles)
	body_clock_refresh()

/// Raises or drops the clock from the body's state. Called whenever a wound or the blood changes.
/mob/living/carbon/human/proc/body_clock_refresh()
	body_hold_flag(STAT_BODY_CLOCK_ACTIVE, body_clock_has_work())

/// A reagent holder of this human changed (the vessel among them): the physiology reads the blood volume, and the clock
/// refills it.
/mob/living/carbon/human/on_reagent_change(changetype)
	. = ..()
	if(vessel && species?.blood_volume && should_have_organ(O_HEART))
		body?.note_blood_fraction(vessel.get_reagent_amount(REAGENT_ID_BLOOD) / species.blood_volume)
	body_clock_refresh()

/// The body holds (or releases) a boolean stat on its human: it is the one source of the body's activity flags.
/mob/living/carbon/human/proc/body_hold_flag(stat, on)
	if(!body)
		return
	if(on)
		hold(src, stat, null, body)
	else
		release(src, stat, body)

/mob/living/carbon/human/proc/body_clock_has_work()
	if(QDELETED(src) || !is_alive())
		return FALSE
	if(vessel && should_have_organ(O_HEART) && (pale || vessel.get_reagent_amount(REAGENT_ID_BLOOD) < species.blood_volume))
		return TRUE
	for(var/obj/item/organ/external/E as anything in organs)
		for(var/datum/affliction/wound/W as anything in E.get_wounds())
			if(W.damage > 0)
				return TRUE
	return FALSE

// --- Wounds -------------------------------------------------------------------------------

/mob/living/carbon/human/proc/wounds_advance(cycles)
	var/can_bleed = should_have_organ(O_HEART) && !(species.flags & NO_BLOOD)
	var/moving = !lying && !buckled_to() && ELAPSED_SINCE(src, l_move_time, CLOCK_WORLD) < BODY_MOVING_WINDOW
	for(var/obj/item/organ/external/E as anything in organs)
		var/list/wounds = E.get_wounds()
		if(!length(wounds))
			continue
		if(E.wounds_heal())
			var/share = WOUND_AUTOHEAL_PER_CYCLE * CONFIG_GET(number/organ_regeneration_multiplier) * cycles / (length(wounds) + 1)
			for(var/datum/affliction/wound/W as anything in wounds.Copy())
				if(W.damage > 0 && W.can_autoheal() && W.wound_damage() < WOUND_AUTOHEAL_MAX_DAMAGE)
					W.heal_damage(share)
				// Moving about gets an open wound dirty faster.
				if(moving && W.infection_check())
					W.germ_level += 1
				// A salved wound fights infection.
				if(W.germ_level > 0 && W.salved && prob(min(100, 2 * cycles)))
					W.disinfected = TRUE
					W.germ_level = 0
		if(can_bleed && !E.is_robotic())
			for(var/datum/affliction/wound/W as anything in E.get_wounds())
				W.run_bleed(cycles, W.bleeding())
		E.update_damages()
		if(E.update_damage_state())
			UpdateDamageIcon(1)

/// TRUE when wounds on this limb close on their own: not on a prosthesis or an undead limb.
/obj/item/organ/external/proc/wounds_heal()
	return !is_robotic() && !(data.get_species_flags() & UNDEAD)

/// When a healed wound may fade, in world time: at once on a prosthesis (a repaired dent is gone), ten minutes after it
/// was made on flesh.
/datum/affliction/wound/proc/wound_fade_due()
	var/obj/item/organ/external/E = location
	if(istype(E) && !E.wounds_heal())
		return 0
	return created + WOUND_FADE_DELAY

/// The wound healed to nothing on a living body: arm its fade.
/datum/affliction/wound/proc/schedule_fade()
	var/mob/living/carbon/human/H = owner
	if(!istype(H))
		return
	after(H, max(0, wound_fade_due() - scheduler_time_of(H)), TYPE_PROC_REF(/mob/living/carbon/human, fade_wound), clock = CLOCK_WORLD, with = list(src))

/// A healed wound's fade is due: it leaves the limb unless it reopened.
/mob/living/carbon/human/proc/fade_wound(datum/affliction/wound/W)
	if(QDELETED(W) || W.damage > 0 || W.owner != src)
		return
	if(scheduler_time_of(src) < W.wound_fade_due())
		W.schedule_fade() // made again by a merge since: wait for the new time
		return
	var/obj/item/organ/external/E = W.location
	if(!istype(E))
		return
	E.remove_wound(W)
	E.update_damages()
	if(E.update_damage_state())
		UpdateDamageIcon(1)

// --- Blood --------------------------------------------------------------------------------

/mob/living/carbon/human/proc/blood_advance(cycles)
	if(!vessel || !should_have_organ(O_HEART))
		return
	if(body_temperature() < BODY_CLOCK_CRYO_TEMPERATURE) // cryo: blood neither moves nor refills
		return
	var/blood_volume_raw = vessel.get_reagent_amount(REAGENT_ID_BLOOD)
	// Perfusion is the physiology's: it reads the volume (and the heart's pumping) and decides whether the tissues starve.
	body?.note_blood_fraction(species.blood_volume ? blood_volume_raw / species.blood_volume : 1)

	if(blood_volume_raw < species.blood_volume)
		var/datum/reagent/blood/B = own_blood()
		if(B)
			B.volume += (BLOOD_REGEN_PER_CYCLE + factor(BF_BLOOD_REGEN)) * cycles

	// DQ medical owns blood-loss presentation (internal_hemorrhage / hypovolemic_shock symptoms) and the physiology owns
	// its consequence (low perfusion -> oxygen debt). Here: the pale sprite cue, and the fatal collapse below the
	// survivable volume.
	if(blood_volume_raw >= species.blood_volume * species.blood_level_safe)
		if(pale)
			pale = 0
			update_icons_body()
	else
		if(!pale)
			pale = 1
			update_icons_body()
		if(blood_volume_raw < species.blood_volume * species.blood_level_fatal)
			status_at_least(STAT_PARALYZED, 3)
			status_at_least(STAT_SLEEPING, 3)
			injure(INJURY_TOXIN, (factor(BF_STABILIZATION) ? 1.5 : 3) * cycles, flags = INJURE_SILENT)
		// Without enough blood you slowly go hungry.
		if(nutrition >= 300)
			adjust_nutrition(-10 * cycles)
		else if(nutrition >= 200)
			adjust_nutrition(-3 * cycles)

	bleed(cycles)

/// The vessel's blood that is this body's own (a transfusion's donor blood is not regenerated).
/mob/living/carbon/human/proc/own_blood()
	var/datum/reagent/blood/B = locate_in_list(vessel.reagent_list, /datum/reagent/blood)
	if(B && B.data["donor"] != src)
		for(var/datum/reagent/blood/D in vessel.reagent_list)
			if(D.data["donor"] == src)
				return D
	return B

/// Loses the blood `cycles` Life cycles of bleeding cost: external bleeding drips, arterial tears bleed inside and grow.
/mob/living/carbon/human/proc/bleed(cycles)
	var/external = 0
	for(var/obj/item/organ/external/E as anything in organs)
		if(E.is_robotic() || E.flow_occluded())
			continue
		for(var/datum/affliction/wound/internal_bleeding/W in E.get_wounds())
			W.arterial_advance(cycles)
			remove_blood(internal_bleed_rate(W, E.applied_pressure) * cycles)
			if(prob(min(100, cycles)))
				custom_pain("You feel a stabbing pain in your [E.name]!", 50)
		external += external_bleed_rate(E)
	drip(external * cycles)

/// Blood per Life cycle this limb loses outside: its bleeding wounds and an open, unclamped surgical site.
/mob/living/carbon/human/proc/external_bleed_rate(obj/item/organ/external/E)
	if(E.is_robotic() || E.flow_occluded())
		return 0
	. = 0
	// D18b: an open surgical site bleeds only while the incision does (clamped, closed or bloodless sites don't).
	var/datum/affliction/surgical_incision/incision = E.get_incision()
	if(incision?.is_bleeding())
		. += 2
	var/divisor = blood_loss_divisor()
	for(var/datum/affliction/wound/W as anything in E.get_wounds())
		if(!W.bleeding())
			continue
		var/temp_bld = divisor
		if(W.damage_type == PIERCE) // gunshots and spear stabs bleed more
			temp_bld = max(temp_bld - 5, 1)
		else if(W.damage_type == BRUISE) // bruises bleed less
			temp_bld = max(temp_bld + 5, 1)
		// The farther from the vital regions, the less you bleed.
		if(E.organ_tag in list(BP_L_ARM, BP_R_ARM, BP_L_LEG, BP_R_LEG))
			temp_bld = max(temp_bld + 5, 1)
		else if(E.organ_tag in list(BP_L_HAND, BP_R_HAND, BP_L_FOOT, BP_R_FOOT))
			temp_bld = max(temp_bld + 10, 1)
		if(factor(BF_STABILIZATION)) // inaprovaline slows blood loss
			temp_bld = max(temp_bld + 10, 1)
		if(E.applied_pressure)
			if(ishuman(E.applied_pressure))
				var/mob/living/carbon/human/presser = E.applied_pressure
				presser.bloody_hands(src, 0)
			// Pressure on every wound of the limb at once: you can do nothing else, so it works well.
			var/min_eff_damage = max(0, W.damage - 10) / (temp_bld / 5) // still a little drips out
			. += max(min_eff_damage, W.damage - 30) / temp_bld
		else
			. += W.damage / temp_bld

/// Blood per Life cycle an arterial tear bleeds inside.
/mob/living/carbon/human/proc/internal_bleed_rate(datum/affliction/wound/internal_bleeding/W, applied_pressure = FALSE)
	var/temp_bld = blood_loss_divisor() + 10 // slower than an open wound
	if(factor(BF_STABILIZATION) || W.strongly_clotted())
		temp_bld = max(temp_bld + 30, 1) // stabilisers are great on internal wounds
	if(applied_pressure) // pressure on the wound helps stop arterial bleeding
		temp_bld += 30
	if(W.clamped)
		temp_bld *= 10 // a clamped tear bleeds ten times slower
	return W.damage / temp_bld

/// Blood per Life cycle the whole body loses: outside, and (with `count_internal`) inside. `only` limits it to one limb.
/mob/living/carbon/human/proc/blood_loss_rate(obj/item/organ/external/only, count_internal = FALSE)
	. = 0
	for(var/obj/item/organ/external/E as anything in (only ? list(only) : organs))
		if(E.is_robotic() || E.flow_occluded())
			continue
		. += external_bleed_rate(E)
		if(count_internal)
			for(var/datum/affliction/wound/internal_bleeding/W in E.get_wounds())
				. += internal_bleed_rate(W, E.applied_pressure)

/// The divisor of every bleed: lower bleeds more. INFINITY when the body does not bleed (BF_BLEEDING 0).
/mob/living/carbon/human/proc/blood_loss_divisor()
	var/bleeding = factor(BF_BLEEDING)
	if(bleeding <= 0)
		return INFINITY
	return 30.01 / species.bloodloss_rate / bleeding

// --- Organs (slice 3) ------------------------------------------------------------------------
// Each organ's work is organ_tick(cycles), scaled by the body time that passed: the liver straining under toxin load,
// withdrawal, a parasite growing, a tumour's effects. The clock runs while some organ has work (life_step_idle() is
// FALSE) or a limb carries germs or chemical traces; the body raises it when its organs, factors or chemicals change.
// What an organ *does for* the body is read where it is used: the heart's condition is the physiology's pump, the
// lungs' its gas exchange (physiology.dm); the kidneys clear toxin at a rate (kidney_clearance()).

/// TRUE while an organ has work on the body clock: the body holds it.
STAT(/mob/living/carbon/human, organs_active, ANY)

/// The organ clock's entries, for the human's CAPABILITIES block: `active` is STAT_ORGANS_ACTIVE.
/proc/organ_clock(active)
	return every(LIFE_CYCLE, then(TYPE_PROC_REF(/mob/living/carbon/human, organs_step)), when = active)

/mob/living/carbon/human/proc/organs_step(datum/act/timer/A)
	organs_advance(body_clock_span(A.dt) / LIFE_CYCLE)

/// Runs every organ's work for `cycles` Life cycles of body time (also a CPR cycle's extra circulation).
/mob/living/carbon/human/proc/organs_advance(cycles)
	if(cycles > 0 && is_alive())
		for(var/obj/item/organ/I as anything in internal_organ_list())
			I.organ_tick(cycles)
		for(var/obj/item/organ/external/E as anything in organs)
			if(E.germ_level || LAZYLEN(E.trace_chemicals))
				E.organ_tick(cycles)
	organs_refresh()

/mob/living/carbon/human/proc/organs_refresh()
	if(QDELETED(src))
		return
	body_hold_flag(STAT_ORGANS_ACTIVE, is_alive() && organs_have_work())

/mob/living/carbon/human/proc/organs_have_work()
	for(var/obj/item/organ/E as anything in organs)
		if(E.germ_level || LAZYLEN(E.trace_chemicals))
			return TRUE
	for(var/obj/item/organ/I as anything in internal_organ_list())
		if(!I.life_step_idle())
			return TRUE
	return FALSE
