// Balance harness scenarios (see _balance_harness.dm). Each table below is the
// single source of both what a scenario runs and the keys it promises.

// --- Baseline -------------------------------------------------------------------

#define BALANCE_BASELINE_SECONDS 60

/// The control every other scenario is read against: the air where the test
/// mobs stand, and an unhurt human left alone for a minute. If this human
/// passes out or builds oxygen debt, so does every patient in the other
/// scenarios, whatever their injury.
/datum/balance_scenario/baseline
	id = "baseline"
	description = "Control: the site's air and an unhurt human over 60 s"

TYPE_TABLE(/datum/balance_scenario/baseline, balance_expected_keys, list( \
	"baseline.site.pressure_kpa", \
	"baseline.site.o2_share", \
	"baseline.healthy.consciousness_after_first_life", \
	"baseline.healthy.sleeping_after_first_life", \
	"baseline.healthy.time_to_unconscious_s", \
	"baseline.healthy.ventilation_end", \
	"baseline.healthy.oxygenation_end", \
	"baseline.healthy.breath_quality_end", \
	"baseline.healthy.oxygen_debt_end", \
	"baseline.healthy.dead", \
))

/datum/balance_scenario/baseline/Run()
	var/datum/gas_mixture/air = site.return_air()
	var/total_moles = air?.total_moles()
	record("baseline.site.pressure_kpa", air?.return_pressure(), "kPa")
	record("baseline.site.o2_share", total_moles ? air.get_moles(GAS_O2) / total_moles : null, "share")
	begin_trial()
	var/mob/living/carbon/human/H = spawn_thing(/mob/living/carbon/human)
	live(H)
	record("baseline.healthy.consciousness_after_first_life", H.body.get_consciousness(), "points")
	record("baseline.healthy.sleeping_after_first_life", H.status_units(STAT_SLEEPING), "ticks")
	var/list/afflictions = list()
	for(var/datum/affliction/A as anything in H.body.afflictions)
		afflictions += "[A.type] ([round(A.severity, 0.1)])"
	note("healthy human after one Life: stat [H.stat], consciousness [H.body.get_consciousness()], pain [H.current_pain()], sleeping [H.status_units(STAT_SLEEPING)], paralysis [H.status_units(STAT_PARALYZED)], afflictions: [length(afflictions) ? jointext(afflictions, ", ") : "none"]")
	var/unconscious_at = is_down(H) ? BALANCE_LIFE_SECONDS : null
	var/elapsed = BALANCE_LIFE_SECONDS
	while(elapsed < BALANCE_BASELINE_SECONDS && !is_dead(H))
		live(H)
		elapsed += BALANCE_LIFE_SECONDS
		if(isnull(unconscious_at) && is_down(H))
			unconscious_at = elapsed
	record("baseline.healthy.time_to_unconscious_s", unconscious_at, "s")
	record("baseline.healthy.ventilation_end", H.body.ventilation(), "fraction")
	record("baseline.healthy.oxygenation_end", H.body.oxygenation(), "SpO2")
	record("baseline.healthy.breath_quality_end", H.body.physiology?.breath_quality, "fraction")
	record("baseline.healthy.oxygen_debt_end", H.oxygen_debt(), "debt")
	record("baseline.healthy.dead", is_dead(H) ? 1 : 0)
	cleanup()

// --- Time to kill ---------------------------------------------------------------

/// Seconds between hits when a weapon doesn't say: one click.
#define BALANCE_TTK_CLICK_SECONDS (DEFAULT_ATTACK_COOLDOWN / (1 SECONDS))
/// Longest a TTK trial runs before calling it "never".
#define BALANCE_TTK_CAP_SECONDS 180
/// Most hits a TTK trial lands before calling it "never".
#define BALANCE_TTK_MAX_HITS 200

/// Time-to-crit and time-to-kill for a representative weapon set against
/// armoured and unarmoured targets. Every hit is injure_by() at the torso with
/// the weapon's own injury kind, damage and armour penetration, so the worn
/// armour soak applies exactly as in play; Life() runs between hits.
/datum/balance_scenario/ttk
	id = "ttk"
	description = "Time to crit and to kill per weapon and target (injure_by with the real armour soak)"

