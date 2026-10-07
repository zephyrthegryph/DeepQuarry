// Stat declarations (doc/rewrite/final_api.html, section 5). STAT(T, name, RULE, ...) declares the stat; `analyze gen declare_ids` writes its
// id, STAT_<NAME>, into code/engine/_generated/ids.dm, so nothing here carries a number. These are the base stats of section 5 ("Base stats,
// declared once"); they belong in code/base/<type>/ (section 22) once E3 lands.

STAT(/obj/machinery, operable, ALL, virtual = TRUE)
STAT(/obj/machinery, power_draw, SUM, virtual = TRUE)
/// The machine has power for its controls: false while any source holds it down (its area channel is dark: area_gives_power(); SRC_GRID is the manual override set_powered() holds). The NOPOWER condition bit.
STAT(/obj/machinery, has_power, ALL, base = TRUE, virtual = TRUE)
/// The machine is under maintenance (the MAINT bit): true while any source holds it so (SRC_MAINTENANCE: an open service hatch).
STAT(/obj/machinery, in_maintenance, ANY, virtual = TRUE)
/// The machine's own switch is on: false while the switch holds it off (SRC_SWITCH; the POWEROFF bit). It does not stop the machine being operable.
STAT(/obj/machinery, switched_on, ALL, base = TRUE, virtual = TRUE)
/// The machine is whole: false while any source holds it broken (SRC_DAMAGE: atom_break() until atom_fix()). The BROKEN condition bit, inverted.
STAT(/obj/machinery, intact, ALL, base = TRUE, virtual = TRUE)
/// Body effect type -> its stack count: one hold per applied effect (hold(L, STAT_BODY_EFFECT_COUNTS, stacks, L, key = path)); read with body_effects().
STAT(/mob/living, body_effect_counts, SUM_PER_KEY, virtual = TRUE)
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
/// What the area's machines ask of each power channel, in watts: the sum of their contributions (contributes_to(nameof(power_area), ...) in
/// `/obj/machinery`'s capabilities). The APC supplies it; nothing keeps a tally of it (doc/rewrite/power_grid.md).
STAT(/area, demand_equip, SUM, virtual = TRUE)
STAT(/area, demand_light, SUM, virtual = TRUE)
STAT(/area, demand_environ, SUM, virtual = TRUE)

