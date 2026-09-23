/// Symptom and reagent emotes are free phrases, not emote keys; they must read
/// as third-person emotes instead of an "Unknown emote" error.
/datum/unit_test/dq_involuntary_emote_conjugation

/datum/unit_test/dq_involuntary_emote_conjugation/Run()
	var/list/cases = list(
		"shudder" = "shudders",
		"wince at their useless arm" = "winces at their useless arm",
		"wipe their brow" = "wipes their brow",
		"clutch their chest" = "clutches their chest",
		"cry" = "cries",
		"stay still" = "stays still",
		"hiss" = "hisses",
	)
	for(var/phrase in cases)
		TEST_ASSERT_EQUAL(third_person_phrase(phrase), cases[phrase], "conjugating '[phrase]'")
