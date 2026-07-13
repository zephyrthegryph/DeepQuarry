// Mind/Body specialty system defines.
//
// Two top-level types (Body + Mind), each divided into thematic *categories* with
// their own age-derived point pools. Categories own one or more *trees* which group
// perks visually; trees inside a single category share that category's pool. Younger
// characters get bigger Body pools, older characters get bigger Mind pools.
//
// Per-category pool formula (tuneable from here):
//   body_pool_per_cat = clamp(BASE_BODY_PER_CAT - decay,  MIN_PER_CAT, BASE_BODY_PER_CAT)
//   mind_pool_per_cat = clamp(MIN_PER_CAT      + growth,  MIN_PER_CAT, MAX_MIND_PER_CAT)
//   decay = round((age - 18) / AGE_STEP)
//   growth = round((age - 18) / AGE_STEP)
//
// At age 18  : body = 6 per cat × 4 cats = 24 total; mind = 2 per cat × 7 cats = 14 total
// At age 58  : body = 2 per cat × 4 cats =  8 total; mind = 6 per cat × 7 cats = 42 total
// At age 100 : body = 2 per cat × 4 cats =  8 total; mind = 6 per cat × 7 cats = 42 total (caps)

// Pool sizes — single shared pool per side (Body, Mind). Each side's pool
// covers ALL of that side's categories; spending Speed points reduces what's
// available for Strength / Vigor / Endurance.
#define MIND_BODY_AGE_STEP            10
#define MIND_BODY_BODY_POOL_AT_18     20
#define MIND_BODY_BODY_POOL_MIN       8
#define MIND_BODY_MIND_POOL_AT_18     8
#define MIND_BODY_MIND_POOL_MAX       20

// Top-level category type ids — used by /datum/perk.category lookup and the UI to
// split the view into Body vs Mind panes.
#define PERK_CATEGORY_TYPE_BODY  "body"
#define PERK_CATEGORY_TYPE_MIND  "mind"

// Body category ids (one tree per category).
#define PERK_CATEGORY_BODY_STRENGTH   "body_strength"
#define PERK_CATEGORY_BODY_VIGOR      "body_vigor"
#define PERK_CATEGORY_BODY_SPEED      "body_speed"
#define PERK_CATEGORY_BODY_ENDURANCE  "body_endurance"

// Mind department category ids (each owns multiple sub-role trees).
#define PERK_CATEGORY_MIND_COMMAND     "mind_command"
#define PERK_CATEGORY_MIND_SECURITY    "mind_security"
#define PERK_CATEGORY_MIND_ENGINEERING "mind_engineering"
#define PERK_CATEGORY_MIND_MEDICAL     "mind_medical"
#define PERK_CATEGORY_MIND_RESEARCH    "mind_research"
#define PERK_CATEGORY_MIND_CARGO       "mind_cargo"
#define PERK_CATEGORY_MIND_CIVILIAN    "mind_civilian"

// Body tree ids (one per body category; the tree id matches the category id).
#define PERK_TREE_BODY_STRENGTH    PERK_CATEGORY_BODY_STRENGTH
#define PERK_TREE_BODY_VIGOR       PERK_CATEGORY_BODY_VIGOR
#define PERK_TREE_BODY_SPEED       PERK_CATEGORY_BODY_SPEED
#define PERK_TREE_BODY_ENDURANCE   PERK_CATEGORY_BODY_ENDURANCE

// Mind sub-role tree ids — each belongs to a Mind category (the department) and
// shares its pool. Names match the job they're built around so the UI can read
// thematically.
#define PERK_TREE_MIND_CMD_CAPTAIN     "mind_cmd_captain"
#define PERK_TREE_MIND_CMD_HOP         "mind_cmd_hop"

#define PERK_TREE_MIND_SEC_OFFICER     "mind_sec_officer"
#define PERK_TREE_MIND_SEC_DETECTIVE   "mind_sec_detective"
#define PERK_TREE_MIND_SEC_WARDEN      "mind_sec_warden"

#define PERK_TREE_MIND_ENG_ATMOS       "mind_eng_atmos"
#define PERK_TREE_MIND_ENG_ENGINE      "mind_eng_engine"
#define PERK_TREE_MIND_ENG_SALVAGE     "mind_eng_salvage"

#define PERK_TREE_MIND_MED_DOCTOR      "mind_med_doctor"
#define PERK_TREE_MIND_MED_SURGEON     "mind_med_surgeon"
#define PERK_TREE_MIND_MED_CHEMIST     "mind_med_chemist"

#define PERK_TREE_MIND_RES_SCIENTIST   "mind_res_scientist"
#define PERK_TREE_MIND_RES_ROBOTICIST  "mind_res_roboticist"
#define PERK_TREE_MIND_RES_XENOARCH    "mind_res_xenoarch"

