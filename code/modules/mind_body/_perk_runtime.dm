// Runtime perk record.
//
// At character spawn the mind/body apply hook grants every chosen perk via
// /datum/perk/grant(); the base grant() stamps the perk's type into this set so any
// gameplay system can ask `has_perk()` at the exact moment it matters — an unarmed
// swing, a grab resist, a crit entry, a hazard tick. `var_changes` perks still bake
// their stat mods into the synthesized species as before; this set is what the
// conditional / always-on perks read off.

/mob/living
	/// Set of granted perk type paths (path -> TRUE). Lazy — most mobs have none.
	var/list/granted_perks
	/// Aggregated multiplicative perk modifiers (fx hook -> product). Lazy.
	var/list/perk_fx_mult
	/// Aggregated additive perk modifiers (fx hook -> sum). Lazy.
	var/list/perk_fx_add

/// TRUE when this mob has the given perk. Pass a /datum/perk type path.
/mob/living/proc/has_perk(perk_path)
	return granted_perks?[perk_path]

/// Multiplicative perk modifier for an fx hook. Default 1 (no perks contribute).
/// A site applies it as `value *= perk_mult(DQ_PERK_FX_FOO)`.
/mob/living/proc/perk_mult(hook)
	return perk_fx_mult?[hook] || 1

/// Additive perk modifier for an fx hook. Default 0. Used for flat bonuses and summed
/// probabilities — `prob(perk_add(DQ_PERK_FX_EVADE_MELEE))`.
/mob/living/proc/perk_add(hook)
	return perk_fx_add?[hook] || 0

/mob/living/proc/grant_perk(perk_path)
	LAZYSET(granted_perks, perk_path, TRUE)

/mob/living/proc/revoke_perk(perk_path)
	if(!granted_perks)
		return
	granted_perks -= perk_path
	UNSETEMPTY(granted_perks)

/// Fold one perk's declared fx modifiers into the per-mob cache (called on grant).
/mob/living/proc/fold_perk_fx(datum/perk/P)
	if(P.fx_mult)
		LAZYINITLIST(perk_fx_mult)
		for(var/hook in P.fx_mult)
			perk_fx_mult[hook] = (perk_fx_mult[hook] || 1) * P.fx_mult[hook]
	if(P.fx_add)
		LAZYINITLIST(perk_fx_add)
		for(var/hook in P.fx_add)
			perk_fx_add[hook] = (perk_fx_add[hook] || 0) + P.fx_add[hook]

/// Rebuild the fx cache from the current granted set (called on the rare revoke path).
/mob/living/proc/rebuild_perk_fx()
	perk_fx_mult = null
	perk_fx_add = null
	for(var/path in granted_perks)
		var/datum/perk/P = GLOB.all_perks?[path]
		if(P)
			fold_perk_fx(P)

// ── Crit-survival perks (Vigor: Last Stand) ─────────────────────────────────────

/mob/living
	/// world.time the auto crit reactions may next fire.
	var/dq_second_wind_at = 0
	var/dq_adrenal_at = 0
	/// Immovable: while world.time is below this, hard CC (Stun/Weaken) is shrugged off.
	var/dq_cc_immune_until = 0
	/// Tick the current Immovable window opened — lets same-tick CC (a paired stun+knockdown) through.
	var/dq_cc_window_set_at = 0
	/// Tenacious: world.time of the last stun, to tell a fight's first stun from later ones.
	var/dq_last_stun_at = 0

/// Extra negative crit-point room from crit-survival perks — you stay conscious longer.
/mob/living/proc/dq_crit_point_bonus()
	. = 0
	if(has_perk(/datum/perk/body/vig_pain_tolerance))
		. += DQ_PERK_PAIN_TOLERANCE_HP
	if(has_perk(/datum/perk/body/vig_survivor))
		. += DQ_PERK_SURVIVOR_HP
	if(has_perk(/datum/perk/body/vig_deaths_door))
		. += DQ_PERK_DEATHS_DOOR_HP

