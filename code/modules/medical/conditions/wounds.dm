// Wound afflictions — the physical damage model of an external limb.
//
// A wound is an affliction located on a limb (`location` = the
// /obj/item/organ/external). It keeps the old physical wound model: a damage
// size, a stage ladder (desc per damage band), bleeding & bleed_timer,
// bandaged / salved / clamped / disinfected, germ_level, merging and
// worsening, and autoheal. Limb integrity — get_trauma() / get_burn() — is the
// sum of the limb's wounds (cached on the limb, invalidated from sync()).
//
// Wounds are created by the limb (receive_injury -> apply_wound_damage ->
// create_wound), never through body.afflict(): a limb can carry several
// wounds of the same type. They are constructed as new type(limb, damage),
// attached with limb.add_wound() and removed with limb.remove_wound();
// detached limbs carry them in detached_afflictions like any other located
// affliction.
//
// Pain: wounds contribute NO pain themselves (pain_at_max = 0). Limb pain is
// derived from limb integrity in the humanoid plan's recompute_vitals(), the
// single source of limb pain.
//
// Treatment (the shared affliction pipeline; wounds override only
// receive_tagged_treatment() and progress()):
//  - Every mechanism in treated_by heals wound `damage`, except
//    TREAT_HEMOSTATIC, which runs down the bleed. Continuous treatment
//    (reagents) is scaled by `continuous_scale`; instant mends (kits, tools,
//    powers) share one budget across the wounds they reach.
//  - TREAT_RESTORATION heals every wound, internal ones included.
//  - Kits/bandages/ointment set the bandaged/salved/disinfected flags.
//  - Natural autoheal stays in the limb's update_wounds().

/// Bleed ticks removed per tick per unit of hemostatic treatment level.
#define WOUND_HEMOSTATIC_BLEED_RATE 5

/datum/affliction/wound
	name = "wound"
	category = "Wounds"
	clinical_description = "Physical damage to a limb."
	biology = BIOLOGY_ORGANIC
	injury_category = INJURY_CATEGORY_PHYSICAL
	progression_rate = 0
	severity_per_injury = 0
	pain_at_max = 0
	min_symptoms = 0
	max_symptoms = 0
	restoration_rate = 1
	shares_mend_budget = TRUE
	/// Multiplier on continuous (per-tick) healing of wound damage.
	var/continuous_scale = 0.5

	/// Index into `stages` of the current stage.
	var/current_stage = 0
	/// Description of the current stage ("deep cut", "healing burn", …).
	var/desc = "wound"
	/// Damage this wound carries (all merged instances together).
	var/damage = 0
	/// Ticks of bleeding left.
	var/bleed_timer = 0
	/// Above this per-wound damage the wound must be treated to stop bleeding.
	var/bleed_threshold = 30
	/// Damage of the current stage; below it the wound heals into the next.
	var/min_damage = 0
	var/bandaged = FALSE
	var/clamped = FALSE
	var/salved = FALSE
	var/disinfected = FALSE
	/// world.time the wound was made.
	var/created = 0
	/// Number of merged wounds of this type.
	var/amount = 1
	var/germ_level = 0

	// --- Defined by the wound type ---
	/// Stage ladder: desc -> minimum damage, worst first.
	var/list/stages
	/// Internal wounds (arterial bleeds) only heal through surgery.
	var/internal = FALSE
	/// Highest stage index that still bleeds.
	var/max_bleeding_stage = 0
	/// CUT, PIERCE, BRUISE or BURN.
	var/damage_type = CUT
	/// Max per-wound damage that still autoheals.
	var/autoheal_cutoff = 10
	/// The injury_category this wound reports while it carries damage.
	var/wound_category

/datum/affliction/wound/New(location, initial_damage = 0)
	..()
	wound_category = injury_category
	created = world.time
	damage = initial_damage
	init_stage(initial_damage)
	bleed_timer += initial_damage
	sync()

/datum/affliction/wound/Destroy()
	var/obj/item/organ/external/E = location
	if(istype(E))
		E.integrity_dirty = TRUE
	return ..()