#define PERK_TREE_MIND_CARGO_QM        "mind_cargo_qm"
#define PERK_TREE_MIND_CARGO_TECH      "mind_cargo_tech"
#define PERK_TREE_MIND_CARGO_MINER     "mind_cargo_miner"

#define PERK_TREE_MIND_CIV_BARTENDER   "mind_civ_bartender"
#define PERK_TREE_MIND_CIV_CHEF        "mind_civ_chef"
#define PERK_TREE_MIND_CIV_BOTANIST    "mind_civ_botanist"
#define PERK_TREE_MIND_CIV_JANITOR     "mind_civ_janitor"

// /datum/perk.category dispatches via these labels to the correct pool side.
#define PERK_KIND_BODY  "body"
#define PERK_KIND_MIND  "mind"

// Threshold-capstone gate: points to spend in a category before its capstone unlocks.
#define DQ_PERK_CAPSTONE_SPEND 7

// ── Perk effect-hook ids (fx_mult / fx_add) ─────────────────────────────────────
// A perk declares fx_mult[hook]/fx_add[hook]; on grant these fold into a per-mob cache.
// A gameplay site reads perk_mult(hook) (default 1) or perk_add(hook) (default 0). New
// perks sharing a hook need NO site change — just declare the modifier on the datum.
// Strings are fine here; they only key a small per-mob assoc cache.
#define DQ_PERK_FX_UNARMED_DMG     "unarmed_dmg"     // mult: unarmed attack force
#define DQ_PERK_FX_HEAVY_DMG       "heavy_dmg"       // mult: charged/heavy swing force
#define DQ_PERK_FX_ARMOR_PEN       "armor_pen"       // add:  fraction of target armor ignored (0-1)
#define DQ_PERK_FX_THROW_FORCE     "throw_force"     // mult: thrown-item impact damage
#define DQ_PERK_FX_THROW_RANGE     "throw_range"     // add:  bonus throw range (tiles)
#define DQ_PERK_FX_REGEN           "regen"           // mult: passive out-of-combat regen
#define DQ_PERK_FX_HEAL            "heal"            // mult: all natural healing
#define DQ_PERK_FX_ORGAN_HEAL      "organ_heal"      // mult: internal-organ self-repair
#define DQ_PERK_FX_CLOT            "clot"            // mult: bleed clotting rate
#define DQ_PERK_FX_BLOOD_REGEN     "blood_regen"     // mult: blood volume recovery
#define DQ_PERK_FX_MAX_BLOOD       "max_blood"       // mult: maximum blood volume
#define DQ_PERK_FX_KNOCKBACK_DIST  "knockback_dist"  // mult: distance you are shoved/knocked back
#define DQ_PERK_FX_KNOCKDOWN_DUR   "knockdown_dur"   // mult: knockdown/weaken duration on you
#define DQ_PERK_FX_STAMINA_DRAIN   "stamina_drain"   // mult: stamina cost of exertion
#define DQ_PERK_FX_STAMINA_REGEN   "stamina_regen"   // mult: stamina recovery rate
#define DQ_PERK_FX_EVADE_MELEE     "evade_melee"     // add:  % chance to evade a light melee hit
#define DQ_PERK_FX_EVADE_RANGED    "evade_ranged"    // add:  % chance to evade thrown/projectile
#define DQ_PERK_FX_HAZARD_HEAT     "hazard_heat"     // mult: heat/high-temp damage taken
#define DQ_PERK_FX_HAZARD_COLD     "hazard_cold"     // mult: cold/low-temp damage taken
#define DQ_PERK_FX_HAZARD_PRESSURE_HIGH "hazard_pressure_high" // mult: high-pressure damage
#define DQ_PERK_FX_HAZARD_PRESSURE_LOW  "hazard_pressure_low"  // mult: low-pressure/vacuum damage
#define DQ_PERK_FX_HAZARD_ACID     "hazard_acid"     // mult: acid damage taken
#define DQ_PERK_FX_GRAB_ESCAPE     "grab_escape"     // add:  % bonus to your grab-break chance
#define DQ_PERK_FX_STAGGER_RESIST  "stagger_resist"  // mult: incoming poise/stagger damage

// ── Body perk effect tuning ─────────────────────────────────────────────────────
// Magnitudes for the conditional (has_perk / fx) Body perks. Stat-mod perks tune via
// their var_changes instead.

