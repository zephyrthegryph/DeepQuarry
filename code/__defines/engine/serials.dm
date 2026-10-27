// Serial numbers (doc/rewrite/proposals/relations.md D9a): the one declared form for a number that is player-facing or saved data
// ("DQ-12", an NTNet card id, a power cell's number, a SQL round number). A serial is not a handle: it never finds the entity again
// (ref_token() / resolve_token() do that), it is a record field that counts up.
//
// Declare a kind once, next to its owner, then take numbers from it:
//   SERIAL_DEF(contract, 1, FALSE)
//   contract.id = "DQ-[next_serial(contract)]"
// One counter per kind, created on first use. A kind is round-scoped (it starts again at `first` each round) unless it is declared
// persisted: a persisted kind counts on from a number kept elsewhere, so its owner seeds it (serial_seed(kind, last_issued)) from the
// database or the save before it issues, and issuing from an unseeded persisted kind is refused (null, reported). A keyed take
// (next_serial_keyed(kind, key)) counts one run per key. Seeds, resets and each kind's first number are logged.

/// Declares the serial kind `kind`: /datum/serial/<kind>. `first_number` is the first number issued, `persist` TRUE for a kind that is seeded
/// from saved data.
#define SERIAL_DEF(kind, first_number, persist) /datum/serial/##kind{first = first_number; persisted = persist}

/// The next number of a serial kind (a SERIAL_DEF name).
#define next_serial(kind) serial_issue(/datum/serial/##kind)
/// The next number of `key`'s own run of a serial kind.
#define next_serial_keyed(kind, key) serial_issue(/datum/serial/##kind, key)
/// Seeds a persisted kind: the next number issued is last_issued + 1. Returns the seed.
#define serial_seed(kind, last_issued) serial_seed_kind(/datum/serial/##kind, last_issued)
/// Starts a round-scoped kind again at its first number.
#define serial_reset(kind) serial_reset_kind(/datum/serial/##kind)