/datum/affliction/wound/on_added()
	. = ..()
	sync()

/datum/affliction/wound/on_removed()
	. = ..()
	var/obj/item/organ/external/E = location
	if(istype(E))
		E.integrity_dirty = TRUE

/// Desc of stage `index`.
/datum/affliction/wound/proc/stage_desc(index)
	return stages[index]

/// Minimum damage of stage `index`.
/datum/affliction/wound/proc/stage_damage(index)
	return stages[stages[index]]

/datum/affliction/wound/proc/init_stage(initial_damage)
	if(!length(stages))
		return
	current_stage = length(stages)
	while(current_stage > 1 && stage_damage(current_stage - 1) <= initial_damage / amount)
		current_stage--
	apply_current_stage()

/datum/affliction/wound/proc/apply_current_stage()
	min_damage = stage_damage(current_stage)
	desc = stage_desc(current_stage)
	name = desc

/// Push the physical model into the affliction model: severity (for vitality
/// readouts), load participation, and the limb's integrity cache.
/datum/affliction/wound/proc/sync()
	var/obj/item/organ/external/E = location
	var/scale = (istype(E) && E.max_damage) ? E.max_damage : 100
	injury_category = (damage > 0 && !internal) ? wound_category : null
	set_severity(internal ? min(damage * 2, AFFLICTION_SEVERITY_TERMINAL) : 100 * damage / scale)
	if(istype(E))
		E.integrity_dirty = TRUE
	body?.invalidate(BODY_DIRTY_ORGANS)

/datum/affliction/wound/load_value()
	return internal ? 0 : damage

/// Damage per merged wound.
/datum/affliction/wound/proc/wound_damage()
	return damage / amount

/datum/affliction/wound/proc/can_autoheal()
	if(is_treated())
		return TRUE
	if(wound_damage() <= autoheal_cutoff)
		if(created + 10 MINUTES > world.time) // Wounds don't autoheal for ten minutes if not bandaged.
			return FALSE
		return TRUE
	return FALSE

/// Has the wound been given the care its type needs?
/datum/affliction/wound/proc/is_treated()
	if(damage_type == BURN)
		return salved
	return bandaged

/// Can `other` be merged into src?
/datum/affliction/wound/proc/can_merge(datum/affliction/wound/other)
	if(other.type != type)
		return FALSE
	if(other.current_stage != current_stage)
		return FALSE
	if(other.damage_type != damage_type)
		return FALSE
	if(!other.can_autoheal() != !can_autoheal())
		return FALSE
	if(!other.bandaged != !bandaged)
		return FALSE
	if(!other.clamped != !clamped)
		return FALSE
	if(!other.salved != !salved)
		return FALSE
	if(!other.disinfected != !disinfected)
		return FALSE
	return TRUE

/datum/affliction/wound/proc/merge_wound(datum/affliction/wound/other)
	damage += other.damage
	amount += other.amount
	bleed_timer += other.bleed_timer
	germ_level = max(germ_level, other.germ_level)
	created = max(created, other.created)
	sync()

/// Is the wound open to infection? Bigger untreated wounds are likelier.
/datum/affliction/wound/proc/infection_check()
	if(damage < 10)
		return FALSE
	if(is_treated() && damage < 25)
		return FALSE
	if(disinfected)
		germ_level = 0
		return FALSE
	if(damage_type == BRUISE && !bleeding())
		return FALSE
	var/dam_coef = round(damage / 10)
	switch(damage_type)
		if(BRUISE)
			return prob(dam_coef * 5)
		if(BURN)
			return prob(dam_coef * 10)
		if(CUT)
			return prob(dam_coef * 20)
	return FALSE

/datum/affliction/wound/proc/bandage()
	bandaged = TRUE

/datum/affliction/wound/proc/salve()
	salved = TRUE

/datum/affliction/wound/proc/disinfect()
	disinfected = TRUE

