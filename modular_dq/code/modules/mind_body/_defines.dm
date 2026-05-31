// DQAdd — Mind/Body specialty system defines.
//
// Two independent point pools whose size is age-derived: younger characters get more Body,
// older characters get more Mind. Body buys small linear stat tweaks (HP, slowdown, …) and
// unlocks threshold perks; Mind buys role-themed perks organized into per-department trees.
//
// Pool formula (tuneable from here):
//   body_pool = clamp(BASE_BODY_AT_18 - ((age - MIN_AGE) / AGE_STEP),  MIN_POINTS, BASE_BODY_AT_18)
//   mind_pool = clamp(MIN_POINTS    + ((age - MIN_AGE) / AGE_STEP),  MIN_POINTS, BASE_BODY_AT_18)
// At age 18  : body = 14, mind = 2
// At age 58  : body = 10, mind = 6
// At age 118 : body =  4, mind = 12
// At age 158+: body =  2, mind = 14 (both clamped)

#define MIND_BODY_MIN_POINTS       2
#define MIND_BODY_BASE_BODY_AT_18  14
#define MIND_BODY_AGE_STEP         10

// Body linear allocation: each spent Body point grants a small tweak. Threshold perks
// unlock at fixed totals and are bought on top of the linear floor.
#define BODY_POINT_HP_PER          2     // +N max HP per linear Body point
#define BODY_POINT_SLOWDOWN_PER    0.01  // -N slowdown per linear Body point

// Body threshold perk tiers (cost = tier; visible/buyable only when at-least-this-many Body
// points have been linearly allocated).
#define BODY_TIER_LOW              3
#define BODY_TIER_MID              6
#define BODY_TIER_HIGH             9

// Tree identifiers. Body has four thematic sub-catalogs (Strength/Vigor/Speed/Endurance);
// Mind has one tree per department. All Body trees share the Body pool; all Mind trees
// share the Mind pool.
#define PERK_TREE_BODY_STRENGTH    "body_strength"
#define PERK_TREE_BODY_VIGOR       "body_vigor"
#define PERK_TREE_BODY_SPEED       "body_speed"
#define PERK_TREE_BODY_ENDURANCE   "body_endurance"
#define PERK_TREE_MIND_COMMAND     "mind_command"
#define PERK_TREE_MIND_SECURITY    "mind_security"
#define PERK_TREE_MIND_ENGINEERING "mind_engineering"
#define PERK_TREE_MIND_MEDICAL     "mind_medical"
#define PERK_TREE_MIND_RESEARCH    "mind_research"
#define PERK_TREE_MIND_CARGO       "mind_cargo"
#define PERK_TREE_MIND_CIVILIAN    "mind_civilian"

// Perk categories (which pool the cost is drawn from).
#define PERK_CATEGORY_BODY         "body"
#define PERK_CATEGORY_MIND         "mind"