// Strength
#define DQ_PERK_POWERFUL_UNARMED_MULT  1.2   // Powerful Build: unarmed force.
#define DQ_PERK_HEAVY_HANDS_MULT       1.25  // Heavy Hands: charged-swing force.
#define DQ_PERK_SUNDERING_PEN          0.25  // Sundering Blows: armor fraction ignored.
#define DQ_PERK_FORCE_OF_WILL_PROB     15    // Force of Will: % melee hit knocks back.
#define DQ_PERK_BRAWLER_STAGGER        15    // Brawler: poise damage added by an unarmed hit.
#define DQ_PERK_VISE_BREAK_MULT        0.5   // Vise Hands: victim's grab-break chance.
#define DQ_PERK_CHOKE_UPGRADE_MULT     0.75  // Choke Hold: grab reinforce cooldown.
#define DQ_PERK_CRUSHING_BRUTE         2     // Crushing Embrace: brute per tick on a held grab.
#define DQ_PERK_SLIPPERY_ESCAPE        15    // Slippery: % bonus to grab-break chance.
#define DQ_PERK_WRIGGLER_ESCAPE        30    // Wriggler: % bonus to grab-break chance.
#define DQ_PERK_IRON_GRIP_RESIST       50    // Iron Grip: % chance to shrug off a shove.
#define DQ_PERK_DEVOUR_SPEED_MULT      0.7   // Pin/Choke Hold: swallow time on a held victim.
#define DQ_EQUIP_DELAY                 5     // Base quick-equip time; Quickened Hands cuts it, Quick Draw zeroes it for weapons.
#define DQ_PERK_QUICKENED_HANDS_MULT   0.75  // Quickened Hands: quick-equip time.
#define DQ_PERK_THICK_SKIN_PROB        25    // Thick Skin: % chance a brute hit opens no wound.
#define DQ_PERK_BONE_DENSITY_MULT      0.7   // Bone Density: impact damage taken.
#define DQ_PERK_THROW_RANGE_BONUS      2     // Throwing Arm: bonus throw range.
#define DQ_PERK_HAMMER_THROW_MULT      1.25  // Hammer Throw: thrown impact.

// Vigor
#define DQ_PERK_HEARTY_MULT            1.25  // Hearty: out-of-combat regen.
#define DQ_PERK_QUICK_HEALER_MULT      1.2   // Quick Healer: natural healing.
#define DQ_PERK_CONVALESCENT_MULT      1.5   // Convalescent: resting regen bonus.
#define DQ_PERK_REGEN_BASE             1     // Hearty: base HP regen per Life tick out of combat.
#define DQ_PERK_REGEN_COMBAT_DELAY     (5 SECONDS) // Quiet time after a scuffle before regen resumes.
#define DQ_PERK_RESTORATION_MULT       1.25  // Restoration: organ self-repair.
#define DQ_PERK_CLOT_MULT              1.5   // Strong Bloodflow: clot rate.
#define DQ_PERK_MARROW_MULT            2.0   // Marrow Pack: blood recovery.
#define DQ_PERK_JUICE_BOX_MULT         1.2   // Juice Box: max blood volume.
#define DQ_PERK_PAIN_TOLERANCE_HP      15    // Pain Tolerance: crit threshold drop (HP).
#define DQ_PERK_SURVIVOR_HP            10    // Survivor: extra crit-threshold room (HP).
#define DQ_PERK_DEATHS_DOOR_HP         10    // Death's Door: extra crit-threshold room (HP).
#define DQ_PERK_SECOND_WIND_HEAL       30    // Second Wind: HP restored.
#define DQ_PERK_SECOND_WIND_CD         (5 MINUTES) // Second Wind / Adrenal reuse delay.

// Speed
#define DQ_PERK_DODGE_PROB             10    // Dodge: % evade light melee.
#define DQ_PERK_REFLEXES_PROB          20    // Reflexes: % evade thrown/projectile.
#define DQ_PERK_BLUR_PROB              15    // Blur: extra flat melee evade.
#define DQ_PERK_ACROBATIC_MULT         0.8   // Acrobatic: knockdown duration.

// Endurance
#define DQ_PERK_STEADFAST_MULT         0.5   // Steadfast: knockback distance.
#define DQ_PERK_CONDITIONED_MULT       0.75  // Conditioned: stamina drain.
#define DQ_PERK_SECOND_BREATH_MULT     1.5   // Second Breath: stamina regen out of melee.
#define DQ_PERK_IMMOVABLE_STAGGER      0.6   // Immovable: incoming poise damage.
#define DQ_PERK_IMMOVABLE_WINDOW       (1.5 SECONDS) // Immovable: post-CC immunity window.
#define DQ_PERK_EXECUTION_SPEED_MULT   0.6   // Juggernaut: execution windup time.
#define DQ_PERK_STALWART_PROB          20    // Stalwart: % chance to shed an extra point of stun/tick.
#define DQ_PERK_TENACIOUS_MULT         0.5   // Tenacious: first-stun duration.
#define DQ_PERK_TENACIOUS_WINDOW       (8 SECONDS) // Quiet time that "resets" the first-stun bonus.
