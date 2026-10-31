// The one clock read, and the stamp form built on it (doc/rewrite/final_api.html section 3).
//
// TIME_NOW(clock, owner) is "now" on a clock: CLOCK_WORLD is world.time (real game time, owner not needed); CLOCK_OWN is the owner's timer clock
// (timer_clock(): bio for living mobs, machine for machinery), which slows with the domain's rate and stops in stasis/suspension, exactly like
// after() timers on that datum. Payload and list-slot sites that record "now" call it directly: TIME_NOW(CLOCK_WORLD).
//
// An END time ("until": a stun, a lease, a guest pass) is a COOLDOWN (code/defines/engine/cooldowns.dm), defined on TIME_NOW. A START time
// ("how long since": a time of death, the last hit) is STAMP/ELAPSED here:
//
//   STAMP(src, started_at, CLOCK_WORLD)          // record "now"
//   ELAPSED(src, started_at, CLOCK_WORLD)        // deciseconds since the stamp
//
// The clock is part of the value's meaning, so every read passes the same clock the write used.

/// "Now" on `clock`; `owner` is the datum whose own clock CLOCK_OWN reads (omit it for CLOCK_WORLD).
#define TIME_NOW(clock, owner...) ((clock) ? own_clock_now(owner) : world.time)

/// Records "now" on `clock` in the var `name` of D. The pair of ELAPSED; a base type's stamp is a table slot (stamp_now(), sparse_slots.dm).
#define STAMP(D, name, clock) (D.name = TIME_NOW(clock, D))
#define ELAPSED(D, name, clock) (TIME_NOW(clock, D) - D.name)