/// id -> list(class, path, amount source). Amount sources: "force" (a melee
/// swing), "throwforce" (thrown), "damage" (a projectile).
TYPE_TABLE_DECLARE(/datum/balance_scenario/ttk, balance_ttk_weapons, list( \
	"combat_knife" = list("melee", /obj/item/material/knife/tacknife/combatknife, "force"), \
	"classic_baton" = list("melee", /obj/item/melee/classic_baton, "force"), \
	"toolbox" = list("melee", /obj/item/storage/toolbox, "force"), \
	"spear" = list("melee", /obj/item/material/twohanded/spear, "force"), \
	"stun_baton" = list("melee", /obj/item/melee/baton, "force"), \
	"energy_sword" = list("melee", /obj/item/melee/energy/sword, "force"), \
	"pistol_9mm" = list("ballistic", /obj/item/projectile/bullet/pistol, "damage"), \
	"pistol_45" = list("ballistic", /obj/item/projectile/bullet/pistol/medium, "damage"), \
	"rifle_545" = list("ballistic", /obj/item/projectile/bullet/rifle/a545, "damage"), \
	"rifle_762" = list("ballistic", /obj/item/projectile/bullet/rifle/a762, "damage"), \
	"shotgun_slug" = list("ballistic", /obj/item/projectile/bullet/shotgun, "damage"), \
	"laser" = list("laser", /obj/item/projectile/beam, "damage"), \
	"laser_mid" = list("laser", /obj/item/projectile/beam/midlaser, "damage"), \
	"laser_heavy" = list("laser", /obj/item/projectile/beam/heavylaser, "damage"), \
	"xray" = list("laser", /obj/item/projectile/beam/xray, "damage"), \
	"taser_electrode" = list("energy", /obj/item/projectile/energy/electrode, "damage"), \
	"stun_beam" = list("energy", /obj/item/projectile/beam/stun, "damage"), \
	"plasma_stun" = list("energy", /obj/item/projectile/energy/plasmastun, "damage"), \
	"phase_wave" = list("energy", /obj/item/projectile/energy/phase, "damage"), \
	"thrown_toolbox" = list("thrown", /obj/item/storage/toolbox, "throwforce"), \
	"thrown_spear" = list("thrown", /obj/item/material/twohanded/spear, "throwforce"), \
	"thrown_star" = list("thrown", /obj/item/material/star, "throwforce"), \
	"thrown_shard" = list("thrown", /obj/item/material/shard, "throwforce"), \
))

/// id -> list(mob path, worn item paths...).
TYPE_TABLE_DECLARE(/datum/balance_scenario/ttk, balance_ttk_targets, list( \
	"unarmoured" = list(/mob/living/carbon/human), \
	"security_vest" = list(/mob/living/carbon/human, /obj/item/clothing/suit/armor/vest/security), \
	"riot_suit" = list(/mob/living/carbon/human, /obj/item/clothing/suit/armor/riot, /obj/item/clothing/head/helmet/riot), \
	"hardsuit" = list(/mob/living/carbon/human, /obj/item/clothing/suit/space/void/security), \
	"cyborg" = list(/mob/living/silicon/robot), \
	"protean" = list(/mob/living/carbon/human/protean), \
))

TYPE_TABLE_DECLARE(/datum/balance_scenario/ttk, balance_ttk_results, list("hits_to_crit", "time_to_crit_s", "hits_to_kill", "time_to_kill_s", "first_hit_applied"))

/datum/balance_scenario/ttk/expected_keys()
	. = list()
	for(var/weapon_id in TYPE_TABLE_GET(src, balance_ttk_weapons))
		. += "ttk.[weapon_id].raw_damage"
		. += "ttk.[weapon_id].seconds_per_hit"
		for(var/target_id in TYPE_TABLE_GET(src, balance_ttk_targets))
			for(var/name in TYPE_TABLE_GET(src, balance_ttk_results))
				. += "ttk.[weapon_id].[target_id].[name]"
	for(var/target_id in TYPE_TABLE_GET(src, balance_ttk_targets))
		. += "ttk.target.[target_id].equipped"

/datum/balance_scenario/ttk/Run()
	var/list/equipped = list()
	for(var/target_id in TYPE_TABLE_GET(src, balance_ttk_targets))
		begin_trial()
		var/mob/living/probe = make_target(target_id)
		equipped[target_id] = !!probe
		record("ttk.target.[target_id].equipped", probe ? 1 : 0)
	for(var/weapon_id in TYPE_TABLE_GET(src, balance_ttk_weapons))
		for(var/target_id in TYPE_TABLE_GET(src, balance_ttk_targets))
			trial(weapon_id, target_id, equipped[target_id])
			CHECK_TICK
	cleanup()

/// Spawns target `target_id` wearing its kit, or null if the kit wouldn't go on.
/datum/balance_scenario/ttk/proc/make_target(target_id)
	var/list/spec = TYPE_TABLE_GET(src, balance_ttk_targets)[target_id]
	var/mob/living/L = spawn_thing(spec[1])
	for(var/i in 2 to length(spec))
		var/obj/item/worn = spawn_thing(spec[i])
		var/mob/living/carbon/human/H = L
		var/slot = istype(worn, /obj/item/clothing/head) ? SLOT_ID_HEAD : SLOT_ID_SUIT
		if(!istype(H) || !H.equip_to_slot_if_possible(worn, slot, disable_warning = TRUE))
			note("[target_id]: [worn.type] would not equip")
			return null
	return L