/// Heal `amount`; returns what's left over for other wounds. Internal wounds
/// only heal with `heals_internal`.
/datum/affliction/wound/proc/heal_damage(amount, heals_internal = FALSE)
	if(internal && !heals_internal)
		return amount
	var/healed = min(damage, amount)
	amount -= healed
	damage -= healed
	if(length(stages))
		while(wound_damage() < stage_damage(current_stage) && current_stage < length(stages))
			current_stage++
		apply_current_stage()
	sync()
	return amount

/// Reopen the wound by `amount`.
/datum/affliction/wound/proc/open_wound(amount)
	damage += amount
	bleed_timer += amount
	if(length(stages))
		while(current_stage > 1 && stage_damage(current_stage - 1) <= damage / src.amount)
			current_stage--
		apply_current_stage()
	sync()

/// Can this wound absorb `amount` more of `type`? Keeps big hits from being
/// trapped in small wounds.
/datum/affliction/wound/proc/can_worsen(type, amount)
	if(damage_type != type)
		return FALSE
	if(src.amount > 1)
		return FALSE // merged wounds cannot be worsened
	if(!length(stages))
		return FALSE
	// 1.5x the worst stage: a shallow cut carries at most 30, a deep cut 37.5…
	if(damage + amount > 1.5 * stage_damage(1))
		return FALSE
	return TRUE

/datum/affliction/wound/proc/bleeding()
	if(internal)
		return FALSE // internal wounds bleed through calculate_internal_bloodloss
	if(current_stage > max_bleeding_stage)
		return FALSE
	if(bandaged || clamped)
		return FALSE
	// A tourniquet on this limb or one above it stops the flow into the wound.
	var/obj/item/organ/external/E = location
	if(istype(E) && E.flow_occluded())
		return FALSE
	if(bleed_timer <= 0 && wound_damage() <= bleed_threshold)
		return FALSE // clotted; big wounds need a bandage regardless
	return TRUE

// --- Affliction integration -------------------------------------------------

/// A wound merged an injury routed straight to it (affliction = wound type).
/datum/affliction/wound/receive_injury(amount, kind, atom/source)
	open_wound(amount)
	return amount

/// Wound damage, not severity, is the state; severity follows through sync().
/// Hemostatics run down the bleed; packing and occlusive seals dress the wound
/// (one wound per point); every other mechanism heals damage.
/// Returns the amount treated (bleed ticks, wounds dressed or damage).
/datum/affliction/wound/receive_tagged_treatment(tag, amount, continuous = FALSE)
	if(tag == TREAT_WOUND_PACKING || tag == TREAT_OCCLUSIVE_SEAL)
		if(bandaged || internal || amount < 1)
			return 0
		bandage()
		sync()
		log_game("WOUND: [key_name(owner)] [desc] on [location] dressed by [tag].")
		return 1
	if(tag == TREAT_HEMOSTATIC)
		if(bleed_timer <= 0)
			return 0
		var/bleed_before = bleed_timer
		bleed_timer = max(0, bleed_timer - (continuous ? amount * WOUND_HEMOSTATIC_BLEED_RATE : amount))
		return continuous ? (bleed_before - bleed_timer) / WOUND_HEMOSTATIC_BLEED_RATE : bleed_before - bleed_timer
	if(damage <= 0)
		return 0
	if(continuous)
		amount *= continuous_scale
	var/before = damage
	// Internal (arterial) wounds close only by vessel repair or restoration.
	heal_damage(amount, tag == TREAT_RESTORATION || tag == TREAT_VESSEL_REPAIR)
	return before - damage

/// Wounds don't progress on their own: autoheal lives in the limb's
/// update_wounds(), and severity mirrors damage.
/datum/affliction/wound/progress()
	return

/// Wounds don't progress on a severed limb.
/datum/affliction/wound/tick_offline()
	return

// --- Wound type selection ---------------------------------------------------

