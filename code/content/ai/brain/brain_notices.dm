// Occurrences announced with PUBLISH(E, name, field = v): nothing can refuse them, so each is a FIXED ACTION whose notice (the past-tense
// /datum/notice/x of the same name) is generated with the fields below (doc/rewrite/final_api.html sections 8 and 10).

/// --------------------------------------------------------------------------- Signals emitted on the mob by the brain framework. Behaviors can subscribe to these via their eval_triggers list to re-evaluate only when relevant. ---------------------------------------------------------------------------
ACTION(dqai_damage_taken, amount, injury_kind, attacker, FIXED, notice = /datum/notice/dqai_damage_taken)