/datum/balance_scenario/ttk/proc/trial(weapon_id, target_id, target_ok)
	var/list/spec = TYPE_TABLE_GET(src, balance_ttk_weapons)[weapon_id]
	begin_trial()
	var/obj/item/weapon = spawn_thing(spec[2])
	var/amount = 0
	var/seconds_per_hit = BALANCE_TTK_CLICK_SECONDS
	switch(spec[3])
		if("force")
			amount = weapon.force
			seconds_per_hit = weapon.attackspeed / (1 SECONDS)
		if("throwforce")
			amount = weapon.throwforce
		if("damage")
			var/obj/item/projectile/P = weapon
			amount = P.damage
			var/obj/item/gun/gun_type = /obj/item/gun
			seconds_per_hit = initial(gun_type.fire_delay) / (1 SECONDS)
	record("ttk.[weapon_id].raw_damage", amount)
	record("ttk.[weapon_id].seconds_per_hit", seconds_per_hit, "s")
	var/prefix = "ttk.[weapon_id].[target_id]"
	var/mob/living/L = target_ok ? make_target(target_id) : null
	if(!L)
		for(var/name in TYPE_TABLE_GET(src, balance_ttk_results))
			record("[prefix].[name]", null)
		return
	var/zone = ishuman(L) ? BP_TORSO : null
	var/elapsed = 0
	var/next_life = BALANCE_LIFE_SECONDS
	var/hits = 0
	var/crit_hits
	var/crit_time
	var/kill_hits
	var/kill_time
	var/first_applied = 0
	while(hits < BALANCE_TTK_MAX_HITS && elapsed <= BALANCE_TTK_CAP_SECONDS && !is_dead(L))
		hits++
		var/applied = L.injure_by(weapon, amount, zone)
		if(hits == 1)
			first_applied = applied
		if(isnull(crit_hits) && is_down(L))
			crit_hits = hits
			crit_time = elapsed
		if(is_dead(L))
			kill_hits = hits
			kill_time = elapsed
			break
		elapsed += seconds_per_hit
		while(next_life <= elapsed && !is_dead(L))
			live(L)
			if(isnull(crit_hits) && is_down(L))
				crit_hits = hits
				crit_time = next_life
			if(is_dead(L))
				kill_hits = hits
				kill_time = next_life
			next_life += BALANCE_LIFE_SECONDS
	record("[prefix].hits_to_crit", crit_hits, "hits")
	record("[prefix].time_to_crit_s", crit_time, "s")
	record("[prefix].hits_to_kill", kill_hits, "hits")
	record("[prefix].time_to_kill_s", kill_time, "s")
	record("[prefix].first_hit_applied", first_applied, "points")

// --- Bleed-out ------------------------------------------------------------------

#define BALANCE_BLEED_CAP_SECONDS 1200

/// Bleed-out time for each bleeding wound type on an arm: untreated, with a
/// plain gauze roll (the roll's TREAT_WOUND_PACKING per wound), with hemostatic
/// gauze and with a tourniquet above the wound.
/datum/balance_scenario/bleedout
	id = "bleedout"
	description = "Bleed-out time per wound type: untreated, gauze, hemostatic gauze, tourniquet"

/// id -> list(wound path, initial damage: the wound's first stage).
TYPE_TABLE_DECLARE(/datum/balance_scenario/bleedout, balance_bleedout_wounds, list( \
	"cut_small" = list(/datum/affliction/wound/cut/small, 20), \
	"cut_deep" = list(/datum/affliction/wound/cut/deep, 25), \
	"cut_flesh" = list(/datum/affliction/wound/cut/flesh, 35), \
	"cut_gaping" = list(/datum/affliction/wound/cut/gaping, 50), \
	"cut_massive" = list(/datum/affliction/wound/cut/massive, 70), \
	"puncture_flesh" = list(/datum/affliction/wound/puncture/flesh, 15), \
	"puncture_gaping" = list(/datum/affliction/wound/puncture/gaping, 30), \
	"puncture_massive" = list(/datum/affliction/wound/puncture/massive, 60), \
	"bruise_huge" = list(/datum/affliction/wound/bruise, 50), \
	"arterial" = list(/datum/affliction/wound/internal_bleeding, 30), \
))

TYPE_TABLE_DECLARE(/datum/balance_scenario/bleedout, balance_bleedout_treatments, list("untreated", "gauze", "hemostatic_gauze", "tourniquet"))