/// The wound affliction for `damage_type` (CUT/PIERCE/BRUISE/BURN) and
/// `damage`, on an organic or synthetic limb.
/proc/wound_affliction_type(damage_type, damage, synthetic = FALSE)
	if(synthetic)
		switch(damage_type)
			if(CUT, PIERCE)
				return /datum/affliction/wound/synthetic/breach
			if(BRUISE)
				return /datum/affliction/wound/synthetic/dent
			if(BURN)
				return /datum/affliction/wound/synthetic/scorch
		return null
	switch(damage_type)
		if(CUT)
			switch(damage)
				if(70 to INFINITY)
					return /datum/affliction/wound/cut/massive
				if(60 to 70)
					return /datum/affliction/wound/cut/gaping_big
				if(50 to 60)
					return /datum/affliction/wound/cut/gaping
				if(25 to 50)
					return /datum/affliction/wound/cut/flesh
				if(15 to 25)
					return /datum/affliction/wound/cut/deep
				if(0 to 15)
					return /datum/affliction/wound/cut/small
		if(PIERCE)
			switch(damage)
				if(60 to INFINITY)
					return /datum/affliction/wound/puncture/massive
				if(50 to 60)
					return /datum/affliction/wound/puncture/gaping_big
				if(30 to 50)
					return /datum/affliction/wound/puncture/gaping
				if(15 to 30)
					return /datum/affliction/wound/puncture/flesh
				if(0 to 15)
					return /datum/affliction/wound/puncture/small
		if(BRUISE)
			return /datum/affliction/wound/bruise
		if(BURN)
			switch(damage)
				if(50 to INFINITY)
					return /datum/affliction/wound/burn/carbonised
				if(40 to 50)
					return /datum/affliction/wound/burn/deep
				if(30 to 40)
					return /datum/affliction/wound/burn/severe
				if(15 to 30)
					return /datum/affliction/wound/burn/large
				if(0 to 15)
					return /datum/affliction/wound/burn/moderate
	return null

// --- Cuts ----------------------------------------------------------------------
// Minor cuts have max_bleeding_stage set to the stage bearing the wound type's
// name; major cuts to the clot ("blood soaked") stage.

/datum/affliction/wound/cut
	clinical_description = "An open laceration of the skin and soft tissue."
	bleed_threshold = 5
	damage_type = CUT
	treated_by = list(TREAT_TISSUE_REPAIR = 1, TREAT_HEMOSTATIC = 1, TREAT_WOUND_PACKING = 1, TREAT_OCCLUSIVE_SEAL = 1)

/datum/affliction/wound/cut/small
	max_bleeding_stage = 3
	stages = list("ugly ripped cut" = 20, "ripped cut" = 10, "cut" = 5, "healing cut" = 2, "small scab" = 0)

/datum/affliction/wound/cut/deep
	max_bleeding_stage = 3
	stages = list("ugly deep ripped cut" = 25, "deep ripped cut" = 20, "deep cut" = 15, "clotted cut" = 8, "scab" = 2, "fresh skin" = 0)

/datum/affliction/wound/cut/flesh
	max_bleeding_stage = 4
	stages = list("ugly ripped flesh wound" = 35, "ugly flesh wound" = 30, "flesh wound" = 25, "blood soaked clot" = 15, "large scab" = 5, "fresh skin" = 0)

/datum/affliction/wound/cut/gaping
	max_bleeding_stage = 3
	stages = list("gaping wound" = 50, "large blood soaked clot" = 25, "blood soaked clot" = 15, "small angry scar" = 5, "small straight scar" = 0)

/datum/affliction/wound/cut/gaping_big
	max_bleeding_stage = 3
	stages = list("big gaping wound" = 60, "healing gaping wound" = 40, "large blood soaked clot" = 25, "large angry scar" = 10, "large straight scar" = 0)

/datum/affliction/wound/cut/massive
	max_bleeding_stage = 3
	stages = list("massive wound" = 70, "massive healing wound" = 50, "massive blood soaked clot" = 25, "massive angry scar" = 10,  "massive jagged scar" = 0)

// --- Punctures --------------------------------------------------------------------

