// DQAdd — Mind/Body specialty system defines.
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
