// Life scheduler (doc/mob_life_architecture.md §4). /mob/living/Life() runs an ordered list
// of /datum/life_system flyweights; these defines are its vocabulary.

// --- Phases: the coarse position of a system inside one Life cycle --------------------------
// Systems sort by phase, then order. The phase-2 move keeps the legacy Life() sequence, so
// every system sits in the phase that matches where its code ran before; LIFE_PHASE_TAIL
// holds the code subtypes ran after ..() (human, alien, simple mob and bot tails, and the
// per-type pre/post chains). Later phases re-home those systems.
#define LIFE_PHASE_INPUT 1
#define LIFE_PHASE_BODY 2
#define LIFE_PHASE_MIND 3
#define LIFE_PHASE_OUTPUT 4
#define LIFE_PHASE_TAIL 5

// --- tick() results ------------------------------------------------------------------------
// Strings, so no legacy return value (TRUE, 1, a flag) can be mistaken for a scheduler code.
/// Nothing left to do until woken: clears the system's wake bit.
#define LIFE_SLEEP "life_sleep"
/// End this mob's cycle now (the old early `return` before `..()` in a Life() override).
#define LIFE_HALT "life_halt"

// --- Wake bits (/mob/living/var/life_awake) -------------------------------------------------
// One bit per concern; several systems may share a bit. wake(bits) sets them.
#define LIFE_SYS_TRAITS (1<<0)
#define LIFE_SYS_UPKEEP (1<<1)
#define LIFE_SYS_BREATHING (1<<2)
#define LIFE_SYS_THERMAL (1<<3)
#define LIFE_SYS_RADIATION (1<<4)
#define LIFE_SYS_METABOLISM (1<<5)
#define LIFE_SYS_BODY (1<<6)
#define LIFE_SYS_BLOOD (1<<7)
#define LIFE_SYS_ORGANS (1<<8)
#define LIFE_SYS_NUTRITION (1<<9)
#define LIFE_SYS_GENETICS (1<<10)
#define LIFE_SYS_STATUS (1<<11)
#define LIFE_SYS_ADDICTION (1<<12)
#define LIFE_SYS_SENSES (1<<13)
#define LIFE_SYS_IDENTITY (1<<14)
#define LIFE_SYS_HUD (1<<15)
#define LIFE_SYS_CLIENT (1<<16)
#define LIFE_SYS_MOVEMENT (1<<17)
#define LIFE_SYS_MACHINE (1<<18)
#define LIFE_SYS_BEHAVIOUR (1<<19)
#define LIFE_SYS_GATE (1<<20)
#define LIFE_SYS_ALL ((1<<21) - 1)

// --- Segments (/datum/life_context/var/blocked) ---------------------------------------------
// A segment is the run of code that followed an early `return` in a legacy Life() or an
// `if` around a block of hooks. A gate system blocks its segment; the scheduler then skips
// every system tagged with it for the rest of the cycle.
/// /mob/living core after `if(transforming) return` / `if(!loc) return`.
#define LIFE_SEG_LIVING (1<<0)
/// /mob/living core inside `if(stat != DEAD)`.
#define LIFE_SEG_LIVING_ALIVE (1<<1)
/// /mob/living core inside `if(handle_regular_status_updates())`.
#define LIFE_SEG_LIVING_STATUS (1<<2)
/// Human tail inside `if(!stasis) if(stat != DEAD)`.
#define LIFE_SEG_HUMAN_LIVE (1<<3)
/// Human tail inside `if(!stasis) else if(stat == DEAD)`.
#define LIFE_SEG_HUMAN_DEAD (1<<4)
/// Simple mob core after `if(stat >= DEAD) return FALSE`.
#define LIFE_SEG_SIMPLE (1<<5)

// --- Life sets (/mob/living/var/life_set) ---------------------------------------------------
// Which family of Life sequences a mob runs. The legacy silicon Life() procs never called
// the /mob/living parent, so they compose from their own families.
#define LIFE_SET_LIVING (1<<0)
#define LIFE_SET_ROBOT (1<<1)
#define LIFE_SET_AI (1<<2)
#define LIFE_SET_PAI (1<<3)
#define LIFE_SET_DECOY (1<<4)
/// Mobs whose Life() only removes them from the mob lists (dummies, announcers).
#define LIFE_SET_DELIST (1<<5)

// --- Hibernation (doc/mob_life_architecture.md §4.3, §4.9) ---------------------------------
/// Default for GLOB.mob_hibernation_enabled: a mob whose systems are all asleep leaves the
/// SSmobs run until life_wake(). On for every mob, players included. The GLOB var is the
/// runtime switch (benchmarks and admins flip it).
#define MOB_HIBERNATION_ENABLED TRUE
/// Default for GLOB.mob_hibernation_trace: log every hibernate and wake transition
/// (MOB_HIBERNATE lines). Off by default because it is one line per transition.
#define MOB_HIBERNATION_TRACE FALSE
/// How often SSmobs audits sleeping mobs for a missed wake.
#define MOB_HIBERNATION_AUDIT_INTERVAL (30 SECONDS)
/// Hibernating mobs checked per audit (round robin).
#define MOB_HIBERNATION_AUDIT_SAMPLE 400
/// Awake mobs with sleeping systems checked per audit (round robin).
#define MOB_HIBERNATION_AUDIT_AWAKE_SAMPLE 100
/// Segments a dead mob never runs (the alive gate, the status system and the simple and
/// human vitals gates block them), so the audit doesn't expect their systems to be idle.
#define LIFE_SEGS_BLOCKED_WHEN_DEAD (LIFE_SEG_LIVING_ALIVE | LIFE_SEG_LIVING_STATUS | LIFE_SEG_HUMAN_LIVE | LIFE_SEG_SIMPLE)

// --- Wake groups: the bits a producer wakes --------------------------------------------------
/// The body changed: injury, treatment, affliction, factor or reagent change.
#define LIFE_WAKE_BODY (LIFE_SYS_BODY | LIFE_SYS_METABOLISM | LIFE_SYS_HUD | LIFE_SYS_IDENTITY)
/// A stun, weaken, paralysis, sleep, confusion or blindness setter ran.
#define LIFE_WAKE_STATUS (LIFE_SYS_STATUS | LIFE_SYS_MOVEMENT | LIFE_SYS_GENETICS | LIFE_SYS_HUD)
/// The mob moved: new air, area, light, gravity and hazards.
#define LIFE_WAKE_MOVED (LIFE_SYS_BREATHING | LIFE_SYS_THERMAL | LIFE_SYS_MOVEMENT | LIFE_SYS_SENSES | LIFE_SYS_UPKEEP | LIFE_SYS_HUD | LIFE_SYS_IDENTITY)
/// Something was equipped or unequipped: sight, voice, name, insulation, internals.
#define LIFE_WAKE_EQUIPMENT (LIFE_SYS_SENSES | LIFE_SYS_IDENTITY | LIFE_SYS_HUD | LIFE_SYS_THERMAL | LIFE_SYS_BREATHING | LIFE_SYS_MOVEMENT)

/// Nominal seconds between two Life() calls for one mob (SSmobs wait x slices).
#define LIFE_NOMINAL_SECONDS 2