/datum/affliction/wound/puncture
	clinical_description = "A penetrating wound; narrow at the surface, deep beneath it."
	bleed_threshold = 5
	damage_type = PIERCE
	treated_by = list(TREAT_TISSUE_REPAIR = 1, TREAT_HEMOSTATIC = 1, TREAT_WOUND_PACKING = 1, TREAT_OCCLUSIVE_SEAL = 1)

/datum/affliction/wound/puncture/can_worsen(type, amount)
	return FALSE // punctures cannot be enlarged

/datum/affliction/wound/puncture/small
	max_bleeding_stage = 2
	stages = list("puncture" = 5, "healing puncture" = 2, "small scab" = 0)

/datum/affliction/wound/puncture/flesh
	max_bleeding_stage = 2
	stages = list("puncture wound" = 15, "blood soaked clot" = 5, "large scab" = 2, "small round scar" = 0)

/datum/affliction/wound/puncture/gaping
	max_bleeding_stage = 3
	stages = list("gaping hole" = 30, "large blood soaked clot" = 15, "blood soaked clot" = 10, "small angry scar" = 5, "small round scar" = 0)

/datum/affliction/wound/puncture/gaping_big
	max_bleeding_stage = 3
	stages = list("big gaping hole" = 50, "healing gaping hole" = 20, "large blood soaked clot" = 15, "large angry scar" = 10, "large round scar" = 0)

/datum/affliction/wound/puncture/massive
	max_bleeding_stage = 3
	stages = list("massive wound" = 60, "massive healing wound" = 30, "massive blood soaked clot" = 25, "massive angry scar" = 10,  "massive jagged scar" = 0)

// --- Bruises ------------------------------------------------------------------------

/datum/affliction/wound/bruise
	clinical_description = "Blunt trauma: crushed soft tissue and ruptured capillaries under intact skin."
	stages = list("monumental bruise" = 80, "huge bruise" = 50, "large bruise" = 30,
				  "moderate bruise" = 20, "small bruise" = 10, "tiny bruise" = 5)
	bleed_threshold = 20
	max_bleeding_stage = 2 // only huge bruises and worse bleed
	damage_type = BRUISE
	treated_by = list(TREAT_TISSUE_REPAIR = 1, TREAT_HEMOSTATIC = 1, TREAT_WOUND_PACKING = 1, TREAT_OCCLUSIVE_SEAL = 1)

// --- Burns ----------------------------------------------------------------------------

/datum/affliction/wound/burn
	clinical_description = "Thermal, chemical or electrical destruction of the skin."
	injury_category = INJURY_CATEGORY_THERMAL
	damage_type = BURN
	max_bleeding_stage = 0
	treated_by = list(TREAT_BURN_CARE = 1)

/datum/affliction/wound/burn/bleeding()
	return FALSE

/datum/affliction/wound/burn/moderate
	stages = list("ripped burn" = 10, "moderate burn" = 5, "healing moderate burn" = 2, "fresh skin" = 0)

/datum/affliction/wound/burn/large
	stages = list("ripped large burn" = 20, "large burn" = 15, "healing large burn" = 5, "fresh skin" = 0)

/datum/affliction/wound/burn/severe
	stages = list("ripped severe burn" = 35, "severe burn" = 30, "healing severe burn" = 10, "burn scar" = 0)

/datum/affliction/wound/burn/deep
	stages = list("ripped deep burn" = 45, "deep burn" = 40, "healing deep burn" = 15,  "large burn scar" = 0)

/datum/affliction/wound/burn/carbonised
	stages = list("carbonised area" = 50, "healing carbonised area" = 20, "massive burn scar" = 0)

// --- Internal bleeding -------------------------------------------------------------------

/datum/affliction/wound/internal_bleeding
	clinical_description = "A torn artery bleeding into the tissue. Only surgery closes it."
	category = "Circulation"
	internal = TRUE
	stages = list("severed artery" = 30, "cut artery" = 20, "damaged artery" = 10, "bruised artery" = 5)
	autoheal_cutoff = 5
	max_bleeding_stage = 4 // all stages bleed
	treated_by = list(TREAT_VESSEL_REPAIR = 1)

