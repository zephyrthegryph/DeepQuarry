//We will round to this value in damage calculations.
#define DAMAGE_PRECISION 0.1
/// Material weapons, armour and traps wear down one of these (in integrity) per
/// blow; their max integrity is the material's integrity, rounded to wear units.
#define MATERIAL_WEAR_UNIT 10

//Damage flag defines //

/// Involves corrosive substances.
#define ACID "acid"
/// Involved in checking whether a disease can infect or spread. Also involved in xeno neurotoxin.
#define BIO "bio"
/// Involves a shockwave, usually from an explosion.
#define BOMB "bomb"
/// Involves a solid projectile.
#define BULLET "bullet"
/// Involves being eaten
#define CONSUME "consume"
/// Involves an EMP or energy-based projectile.
#define ENERGY "energy"
/// Involves fire or temperature extremes.
#define FIRE "fire"
/// Involves a laser.
#define LASER "laser"
/// Involves a melee attack or a thrown object.
#define MELEE "melee"
/// Involved in checking the likelihood of applying a wound to a mob.
#define WOUND "wound"

