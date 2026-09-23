// Damage packet kinds. See doc/rewrite/damage.md §2.
// Flat list indices into /datum/damage_packet/var/list/amounts.
#define DAMAGE_BLUNT      1
#define DAMAGE_SHARP      2
#define DAMAGE_PIERCE     3
#define DAMAGE_THERMAL    4
#define DAMAGE_COLD       5
#define DAMAGE_SHOCK      6
#define DAMAGE_CORROSIVE  7
#define DAMAGE_TOXIC      8
#define DAMAGE_RADIATION  9
#define DAMAGE_IONIC      10
#define DAMAGE_BLAST      11
#define DAMAGE_PAIN       12
#define DAMAGE_KIND_COUNT 12

// Damage packet flags.
/// The hit has a cutting edge (dismemberment odds, sharp-to-blunt conversion).
#define DAMAGE_PACKET_EDGE              (1<<0)
/// Delivered by a projectile.
#define DAMAGE_PACKET_PROJECTILE        (1<<1)
/// No hit sound, no pain flash.
#define DAMAGE_PACKET_SILENT            (1<<2)
/// Skip species/body resistance factors (scripted exact amounts).
#define DAMAGE_PACKET_IGNORE_RESISTANCE (1<<3)
/// Armour does not apply (insulation already counted, hits from inside, EMP surges).
#define DAMAGE_PACKET_UNARMORED         (1<<5)
/// Delivered by a thrown atom.
#define DAMAGE_PACKET_THROWN            (1<<4)