// --- Lost limb (stump) ----------------------------------------------------------------------

/datum/affliction/wound/lost_limb
	clinical_description = "The raw stump of an amputated limb."

/// `location` is the parent limb carrying the stump; `lost_limb` the limb
/// that came off.
/datum/affliction/wound/lost_limb/New(location, obj/item/organ/external/lost_limb, losstype, clean)
	if(!istype(lost_limb)) // prototype / bare construction
		return ..(location, 0)
	var/damage_amt = lost_limb.max_damage
	if(clean)
		damage_amt *= 0.25
	switch(losstype)
		if(DROPLIMB_EDGE, DROPLIMB_BLUNT)
			damage_type = CUT
			max_bleeding_stage = 3 // clotted stump and above bleed
			stages = list(
				"ripped stump" = damage_amt * 1.3,
				"bloody stump" = damage_amt,
				"clotted stump" = damage_amt * 0.5,
				"scarred stump" = 0,
			)
		if(DROPLIMB_BURN)
			damage_type = BURN
			injury_category = INJURY_CATEGORY_THERMAL
			stages = list(
				"ripped charred stump" = damage_amt * 1.3,
				"charred stump" = damage_amt,
				"scarred stump" = 0,
			)
		if(DROPLIMB_ACID)
			damage_type = BURN
			injury_category = INJURY_CATEGORY_THERMAL
			stages = list(
				"disfigured mass" = damage_amt * 1.3,
				"melted stump" = damage_amt,
				"deformed stump" = damage_amt * 0.5,
				"scarred stump" = 0,
			)
	treated_by = (damage_type == BURN) ? list(TREAT_BURN_CARE = 1) : list(TREAT_TISSUE_REPAIR = 1, TREAT_HEMOSTATIC = 1, TREAT_WOUND_PACKING = 1)
	return ..(location, damage_amt)

/datum/affliction/wound/lost_limb/can_merge(datum/affliction/wound/other)
	return FALSE

// --- Synthetic wounds ------------------------------------------------------------------------
// Prosthetic and robotic limbs. They never bleed, never get infected and
// never autoheal: they are repaired — welder / nanopaste (plating) for
// structural damage, cable / nanopaste (wiring) for scorching.

/datum/affliction/wound/synthetic
	category = "Hardware"
	biology = BIOLOGY_SYNTHETIC | BIOLOGY_NANOFORM
	autoheal_cutoff = 0
	max_bleeding_stage = 0
	continuous_scale = 1

/datum/affliction/wound/synthetic/bleeding()
	return FALSE

/datum/affliction/wound/synthetic/infection_check()
	return FALSE

/datum/affliction/wound/synthetic/can_autoheal()
	return FALSE

/datum/affliction/wound/synthetic/is_treated()
	return FALSE

/datum/affliction/wound/synthetic/dent
	clinical_description = "Deformed plating and bent structural members from an impact."
	damage_type = BRUISE
	treated_by = list(TREAT_PLATING_REPAIR = 1)
	stages = list("crumpled plating" = 50, "severe dent" = 30, "dent" = 15, "small dent" = 5, "scuff" = 0)

/datum/affliction/wound/synthetic/breach
	clinical_description = "A cut or puncture through the plating, exposing the internals."
	damage_type = CUT
	treated_by = list(TREAT_PLATING_REPAIR = 1)
	stages = list("torn-open plating" = 50, "hull breach" = 30, "gash" = 15, "nick" = 5, "scratch" = 0)

/datum/affliction/wound/synthetic/scorch
	clinical_description = "Heat or current damage: scorched plating and melted wiring insulation."
	injury_category = INJURY_CATEGORY_THERMAL
	damage_type = BURN
	treated_by = list(TREAT_WIRING_REPAIR = 1)
	stages = list("melted wiring" = 50, "fused circuitry" = 30, "scorching" = 15, "scorch mark" = 5, "discolouration" = 0)

#undef WOUND_HEMOSTATIC_BLEED_RATE
