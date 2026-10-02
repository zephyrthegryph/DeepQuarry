// Stat ids (doc/rewrite/final_api.html, section 5). STAT(T, name, RULE, ...) declares the var, its base and the id
// STAT_<NAME>; E3's generator emits the ids into code/engine/_generated/. Until it lands these are the hand-assigned ids
// of the base stats of section 5 ("Base stats, declared once") and of the E0 fixtures, so the contracts, the driver and the
// proofs can name them. One id per name, never renumbered: the generator reads this file and keeps what is here.
//
// The declarations themselves belong in code/base/<type>/ (section 22) once E3 lands; they are listed here as markers so
// the generator has the rule and base of each next to its id.

STAT(/obj/machinery, operable, ALL)
STAT(/obj/machinery, power_draw, SUM)
STAT(/mob/living, can_act, ALL)
STAT(/mob/living, can_move, ALL)
STAT(/mob/living, acts_via, MASK_AND, base = ORIGIN_ALL)
STAT(/atom, density, TOP)
STAT(/atom, opacity, ANY)
STAT(/atom, invisibility, MAX)
STAT(/atom, light_range, MAX)
STAT(/atom/movable, suspended, ANY)
STAT(/atom, clock_rate, MIN, base = 1)
STAT(/mob/living, clock_rate_bio, MIN, base = 1)
STAT(/area, lights_nightshift, ANY)

#define STAT_OPERABLE 1
#define STAT_POWER_DRAW 2
#define STAT_CAN_ACT 3
#define STAT_CAN_MOVE 4
#define STAT_ACTS_VIA 5
#define STAT_DENSITY 6
#define STAT_OPACITY 7
#define STAT_INVISIBILITY 8
#define STAT_LIGHT_RANGE 9
#define STAT_SUSPENDED 10
#define STAT_CLOCK_RATE 11
#define STAT_CLOCK_RATE_BIO 12
#define STAT_LIGHTS_NIGHTSHIFT 13
/// The E0 fixtures' own stats (code/tests/engine/): a lamp's reach under the night-shift cascade, proof 8.
#define STAT_E0_LAMP_RANGE 100
