/mob/living/simple_mob/humanoid/cultist //Do not spawn this on in directly it is simply a base for the rest namely the unique death animations.
	name = "Cultist"
	desc = "An awfully frail and ghastly looking individual"
	tt_desc = "NULL"
	icon = 'icons/mob/cultists.dmi'
	icon_state = "initiate"

CAPABILITIES(/mob/living/simple_mob/humanoid/cultist)
	configure(mob_rules(faction = "cult"))
	configure(mob_kind(mob_class = MOB_CLASS_DEMONIC))