TYPE_TABLE_DECLARE(/datum/balance_scenario/bleedout, balance_bleedout_results, list("bleeding_after_treatment", "time_to_unconscious_s", "time_to_death_s", "blood_fraction_end"))

/datum/balance_scenario/bleedout/expected_keys()
	. = list()
	for(var/wound_id in TYPE_TABLE_GET(src, balance_bleedout_wounds))
		for(var/treatment in TYPE_TABLE_GET(src, balance_bleedout_treatments))
			for(var/name in TYPE_TABLE_GET(src, balance_bleedout_results))
				. += "bleedout.[wound_id].[treatment].[name]"

/datum/balance_scenario/bleedout/Run()
	for(var/wound_id in TYPE_TABLE_GET(src, balance_bleedout_wounds))
		for(var/treatment in TYPE_TABLE_GET(src, balance_bleedout_treatments))
			trial(wound_id, treatment)
			CHECK_TICK
	cleanup()

/datum/balance_scenario/bleedout/proc/trial(wound_id, treatment)
	var/list/spec = TYPE_TABLE_GET(src, balance_bleedout_wounds)[wound_id]
	begin_trial()
	var/prefix = "bleedout.[wound_id].[treatment]"
	var/mob/living/carbon/human/H = spawn_thing(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	var/wound_type = spec[1]
	var/datum/affliction/wound/W = new wound_type(arm, spec[2])
	arm.add_wound(W)
	switch(treatment)
		if("gauze")
			// What a roll of gauze does to each open wound on the limb.
			for(var/datum/affliction/wound/open as anything in arm.get_wounds())
				if(!open.internal && !open.bandaged)
					open.receive_tagged_treatment(TREAT_WOUND_PACKING, 1)
			arm.update_damages()
		if("hemostatic_gauze")
			var/obj/item/stack/medical/field/hemostatic_gauze/G = spawn_thing(/obj/item/stack/medical/field/hemostatic_gauze)
			G.apply_to_limb(H, arm, null)
		if("tourniquet")
			var/obj/item/tourniquet/T = spawn_thing(/obj/item/tourniquet)
			arm.apply_tourniquet(T)
	record("[prefix].bleeding_after_treatment", (!QDELETED(W) && W.bleeding()) ? 1 : 0)
	var/unconscious_at
	var/dead_at
	var/elapsed = 0
	while(elapsed < BALANCE_BLEED_CAP_SECONDS && !is_dead(H))
		live(H)
		elapsed += BALANCE_LIFE_SECONDS
		if(isnull(unconscious_at) && is_down(H))
			unconscious_at = elapsed
		if(is_dead(H))
			dead_at = elapsed
	record("[prefix].time_to_unconscious_s", unconscious_at, "s")
	record("[prefix].time_to_death_s", dead_at, "s")
	record("[prefix].blood_fraction_end", blood_fraction(H), "fraction")

// --- Hypoxia --------------------------------------------------------------------

#define BALANCE_HYPOXIA_CAP_SECONDS 900
/// A bag-valve mask squeeze every this many seconds.
#define BALANCE_BVM_CADENCE_SECONDS 12

/// The hypoxia timeline from a failed airway, breathing or circulation:
/// unconscious, first brain lesion, brain death, death; untreated, bagged
/// with a bag-valve mask, and with CPR from a bystander.
/datum/balance_scenario/hypoxia
	id = "hypoxia"
	description = "Hypoxia timeline (unconscious, brain lesion, brain death, death) with none, BVM or CPR"

TYPE_TABLE_DECLARE(/datum/balance_scenario/hypoxia, balance_hypoxia_causes, list("airway_obstruction", "respiratory_arrest", "cardiac_arrest_vf"))

TYPE_TABLE_DECLARE(/datum/balance_scenario/hypoxia, balance_hypoxia_interventions, list("none", "bvm", "cpr"))

TYPE_TABLE_DECLARE(/datum/balance_scenario/hypoxia, balance_hypoxia_results, list("time_to_unconscious_s", "time_to_brain_lesion_s", "time_to_brain_death_s", "time_to_death_s", "oxygen_debt_end", "brain_damage_end"))

/datum/balance_scenario/hypoxia/expected_keys()
	. = list()
	for(var/cause in TYPE_TABLE_GET(src, balance_hypoxia_causes))
		for(var/intervention in TYPE_TABLE_GET(src, balance_hypoxia_interventions))
			for(var/name in TYPE_TABLE_GET(src, balance_hypoxia_results))
				. += "hypoxia.[cause].[intervention].[name]"

/datum/balance_scenario/hypoxia/Run()
	for(var/cause in TYPE_TABLE_GET(src, balance_hypoxia_causes))
		for(var/intervention in TYPE_TABLE_GET(src, balance_hypoxia_interventions))
			trial(cause, intervention)
			CHECK_TICK
	cleanup()

/datum/balance_scenario/hypoxia/proc/trial(cause, intervention)
	begin_trial()
	var/prefix = "hypoxia.[cause].[intervention]"
	var/mob/living/carbon/human/H = spawn_thing(/mob/living/carbon/human)
	switch(cause)
		if("airway_obstruction")
			H.body.afflict(/datum/affliction/airway_obstruction)
		if("respiratory_arrest")
			H.body.afflict(/datum/affliction/respiratory_arrest)
		if("cardiac_arrest_vf")
			H.induce_arrhythmia(CARDIAC_RHYTHM_VF)
	var/obj/item/bag_valve_mask/bvm
	var/mob/living/carbon/human/rescuer
	switch(intervention)
		if("bvm")
			bvm = spawn_thing(/obj/item/bag_valve_mask)
		if("cpr")
			rescuer = spawn_thing(/mob/living/carbon/human)
	var/cpr_cadence = CPR_COMPRESSION_WINDOW / (1 SECONDS)
	var/next_bvm = 0
	var/next_cpr = 0
	var/unconscious_at
	var/lesion_at
	var/brain_dead_at
	var/dead_at
	var/elapsed = 0
	while(elapsed < BALANCE_HYPOXIA_CAP_SECONDS && !is_dead(H))
		if(bvm && elapsed >= next_bvm)
			bvm.apply_ventilation(H)
			next_bvm += BALANCE_BVM_CADENCE_SECONDS
		if(rescuer && elapsed >= next_cpr)
			H.perform_cpr(rescuer)
			next_cpr += cpr_cadence
		live(H)
		elapsed += BALANCE_LIFE_SECONDS
		var/obj/item/organ/internal/brain/B = brain_of(H)
		if(isnull(unconscious_at) && is_down(H))
			unconscious_at = elapsed
		if(isnull(lesion_at) && B?.damage > 0)
			lesion_at = elapsed
		if(isnull(brain_dead_at) && (!B || B.is_brain_dead()))
			brain_dead_at = elapsed
		if(is_dead(H))
			dead_at = elapsed
	var/obj/item/organ/internal/brain/final_brain = brain_of(H)
	record("[prefix].time_to_unconscious_s", unconscious_at, "s")
	record("[prefix].time_to_brain_lesion_s", lesion_at, "s")
	record("[prefix].time_to_brain_death_s", brain_dead_at, "s")
	record("[prefix].time_to_death_s", dead_at, "s")
	record("[prefix].oxygen_debt_end", QDELETED(H) ? null : H.oxygen_debt(), "debt")
	record("[prefix].brain_damage_end", final_brain ? final_brain.damage : null, "points")

// --- Treatment efficacy ---------------------------------------------------------

#define BALANCE_TREAT_CAP_SECONDS 600
/// A condition counts as treated once it's down to this share of its start.
#define BALANCE_TREATED_SHARE 0.1
#define BALANCE_TREAT_SNAPSHOT_SECONDS 120

/// Time to treat standard conditions with the standard chems (a dose in the
/// blood at t=0), against the same condition left alone, plus whether the
/// standard tools resolve their condition in one application.
/datum/balance_scenario/treatment
	id = "treatment"
	description = "Time to treat standard conditions with standard chems, and single-use tool efficacy"

/// condition -> list(treatment -> reagent id or null for the untreated control, dose).
TYPE_TABLE_DECLARE(/datum/balance_scenario/treatment, balance_treatment_conditions, list( \
	"trauma_40" = list("none" = null, "bicaridine" = list(REAGENT_ID_BICARIDINE, 15), "tricordrazine" = list(REAGENT_ID_TRICORDRAZINE, 15)), \
	"burn_40" = list("none" = null, "kelotane" = list(REAGENT_ID_KELOTANE, 15), "dermaline" = list(REAGENT_ID_DERMALINE, 15)), \
	"toxin_30" = list("none" = null, "dylovene" = list(REAGENT_ID_ANTITOXIN, 15)), \
	"oxygen_debt_40" = list("none" = null, "dexalin" = list(REAGENT_ID_DEXALIN, 15)), \
	"brain_30" = list("none" = null, "alkysine" = list(REAGENT_ID_ALKYSINE, 10)), \
	"heart_20" = list("none" = null, "peridaxon" = list(REAGENT_ID_PERIDAXON, 10)), \
	"pain_60" = list("none" = null, "tramadol" = list(REAGENT_ID_TRAMADOL, 10)), \
))

TYPE_TABLE_DECLARE(/datum/balance_scenario/treatment, balance_treatment_tools, list("hemostatic_gauze_stops_bleed", "airway_kit_clears_obstruction", "defibrillator_converts_vf", "tourniquet_stops_arterial_bleed"))

TYPE_TABLE_DECLARE(/datum/balance_scenario/treatment, balance_treatment_results, list("start", "remaining_share_at_120s", "time_to_treated_s"))

/datum/balance_scenario/treatment/expected_keys()
	. = list()
	var/list/conditions = TYPE_TABLE_GET(src, balance_treatment_conditions)
	for(var/condition in conditions)
		for(var/treatment in conditions[condition])
			for(var/name in TYPE_TABLE_GET(src, balance_treatment_results))
				. += "treatment.[condition].[treatment].[name]"
	for(var/tool in TYPE_TABLE_GET(src, balance_treatment_tools))
		. += "treatment.tool.[tool]"

/datum/balance_scenario/treatment/Run()
	var/list/conditions = TYPE_TABLE_GET(src, balance_treatment_conditions)
	for(var/condition in conditions)
		var/list/treatments = conditions[condition]
		for(var/treatment in treatments)
			trial(condition, treatment, treatments[treatment])
			CHECK_TICK
	for(var/tool in TYPE_TABLE_GET(src, balance_treatment_tools))
		record("treatment.tool.[tool]", tool_trial(tool) ? 1 : 0, "resolved")
	cleanup()

/// Gives `H` condition `condition`.
/datum/balance_scenario/treatment/proc/inflict(mob/living/carbon/human/H, condition)
	switch(condition)
		if("trauma_40")
			H.injure(INJURY_BLUNT, 40, BP_TORSO)
		if("burn_40")
			H.injure(INJURY_BURN, 40, BP_TORSO)
		if("toxin_30")
			H.injure(INJURY_TOXIN, 30)
		if("oxygen_debt_40")
			H.add_oxygen_debt(40, "balance harness")
		if("brain_30")
			H.injure(INJURY_NEURAL, 30, H.organ_in(O_BRAIN))
		if("heart_20")
			H.injure(INJURY_BLUNT, 20, H.organ_in(O_HEART))
		if("pain_60")
			H.injure(INJURY_PAIN, 60)

/// How much of `condition` `H` still has.
/datum/balance_scenario/treatment/proc/measure(mob/living/carbon/human/H, condition)
	if(QDELETED(H))
		return 0
	switch(condition)
		if("trauma_40")
			return H.injury_load(INJURY_CATEGORY_PHYSICAL)
		if("burn_40")
			return H.injury_load(INJURY_CATEGORY_THERMAL)
		if("toxin_30")
			return H.injury_load(INJURY_CATEGORY_TOXIC)
		if("oxygen_debt_40")
			return H.oxygen_debt()
		if("brain_30")
			var/obj/item/organ/internal/brain/B = H.organ_in(O_BRAIN)
			return B ? B.damage : 0
		if("heart_20")
			var/obj/item/organ/internal/heart/heart = H.organ_in(O_HEART)
			return heart ? heart.damage : 0
		if("pain_60")
			return H.current_pain()
	return 0

/datum/balance_scenario/treatment/proc/trial(condition, treatment, list/dose)
	begin_trial()
	var/prefix = "treatment.[condition].[treatment]"
	var/mob/living/carbon/human/H = spawn_thing(/mob/living/carbon/human)
	inflict(H, condition)
	live(H) // let the body turn the harm into afflictions before measuring
	var/start = measure(H, condition)
	if(dose)
		H.bloodstr.add_reagent(dose[1], dose[2])
	record("[prefix].start", start, "points")
	var/treated_at
	var/share_at_snapshot
	var/elapsed = 0
	while(elapsed < BALANCE_TREAT_CAP_SECONDS && !is_dead(H))
		live(H)
		elapsed += BALANCE_LIFE_SECONDS
		var/now = measure(H, condition)
		if(elapsed == BALANCE_TREAT_SNAPSHOT_SECONDS)
			share_at_snapshot = start > 0 ? now / start : 0
		if(isnull(treated_at) && now <= start * BALANCE_TREATED_SHARE)
			treated_at = elapsed
			if(elapsed >= BALANCE_TREAT_SNAPSHOT_SECONDS)
				break
	if(isnull(share_at_snapshot))
		share_at_snapshot = start > 0 ? measure(H, condition) / start : 0
	record("[prefix].remaining_share_at_120s", share_at_snapshot, "share")
	record("[prefix].time_to_treated_s", treated_at, "s")

/// Does one application of `tool` resolve its condition?
/datum/balance_scenario/treatment/proc/tool_trial(tool)
	begin_trial()
	var/mob/living/carbon/human/H = spawn_thing(/mob/living/carbon/human)
	switch(tool)
		if("hemostatic_gauze_stops_bleed")
			var/obj/item/organ/external/arm = H.get_organ(BP_R_ARM)
			var/datum/affliction/wound/W = new /datum/affliction/wound/cut/deep(arm, 25)
			arm.add_wound(W)
			var/obj/item/stack/medical/field/hemostatic_gauze/G = spawn_thing(/obj/item/stack/medical/field/hemostatic_gauze)
			G.apply_to_limb(H, arm, null)
			return QDELETED(W) || !W.bleeding()
		if("airway_kit_clears_obstruction")
			var/datum/affliction/airway_obstruction/A = H.body.afflict(/datum/affliction/airway_obstruction)
			var/obj/item/airway_kit/kit = spawn_thing(/obj/item/airway_kit)
			kit.clear_airway(H)
			return QDELETED(A) || !A.blocks_airway()
		if("defibrillator_converts_vf")
			H.induce_arrhythmia(CARDIAC_RHYTHM_VF)
			H.defibrillate_heart()
			return H.has_cardiac_output()
		if("tourniquet_stops_arterial_bleed")
			var/obj/item/organ/external/leg = H.get_organ(BP_L_LEG)
			var/datum/affliction/wound/W = new /datum/affliction/wound/internal_bleeding(leg, 30)
			leg.add_wound(W)
			var/obj/item/tourniquet/T = spawn_thing(/obj/item/tourniquet)
			leg.apply_tourniquet(T)
			return QDELETED(W) || !W.bleeding()
	return FALSE

// --- Digestion ------------------------------------------------------------------

#define BALANCE_DIGEST_SECONDS 60
/// Harm given to the prey before a heal-belly trial, so healing has something to do.
#define BALANCE_DIGEST_HEAL_INJURY 30

/// What each belly mode does to a human prey (and its predator) over 60 s:
/// the belly cycles at the mob Life cadence and both mobs live.
/datum/balance_scenario/digestion
	id = "digestion"
	description = "Totals per belly mode over 60 s"

TYPE_TABLE_DECLARE(/datum/balance_scenario/digestion, balance_digestion_modes, list( \
	"hold" = DM_HOLD, \
	"digest" = DM_DIGEST, \
	"absorb" = DM_ABSORB, \
	"drain" = DM_DRAIN, \
	"shrink" = DM_SHRINK, \
	"grow" = DM_GROW, \
	"size_steal" = DM_SIZE_STEAL, \
	"heal" = DM_HEAL, \
))

TYPE_TABLE_DECLARE(/datum/balance_scenario/digestion, balance_digestion_results, list("prey_injury_delta", "prey_nutrition_delta", "pred_nutrition_delta", "prey_size_delta", "prey_absorbed", "prey_dead"))

/datum/balance_scenario/digestion/expected_keys()
	. = list()
	for(var/mode_id in TYPE_TABLE_GET(src, balance_digestion_modes))
		for(var/name in TYPE_TABLE_GET(src, balance_digestion_results))
			. += "digestion.[mode_id].[name]"

/datum/balance_scenario/digestion/Run()
	for(var/mode_id in TYPE_TABLE_GET(src, balance_digestion_modes))
		trial(mode_id)
		CHECK_TICK
	cleanup()

/datum/balance_scenario/digestion/proc/trial(mode_id)
	begin_trial()
	var/prefix = "digestion.[mode_id]"
	var/mob/living/carbon/human/pred = spawn_thing(/mob/living/carbon/human)
	var/mob/living/carbon/human/prey = spawn_thing(/mob/living/carbon/human)
	pred.init_vore(TRUE)
	var/obj/belly/B = pred.vore_selected
	if(!B)
		note("[mode_id]: the predator has no belly")
		for(var/name in TYPE_TABLE_GET(src, balance_digestion_results))
			record("[prefix].[name]", null)
		return
	pred.set_nutrition(300)
	prey.set_nutrition(300)
	if(mode_id == "heal")
		prey.injure(INJURY_BLUNT, BALANCE_DIGEST_HEAL_INJURY, BP_TORSO)
		live(prey)
	B.digest_mode = TYPE_TABLE_GET(src, balance_digestion_modes)[mode_id]
	B.nom_atom(prey, pred)
	if(prey.loc != B)
		note("[mode_id]: the prey would not go in")
	var/injury_before = total_injury(prey)
	var/pred_nutrition_before = pred.nutrition
	var/prey_nutrition_before = prey.nutrition
	var/prey_size_before = prey.size_multiplier
	var/elapsed = 0
	while(elapsed < BALANCE_DIGEST_SECONDS)
		if(!QDELETED(B))
			B.belly_cycle(BALANCE_LIFE_SECONDS)
		live(pred)
		live(prey)
		elapsed += BALANCE_LIFE_SECONDS
	var/prey_gone = QDELETED(prey)
	record("[prefix].prey_injury_delta", prey_gone ? null : total_injury(prey) - injury_before, "points")
	record("[prefix].prey_nutrition_delta", prey_gone ? null : prey.nutrition - prey_nutrition_before, "nutrition")
	record("[prefix].pred_nutrition_delta", pred.nutrition - pred_nutrition_before, "nutrition")
	record("[prefix].prey_size_delta", prey_gone ? null : prey.size_multiplier - prey_size_before, "size")
	record("[prefix].prey_absorbed", (!prey_gone && prey.absorbed) ? 1 : 0)
	record("[prefix].prey_dead", is_dead(prey) ? 1 : 0)
	if(!QDELETED(B))
		B.release_all_contents(TRUE, TRUE)

// --- Stasis ---------------------------------------------------------------------

#define BALANCE_STASIS_CAP_SECONDS 3600

/// How much stasis extends the survival of a patient bleeding out from an
/// arterial bleed and a massive cut, which gauze can't stop.
/datum/balance_scenario/stasis
	id = "stasis"
	description = "Survival time of a dying patient without and with stasis"

/// id -> stasis modifier path (null: none).
TYPE_TABLE_DECLARE(/datum/balance_scenario/stasis, balance_stasis_levels, list( \
	"none" = null, \
	"light" = /datum/body_effect/stasis/light, \
	"moderate" = /datum/body_effect/stasis/moderate, \
	"deep" = /datum/body_effect/stasis/deep, \
))

TYPE_TABLE_DECLARE(/datum/balance_scenario/stasis, balance_stasis_results, list("time_to_unconscious_s", "time_to_death_s", "survival_multiplier"))

/datum/balance_scenario/stasis/expected_keys()
	. = list()
	for(var/level in TYPE_TABLE_GET(src, balance_stasis_levels))
		for(var/name in TYPE_TABLE_GET(src, balance_stasis_results))
			. += "stasis.[level].[name]"

/datum/balance_scenario/stasis/Run()
	var/baseline
	for(var/level in TYPE_TABLE_GET(src, balance_stasis_levels))
		var/died_at = trial(level)
		if(level == "none")
			baseline = died_at
		var/multiplier = null
		if(baseline && died_at)
			multiplier = died_at / baseline
		record("stasis.[level].survival_multiplier", multiplier, "x")
		CHECK_TICK
	cleanup()

/datum/balance_scenario/stasis/proc/trial(level)
	begin_trial()
	var/prefix = "stasis.[level]"
	var/mob/living/carbon/human/H = spawn_thing(/mob/living/carbon/human)
	var/obj/item/organ/external/chest = H.get_organ(BP_TORSO)
	var/obj/item/organ/external/leg = H.get_organ(BP_L_LEG)
	chest.add_wound(new /datum/affliction/wound/internal_bleeding(chest, 30))
	leg.add_wound(new /datum/affliction/wound/cut/massive(leg, 70))
	var/stasis_type = TYPE_TABLE_GET(src, balance_stasis_levels)[level]
	if(stasis_type)
		H.set_stasis(stasis_type, src)
	var/unconscious_at
	var/dead_at
	var/elapsed = 0
	while(elapsed < BALANCE_STASIS_CAP_SECONDS && !is_dead(H))
		live(H)
		elapsed += BALANCE_LIFE_SECONDS
		if(isnull(unconscious_at) && is_down(H))
			unconscious_at = elapsed
		if(is_dead(H))
			dead_at = elapsed
	if(!QDELETED(H))
		H.set_stasis(null, src)
	record("[prefix].time_to_unconscious_s", unconscious_at, "s")
	record("[prefix].time_to_death_s", dead_at, "s")
	return dead_at

#undef BALANCE_BASELINE_SECONDS
#undef BALANCE_TTK_CLICK_SECONDS
#undef BALANCE_TTK_CAP_SECONDS
#undef BALANCE_TTK_MAX_HITS
#undef BALANCE_BLEED_CAP_SECONDS
#undef BALANCE_HYPOXIA_CAP_SECONDS
#undef BALANCE_BVM_CADENCE_SECONDS
#undef BALANCE_TREAT_CAP_SECONDS
#undef BALANCE_TREATED_SHARE
#undef BALANCE_TREAT_SNAPSHOT_SECONDS
#undef BALANCE_DIGEST_SECONDS
#undef BALANCE_DIGEST_HEAL_INJURY
#undef BALANCE_STASIS_CAP_SECONDS

// Shared with _balance_harness.dm, the first file of the harness.
#undef BALANCE_RESULTS_FILE
#undef BALANCE_SEED
#undef BALANCE_LIFE_SECONDS
