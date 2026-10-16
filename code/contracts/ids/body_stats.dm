// The body factors as stats (doc/rewrite/final_api.html section 5; doc/rewrite/proposals/stat_layer.md section 4.1). Every one is a real var on
// /mob/living: the stat's settled value, written by the engine alone and read as a plain var (`L.slowdown`). `bounds` is the range the composed
// value is held to (a single contribution may exceed it: an affliction's +30 slowdown composes to at most 20); `schema` on a MAX stat is the range a
// contribution must lie in, which a test build asserts: not below the base (a MAX contribution under it could never count, where the old fold's
// max(baseline, ...) ignored it silently). Its upper side is open, because a table scaled by a dose of 2 or 4 legitimately gives 2 or 4, and the
// bounds hold the composed value to 1. The combine rules are PRODUCT for a multiplier (base 1), SUM for an offset (base 0), MAX for
// a flag or a forced level and MASK_OR for a bit field.
//
// A source declares a table of them (a body factor table, hold_table() in code/engine/stats/tables.dm); the body re-reads every source in
// refresh_factor_sources() (code/modules/body/factors.dm).

// --- Physiology -----------------------------------------------------------------------------------------------------------------

STAT(/mob/living, airway, PRODUCT, bounds = list(0, 1))
STAT(/mob/living, resp_drive, PRODUCT, bounds = list(0, 2))
STAT(/mob/living, lung_mechanics, PRODUCT, bounds = list(0, 1))
STAT(/mob/living, gas_exchange, PRODUCT, bounds = list(0, 1))
STAT(/mob/living, pump, PRODUCT, bounds = list(0, 2))
STAT(/mob/living, circulation, PRODUCT, bounds = list(0, 2))
STAT(/mob/living, demand, PRODUCT, bounds = list(0, 4))
STAT(/mob/living, progression, PRODUCT, bounds = list(0, 4))
STAT(/mob/living, metabolism, PRODUCT, bounds = list(0, 10))
STAT(/mob/living, bleeding, PRODUCT, bounds = list(0, 10))
STAT(/mob/living, healing, PRODUCT, bounds = list(0, 10))

// --- Pain and consciousness ---------------------------------------------------------------------------------------------------
STAT(/mob/living, analgesia, SUM)
STAT(/mob/living, pain, SUM, bounds = list(0, INFINITY))
STAT(/mob/living, sedation, SUM, bounds = list(0, INFINITY))
STAT(/mob/living, heart_rate, SUM)

// --- Vital-sign readouts ------------------------------------------------------------------------------------------------------
STAT(/mob/living, temperature, SUM)
STAT(/mob/living, bp_systolic, SUM)
STAT(/mob/living, bp_diastolic, SUM)
STAT(/mob/living, o2_sat, SUM, bounds = list(-100, 100))
STAT(/mob/living, resp_rate, SUM)

// --- Combat and mobility ------------------------------------------------------------------------------------------------------
STAT(/mob/living, slowdown, SUM, bounds = list(-10, 20))
STAT(/mob/living, penalty_scale, PRODUCT, bounds = list(0, 4))
STAT(/mob/living, haste, MAX, base = 0, bounds = list(0, 1), schema = num(0, INFINITY))
STAT(/mob/living, accuracy, SUM)
STAT(/mob/living, dispersion, SUM)
/// The chance for an attack to miss, in percent. The mob's own base evasion is this stat's type-level constant (its initial value).
STAT(/mob/living, evasion, SUM)
STAT(/mob/living, attack_speed, PRODUCT, bounds = list(0.1, 10))
STAT(/mob/living, melee_damage, PRODUCT, bounds = list(0, 10))

// --- Senses -------------------------------------------------------------------------------------------------------------------
STAT(/mob/living, motor_control, PRODUCT, bounds = list(0, 1))
STAT(/mob/living, darksight, MAX, base = 0, bounds = list(0, 1), schema = num(0, INFINITY))
STAT(/mob/living, sight_flags, MASK_OR)
STAT(/mob/living, action_blocks, MASK_OR)

