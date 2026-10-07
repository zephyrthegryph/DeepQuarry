// Stat declarations (doc/rewrite/final_api.html, section 5). STAT(T, name, RULE, ...) declares the stat; `analyze gen declare_ids` writes its
// id, STAT_<NAME>, into code/engine/_generated/ids.dm, so nothing here carries a number. These are the base stats of section 5 ("Base stats,
// declared once"); they belong in code/base/<type>/ (section 22) once E3 lands.

STAT(/obj/machinery, operable, ALL, virtual = TRUE)
STAT(/obj/machinery, power_draw, SUM, virtual = TRUE)
STAT(/mob/living, can_act, ALL)
STAT(/mob/living, can_move, ALL)
STAT(/mob/living, acts_via, MASK_AND, base = ORIGIN_ALL)
STAT(/atom, density, TOP)
STAT(/atom, opacity, ANY)
STAT(/atom, invisibility, MAX)
STAT(/atom, light_range, MAX, virtual = TRUE)
/// Held while the entity is set aside (absorbed prey, a body kept for reforming): Life admits no frame and its own-clock timers and cadences pause.
/// hold(E, STAT_SUSPENDED, TRUE, source) / release(E, STAT_SUSPENDED, source).
STAT(/datum, suspended, ANY, virtual = TRUE)
STAT(/atom, clock_rate, MIN, base = 1, virtual = TRUE)
/// How much anything cares about this entity now (RELEVANCE_*): the highest level any source holds. A sequence with min_relevance sweeps a member only
/// at or above it; hold(E, STAT_RELEVANCE, RELEVANCE_NEAR, source) / release(E, STAT_RELEVANCE, source), and a datum source deleted drops its hold.
STAT(/datum, relevance, MAX, base = RELEVANCE_NONE, virtual = TRUE)
STAT(/mob/living, clock_rate_bio, MIN, base = 1)
/// What a brain's mob brings to a pack's leader election (code/modules/combat_ai/roles/roles.dm): the lord role +100 and the alpha trait +30 are holds on it.
STAT(/mob/living, ai_authority, SUM, base = 0, virtual = TRUE)
STAT(/area, lights_nightshift, ANY)
STAT(/area, lights_emergency_off, ANY)