/// Incoming-damage multiplier from Undying / Unkillable. 1 when neither applies. Undying
/// scales mitigation up as health falls past half; both flat-halve once you are in crit.
/mob/living/proc/dq_crit_damage_mult()
	var/maxhp = getMaxHealth()
	if(maxhp <= 0)
		return 1
	if(health <= 0)
		if(has_perk(/datum/perk/body/vig_unkillable) || has_perk(/datum/perk/body/vig_undying))
			return 0.5
		return 1
	if(has_perk(/datum/perk/body/vig_undying))
		var/frac = clamp(health / (maxhp * 0.5), 0, 1) // 1 at half-health, 0 at crit
		return 1 - 0.5 * (1 - frac)
	return 1

/// Juice Box: a character's effective maximum blood volume.
/mob/living/carbon/human/proc/dq_max_blood()
	return species.blood_volume * perk_mult(DQ_PERK_FX_MAX_BLOOD)

/// Quick Reactions: the lockout after dropping/whiffing a guard, halved if you have it.
/mob/living/proc/dq_guard_lock(base)
	if(has_perk(/datum/perk/body/spd_quick_reactions))
		return round(base * 0.5)
	return base

/// Always Ready: the attack lockout imposed after taking a step, halved if you have it.
/mob/living/proc/dq_move_attack_lock()
	if(has_perk(/datum/perk/body/spd_always_ready))
		return round(DQ_MOVE_ATTACK_LOCK * 0.5)
	return DQ_MOVE_ATTACK_LOCK

/// Immovable capstone: TRUE if a hard CC should be shrugged off right now. A new hit (a
/// later tick) opens the brief immunity window so the NEXT CC inside it is blocked; CC that
/// lands the same tick (a paired stun + knockdown) all passes through.
/mob/living/proc/dq_immovable_blocks_cc()
	if(!has_perk(/datum/perk/body/end_immovable))
		return FALSE
	if(world.time < dq_cc_immune_until && world.time > dq_cc_window_set_at)
		return TRUE
	if(world.time > dq_cc_window_set_at)
		dq_cc_window_set_at = world.time
		dq_cc_immune_until = world.time + DQ_PERK_IMMOVABLE_WINDOW
	return FALSE

/// Recovery perks (Vigor): a slow out-of-combat heal granted by Hearty, boosted by Quick
/// Healer and by Convalescent while resting. Humans have no baseline brute/burn regen, so
/// this is the whole effect — it does nothing without Hearty. Driven from the Life pass.
/mob/living/carbon/human/proc/dq_perk_regen()
	if(stat != CONSCIOUS || !has_perk(/datum/perk/body/vig_hearty))
		return
	if(world.time < last_stagger_time + DQ_PERK_REGEN_COMBAT_DELAY) // still catching your breath
		return
	if(!getBruteLoss() && !getFireLoss())
		return
	var/amt = DQ_PERK_REGEN_BASE * perk_mult(DQ_PERK_FX_REGEN) * perk_mult(DQ_PERK_FX_HEAL)
	if((resting || lying) && has_perk(/datum/perk/body/vig_convalescent))
		amt *= DQ_PERK_CONVALESCENT_MULT
	heal_overall_damage(amt, amt)

/// Auto-firing crit reactions (Second Wind, Adrenal Reserve). Driven from the Life pass.
/mob/living/carbon/human/proc/dq_check_crit_reactions()
	var/maxhp = getMaxHealth()
	if(maxhp <= 0)
		return
	if(health <= maxhp * 0.25 && has_perk(/datum/perk/body/vig_second_wind) && world.time >= dq_second_wind_at)
		dq_second_wind_at = world.time + DQ_PERK_SECOND_WIND_CD
		SetStunned(0)
		SetWeakened(0)
		// Restore across every lethal damage type so an oxy/tox death doesn't slip past it.
		heal_overall_damage(round(DQ_PERK_SECOND_WIND_HEAL * 0.5), round(DQ_PERK_SECOND_WIND_HEAL * 0.5))
		adjustOxyLoss(-DQ_PERK_SECOND_WIND_HEAL)
		adjustToxLoss(-DQ_PERK_SECOND_WIND_HEAL)
		visible_message(span_warning("\The [src] surges back from the brink with a second wind!"))
	if(health <= 0 && has_perk(/datum/perk/body/vig_adrenal) && world.time >= dq_adrenal_at)
		dq_adrenal_at = world.time + DQ_PERK_SECOND_WIND_CD
		SetStunned(0)
		SetWeakened(0)
		adjust_stamina(max_stamina)
		visible_message(span_warning("\The [src]'s body floods with adrenaline!"))