// --- Harm ---------------------------------------------------------------------------------------------------------------------
STAT(/mob/living, incoming_all, PRODUCT, bounds = list(0, 10))
STAT(/mob/living, incoming_physical, PRODUCT, bounds = list(0, 10))
STAT(/mob/living, incoming_thermal, PRODUCT, bounds = list(0, 10))
STAT(/mob/living, incoming_toxic, PRODUCT, bounds = list(0, 10))
STAT(/mob/living, incoming_genetic, PRODUCT, bounds = list(0, 10))
STAT(/mob/living, incoming_neural, PRODUCT, bounds = list(0, 10))
STAT(/mob/living, incoming_pain, PRODUCT, bounds = list(0, 10))
STAT(/mob/living, disable_duration, PRODUCT, bounds = list(0, 10))
STAT(/mob/living, healing_received, PRODUCT, bounds = list(0, 10))
STAT(/mob/living, endurance_flat, SUM)
STAT(/mob/living, endurance_mult, PRODUCT, bounds = list(0, 100))
/// Sprite width and height as multipliers of the base scale (icon_scale_x, icon_scale_y), which they do not replace.
STAT(/mob/living, scale_mult_x, PRODUCT, bounds = list(0.1, 10))
STAT(/mob/living, scale_mult_y, PRODUCT, bounds = list(0.1, 10))
STAT(/mob/living, pain_immunity, MAX, base = 0, bounds = list(0, 1), schema = num(0, INFINITY))
STAT(/mob/living, pulse_shift, SUM)
STAT(/mob/living, pulse_set, MAX, base = -1, bounds = list(-1, INFINITY), schema = num(-1, INFINITY))
STAT(/mob/living, emp_shift, SUM)
STAT(/mob/living, explosion_shift, SUM)
STAT(/mob/living, heat_exposure, PRODUCT, bounds = list(0, 10))
STAT(/mob/living, cold_exposure, PRODUCT, bounds = list(0, 10))
STAT(/mob/living, siemens, PRODUCT, bounds = list(0, 10))

// --- Chemistry ----------------------------------------------------------------------------------------------------------------
STAT(/mob/living, stabilization, SUM, bounds = list(0, INFINITY))
STAT(/mob/living, antimicrobial, SUM, bounds = list(0, INFINITY))
STAT(/mob/living, blood_regen, SUM, bounds = list(0, INFINITY))
STAT(/mob/living, intoxication, SUM, bounds = list(0, INFINITY))
STAT(/mob/living, hepatotoxicity, SUM, bounds = list(0, INFINITY))
STAT(/mob/living, antiemetic, SUM, bounds = list(0, INFINITY))
STAT(/mob/living, allergy, SUM, bounds = list(0, INFINITY))
STAT(/mob/living, withdrawal, SUM, bounds = list(0, INFINITY))
STAT(/mob/living, neural_repair, SUM, bounds = list(0, INFINITY))
STAT(/mob/living, immune_suppression, SUM, bounds = list(0, INFINITY))

// --- Oxygen transport and stasis ----------------------------------------------------------------------------------------------
STAT(/mob/living, o2_carriage, PRODUCT, bounds = list(0, 2))
STAT(/mob/living, tissue_uptake, PRODUCT, bounds = list(0, 2))
STAT(/mob/living, cardiac_irritability, PRODUCT, bounds = list(0, 10))
/// Share of life processes suspended, 0..1 (stasis bags, sleepers, cryopods); the biological clock's rate is the separate stat clock_rate_bio.
STAT(/mob/living, stasis, MAX, base = 0, bounds = list(0, 1), schema = num(0, INFINITY))

// --- Armour: one stat per armour kind (ARMOR_KIND_COUNT), added to worn and natural armour ----------------------------------------
STAT(/mob/living, armor_blunt, SUM)
STAT(/mob/living, armor_cut, SUM)
STAT(/mob/living, armor_pierce, SUM)
STAT(/mob/living, armor_burn, SUM)
STAT(/mob/living, armor_frostbite, SUM)
STAT(/mob/living, armor_corrosive, SUM)
STAT(/mob/living, armor_electric, SUM)
STAT(/mob/living, armor_toxin, SUM)
STAT(/mob/living, armor_radiation, SUM)
STAT(/mob/living, armor_cellular, SUM)
STAT(/mob/living, armor_neural, SUM)
STAT(/mob/living, armor_pain, SUM)
STAT(/mob/living, armor_digestion, SUM)
STAT(/mob/living, armor_blast, SUM)
