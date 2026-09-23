// Interned armour (doc/rewrite/damage.md §4, roadmap D2). See code/datums/armor.dm.

// Armour keys beyond the damage flags in combat.dm (MELEE, BULLET, LASER,
// ENERGY, BOMB, BIO, FIRE, ACID).
/// Radiation.
#define ARMOR_RAD "rad"
/// Cold: frostbite through a covering, and cold reaching what a holder keeps.
#define ARMOR_COLD "cold"
/// Suffix of a key's flat soak in an armour spec: "melee_flat=5".
#define ARMOR_FLAT_SUFFIX "_flat"

// Indices into the list /datum/armor/proc/soak() returns.
/// Amount left after the armour.
#define ARMOR_SOAK_AMOUNT 1
/// The injury kind that lands: a cut or pierce whose edge the armour turned lands as INJURY_BLUNT.
#define ARMOR_SOAK_KIND 2
/// Effective protection, 0..100, after penetration.
#define ARMOR_SOAK_PROTECTION 3
