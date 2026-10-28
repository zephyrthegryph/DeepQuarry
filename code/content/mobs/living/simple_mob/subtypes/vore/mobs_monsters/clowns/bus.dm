/mob/living/simple_mob/clowns/big/c_shift
	tt_desc = "E Homo sapiens corydon horrificus" //this is a redspace clown
	faction = FACTION_CLOWN

CAPABILITIES(/mob/living/simple_mob/clowns/big/c_shift)
	owns_one(nameof(shadekin), /datum/shadekin, starts = nameof(shadekin_type))
