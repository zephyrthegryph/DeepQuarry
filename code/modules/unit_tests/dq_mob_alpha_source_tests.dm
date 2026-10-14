// Mob alpha writers must not clobber other contributors (no source tracking).
// See code/modules/mob/_alpha_sources.dm.
//
// underwater_stealth, ambush and the robot cloak used to write holder.alpha
// directly and reset it to a hardcoded 255 on expiry. If two such effects
// were ever active on the same mob at once, whichever one expired first would
// blow the mob back to fully opaque out from under the still-active one, and
// whichever expired last would stomp the other's contribution on the way out.

/datum/unit_test/dq_mob_alpha_sources_combine_and_dont_clobber

/datum/unit_test/dq_mob_alpha_sources_combine_and_dont_clobber/Run()
	var/mob/living/carbon/human/H = new(null)

	TEST_ASSERT_EQUAL(stat_value(H, STAT_ALPHA_MULT), 1, "a fresh mob should have no active alpha sources")

	// One stealth-style effect engages: 30/255 opacity (the cult "ambush" value).
	H.set_alpha_source(SRC_ALPHA_AMBUSH, 30/255)
	TEST_ASSERT(H.alpha == 30, "a single alpha source should set alpha directly to its multiplier, got [H.alpha]")

	// A second, independent effect engages on top of it: 50/255 (underwater stealth).
	H.set_alpha_source(SRC_ALPHA_UNDERWATER_STEALTH, 50/255)
	var/expected_combined = round(255 * (30/255) * (50/255))
	TEST_ASSERT(H.alpha == expected_combined, "two concurrent alpha sources should combine multiplicatively, expected [expected_combined], got [H.alpha]")
	TEST_ASSERT(H.alpha != 30 && H.alpha != 50, "the combined alpha should reflect both sources, not just the most recently applied one")

	// The first effect expires. This must NOT snap the mob back to fully
	// opaque (255) -- the second effect is still active and clobbering it
	// would be exactly the historical bug.
	H.clear_alpha_source(SRC_ALPHA_AMBUSH)
	TEST_ASSERT(H.alpha == 50, "clearing one source while another is still active should leave only the remaining source's alpha, expected 50, got [H.alpha]")
	TEST_ASSERT(H.alpha != 255, "clearing one of two active sources must not reset the mob to fully opaque while the other is still active")

	// The second effect expires too. Now, and only now, full opacity returns.
	H.clear_alpha_source(SRC_ALPHA_UNDERWATER_STEALTH)
	TEST_ASSERT_EQUAL(stat_value(H, STAT_ALPHA_MULT), 1, "clearing the last source should leave no sources held")
	TEST_ASSERT(H.alpha == 255, "clearing the last active alpha source should restore full opacity, got [H.alpha]")

	qdel(H)

/// The same scenario, but driven through the real body effects (ambush and
/// underwater_stealth) instead of calling the alpha-source procs directly,
/// to prove the effects themselves were actually converted.
/datum/unit_test/dq_ambush_and_underwater_stealth_modifiers_dont_clobber_each_other

/datum/unit_test/dq_ambush_and_underwater_stealth_modifiers_dont_clobber_each_other/Run()
	var/mob/living/carbon/human/H = new(null)

	var/ambush_mod = H.apply_body_effect(/datum/body_effect/ambush)
	TEST_ASSERT(ambush_mod, "ambush modifier should have applied to a fresh human")
	TEST_ASSERT(H.alpha == 30, "ambush should fade the wearer to alpha 30, got [H.alpha]")

	var/water_mod = H.apply_body_effect(/datum/body_effect/underwater_stealth)
	TEST_ASSERT(water_mod, "underwater_stealth modifier should have applied on top of ambush")
	var/expected_combined = round(255 * (30/255) * (50/255))
	TEST_ASSERT(H.alpha == expected_combined, "both modifiers active should combine, expected [expected_combined], got [H.alpha]")

	// Expire ambush first (order matters for the historical bug: the *first*
	// one to expire is the one whose blind "reset to 255" would clobber the
	// other still-active modifier).
	H.remove_body_effect(/datum/body_effect/ambush, silent = TRUE)
	TEST_ASSERT(H.alpha == 50, "expiring ambush while underwater_stealth is still active should leave alpha at underwater_stealth's own value, got [H.alpha]")

	H.remove_body_effect(/datum/body_effect/underwater_stealth, silent = TRUE)
	TEST_ASSERT(H.alpha == 255, "expiring the last active modifier should restore full opacity, got [H.alpha]")

	qdel(H)
