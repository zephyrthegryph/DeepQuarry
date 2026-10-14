// Hit entries and triggers (the entry a damage packet came through). What a type does when it is hit is a hook on the hit action
// in its CAPABILITIES block: extend(/datum/act/hit/emp, instead(...)), on_notice(/datum/notice/hit/emp, ...), and reflects(kinds, chance)
// for a holder that bounces rounds back (code/datums/sys/damage_reactions.dm).

#define DAMAGE_ENTRY_PROJECTILE 101
#define DAMAGE_ENTRY_EMP 102
#define DAMAGE_ENTRY_EXPLOSION 103
#define DAMAGE_ENTRY_THROWN 104
#define DAMAGE_ENTRY_BLOB 105
#define DAMAGE_ENTRY_GENERIC 106
#define DAMAGE_ENTRY_WEAPON 107
#define DAMAGE_ENTRY_SHOCK 108

/// Entry triggers (the spelling used in declarations).
#define DAMAGE_PROJECTILE DAMAGE_ENTRY_PROJECTILE
#define DAMAGE_EMP DAMAGE_ENTRY_EMP
#define DAMAGE_EXPLOSION DAMAGE_ENTRY_EXPLOSION
#define DAMAGE_THROWN DAMAGE_ENTRY_THROWN
#define DAMAGE_BLOB DAMAGE_ENTRY_BLOB
#define DAMAGE_GENERIC_ATTACK DAMAGE_ENTRY_GENERIC
#define DAMAGE_WEAPON DAMAGE_ENTRY_WEAPON
#define DAMAGE_ELECTROCUTE DAMAGE_ENTRY_SHOCK
