// Shared constants for the on-demand expedition system.

// ---- Site lifecycle status -------------------------------------------------
#define EXP_STATUS_GENERATING 1 // z allocated, being carved/populated
#define EXP_STATUS_READY      2 // generated, awaiting crew deployment
#define EXP_STATUS_ACTIVE     3 // crew deployed at least once
#define EXP_STATUS_COMPLETE   4 // mission objective satisfied
#define EXP_STATUS_EXPIRED    5 // released, z returned to the reuse pool

// ---- Mission state ---------------------------------------------------------
#define EXP_MISSION_ACTIVE   1
#define EXP_MISSION_COMPLETE 2
#define EXP_MISSION_FAILED   3

// ---- Objective state -------------------------------------------------------
#define EXP_OBJ_INCOMPLETE 1
#define EXP_OBJ_COMPLETE   2
#define EXP_OBJ_FAILED     3

// ---- Difficulty bands ------------------------------------------------------
#define EXP_DIFF_LOW   1
#define EXP_DIFF_MED   2
#define EXP_DIFF_HIGH  3

// ---- Loot tiers (low -> high quality) --------------------------------------
#define EXP_LOOT_SCRAP    1
#define EXP_LOOT_COMMON   2
#define EXP_LOOT_UNCOMMON 3
#define EXP_LOOT_RARE     4
#define EXP_LOOT_EXOTIC   5

// ---- Location sizes --------------------------------------------------------
#define EXP_SIZE_SMALL  1
#define EXP_SIZE_MEDIUM 2
#define EXP_SIZE_LARGE  3

// ---- Enemy factions --------------------------------------------------------
// The kind of hostiles guarding a site. Rolled per-site (rarer factions gated
// to higher difficulty) or pinned by a mission. Drives every enemy spawn and
// the boss, via expedition_faction.dm.
#define EXP_FACTION_FAUNA 1 // wild beasts (the default everywhere)
#define EXP_FACTION_XENO  2 // xenomorph brood
#define EXP_FACTION_SYNTH 3 // rogue synthetics / hivebots
#define EXP_FACTION_MERC  4 // hostile mercenaries

// ---- Tuning ----------------------------------------------------------------
// How long a site may sit with no players aboard before it is auto-released
// and its z-level recycled.
#define EXP_AUTO_RELEASE_GRACE (90 SECONDS)
// How many mission offers a launch console keeps on its board.
#define EXP_OFFER_COUNT 3
// Radius (tiles) around the console that counts as "on the launch pad".
#define EXP_PAD_RADIUS 2
// Cooldown between launches on a single console.
#define EXP_LAUNCH_COOLDOWN (3 MINUTES)
