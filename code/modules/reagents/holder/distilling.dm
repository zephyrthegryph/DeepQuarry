/// Returns distilled_reactions_by_reagent so handle_reactions() uses the distilling reaction bucket.
/datum/reagents/distilling/get_reaction_lookup()
	return SSchemistry.distilled_reactions_by_reagent

/// Distilling holders do not track belly-reagent state.
/datum/reagents/distilling/supports_belly_reagents()
	return FALSE

/// Distilling holders do not send COMSIG_REAGENTS_HOLDER_REACTED.
/datum/reagents/distilling/on_reactions_handled(list/effect_reactions)
	return

// handle_reactions() is fully inherited from /datum/reagents via the three hook overrides above.
// No logic is duplicated here — get_reaction_lookup(), supports_belly_reagents(), and
// on_reactions_handled() together select the distilling reaction bucket and suppress the signal.
