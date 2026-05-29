// Passive mobs can't attack things, and will run away instead.
// They can also be displaced by all mobs.
/mob/living/simple_mob/animal/passive
	mob_bump_flag = 0
	allow_mind_transfer = TRUE
