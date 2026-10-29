/mob/living/simple_mob/clowns/big/c_shift
	tt_desc = "E Homo sapiens corydon horrificus" //this is a redspace clown

CAPABILITIES(/mob/living/simple_mob/clowns/big/c_shift)
	configure(mob_rules(faction = FACTION_CLOWN))
	owns_one(nameof(shadekin), /datum/shadekin, starts = nameof(shadekin_type))
