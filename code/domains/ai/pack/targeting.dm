// Pack targeting (doc/rewrite/ai_packs.md B3): the pack decides who each member fights, once, and members read the assignment.
//
// A member's selector chain still picks its own target from the hostiles it knows, but from the list the pack hands it (targeting_candidates()):
//   PACK_SPREAD (the default): targets that already hold `spread_cap` other members are left out, so a pack fans out over its hostiles instead of
//     all biting the nearest. When every target is full the member takes the whole list (it is never left with nobody to fight).
//   PACK_FOCUS: a member that knows the leader's target takes it; everyone shares the leader's fight.
// A pack of one is handed its own list unchanged, so it targets exactly as the per-brain code did.

/// The hostiles `B` may choose its target from, under the pack's doctrine.
/datum/ai_pack/proc/targeting_candidates(datum/ai_brain/B)
	var/list/known = B.model?.visible_hostiles
	if(!length(known) || length(members) <= 1)
		return known
	var/datum/faction_data/data = faction_data()
	if(data.pack_doctrine == PACK_FOCUS)
		var/mob/living/focus = leader?.primary_threat
		if(focus && leader != B && (focus in known))
			return list(focus)
		return known
	var/list/load = list()
	for(var/datum/ai_brain/other as anything in members)
		if(other == B || !other.primary_threat)
			continue
		load[other.primary_threat] += 1
	var/list/open = list()
	for(var/mob/living/M as anything in known)
		if((load[M] || 0) < data.spread_cap)
			open += M
	return length(open) ? open : known
