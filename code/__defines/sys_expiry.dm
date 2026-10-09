// Expiry: state that ends (doc/rewrite/systems.md section 17).
//
// A COOLDOWN (code/__defines/cooldowns.dm) is a gate: "not more than once per N". An expiry is
// state with an end: a stun until, a lease, a guest pass, a flash that fades. ELAPSED reads how
// long ago something was recorded (a start stamp, time of death, the last hit).
//
//   EXPIRY_DECLARE(stun_until)                   // the var (0 = never set)
//   EXPIRY_SET(src, stun_until, 5 SECONDS, CLOCK_WORLD)
//   EXPIRY_ACTIVE(src, stun_until, CLOCK_WORLD)  // TRUE until it runs out
//   EXPIRY_LEFT(src, stun_until, CLOCK_WORLD)    // deciseconds left, 0 when expired
//   EXPIRY_CLEAR(src, stun_until)
//   EXPIRY_STAMP(src, started_at, CLOCK_WORLD)   // record "now"
//   ELAPSED(src, started_at, CLOCK_WORLD)        // deciseconds since the stamp
//
// The clock is part of the value's meaning, so every read passes the same clock the write used:
//   CLOCK_WORLD  world.time (real game time).
//   CLOCK_OWN    the datum's OM timer clock (timer_clock(): bio for living mobs, machine for
//                machinery): it slows with the domain's rate and stops in stasis/suspension,
//                exactly like after() timers on that datum.
// A stored value is a point on that clock; EXPIRY_AT(D, clock, delay) computes one without a var
// (for list slots and records).


/// "Now" on `clock` for datum D.
#define EXPIRY_NOW(D, clock) ((clock) ? expiry_clock_now(D) : world.time)
/// The point on D's `clock` that is `delay` from now.
#define EXPIRY_AT(D, clock, delay) (EXPIRY_NOW(D, clock) + (delay))

#define EXPIRY_DECLARE(name) var/##name = 0
#define EXPIRY_TMP_DECLARE(name) var/tmp/##name = 0
#define STATIC_EXPIRY_DECLARE(name) var/static/##name = 0

#define EXPIRY_SET(D, name, delay, clock) (D.name = expiry_written(D, #name, EXPIRY_AT(D, clock, delay)))
/// Extends to at least `delay` from now (never shortens a longer expiry).
#define EXPIRY_EXTEND(D, name, delay, clock) (D.name = expiry_written(D, #name, max(D.name, EXPIRY_AT(D, clock, delay))))
#define EXPIRY_CLEAR(D, name) (D.name = 0)

/// Declares that PROC runs on the holder when `name` lapses on `clock`, however the holder was
/// created: armed by every EXPIRY_SET/EXPIRY_EXTEND and at materialize (code/datums/sys/expiry.dm).
/// The hook must be idempotent. `EXPIRY_ON_LAPSE(/obj/item/card/id/guest, expiration_time, CLOCK_WORLD, PROC_REF(pass_lapsed))`
#define EXPIRY_ON_LAPSE(PATH, name, clock, PROC) _LIFECYCLE_DECL(PATH, add_expiry_hook(#name, clock, PROC))
#define EXPIRY_ACTIVE(D, name, clock) (D.name > EXPIRY_NOW(D, clock))
#define EXPIRY_EXPIRED(D, name, clock) (D.name <= EXPIRY_NOW(D, clock))
#define EXPIRY_LEFT(D, name, clock) max(0, D.name - EXPIRY_NOW(D, clock))

#define EXPIRY_STAMP(D, name, clock) (D.name = EXPIRY_NOW(D, clock))
#define ELAPSED(D, name, clock) (EXPIRY_NOW(D, clock) - D.name)
/// Elapsed since a raw point (a list slot, a local) on D's clock.
#define ELAPSED_SINCE(D, point, clock) (EXPIRY_NOW(D, clock) - (point))
/// Deciseconds from now until a raw point, 0 when past.
#define LEFT_UNTIL(D, point, clock) max(0, (point) - EXPIRY_NOW(D, clock))
/// TRUE while a raw point is still in the future.
#define BEFORE(D, point, clock) ((point) > EXPIRY_NOW(D, clock))
