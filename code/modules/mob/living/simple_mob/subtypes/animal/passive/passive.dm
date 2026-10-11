// Passive mobs can't attack things, and will run away instead.
// They can also be displaced by all mobs.
/mob/living/simple_mob/animal/passive
	mob_bump_flag = 0

CAPABILITIES(/mob/living/simple_mob/animal/passive)
	profile(nameof(vore_prefs), /datum/record/vore_prefs, fields = list("allow_mind_transfer" = TRUE))
