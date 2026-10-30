/mob/living/simple_mob/animal/space/goose
	name = "goose"
	desc = "It looks pretty angry!"
	tt_desc = "E Branta canadensis" //that iconstate is just a regular goose
	icon_state = "goose"
	icon_living = "goose"
	icon_dead = "goose_dead"


	endurance = 30

	response_help = "pets the"
	response_disarm = "gently pushes aside the"
	response_harm = "hits the"

	harm_intent_damage = 5
	melee_damage_lower = 5 //they're meant to be annoying, not threatening.
	melee_damage_upper = 5 //unless there's like a dozen of them, then you're screwed.
	attacktext = list("pecked")
	attack_sound = SFX_WEAPONS_BITE

	organ_names = /datum/decl/mob_organ_names/goose

	has_langs = list(LANGUAGE_ANIMAL)


CAPABILITIES(/mob/living/simple_mob/animal/space/goose)
	op("berserk", menu(), label("Berserk"), needs(req_self(), req_capable()), then(PROC_REF(berserk_op)))
	configure(mob_rules(faction = FACTION_GEESE))
	configure(butchery_rules(meat_type = /obj/item/reagent_containers/food/snacks/meat/chicken, meat_amount = 3))
	profile(nameof(vore_prefs), /datum/record/vore_prefs, fields = list("can_be_drop_prey" = FALSE))


/datum/say_list/goose
	speak = list("HONK!")
	emote_hear = list("honks loudly!")
	say_maybe_target = list("Honk?")
	say_got_target = list("HONK!!!")

/mob/living/simple_mob/animal/space/goose/life_special(datum/seq_frame/life/F)
	if(((src.ai_brain ? (src.ai_brain.primary_threat ? STANCE_FIGHT : STANCE_IDLE) : STANCE_IDLE) in list(STANCE_APPROACH, STANCE_FIGHT)) && !is_working() && isturf(src.loc))
		if(src.vitality() <= 0.5) // At half health, and fighting someone currently.
			src.berserk()

/mob/living/simple_mob/animal/space/goose/proc/berserk()
	apply_body_effect(/datum/body_effect/berserk, 30 SECONDS)

/mob/living/simple_mob/animal/space/goose/proc/berserk_op(datum/act/op/A)
	berserk()

/datum/decl/mob_organ_names/goose
TYPE_TABLE(/datum/decl/mob_organ_names/goose, mob_organ_hit_zones, list("head", "chest", "left leg", "right leg", "left wing", "right wing", "neck"))

/mob/living/simple_mob/animal/space/goose/white
	icon = 'icons/mob/animal_vr.dmi'
	icon_state = "whitegoose"
	icon_living = "whitegoose"
	icon_dead = "whitegoose_dead"
	name = "white goose"
	desc = "And just when you thought it was a lovely day..."

/mob/living/simple_mob/animal/space/goose/domesticated
	name = "domesticated goose"
	desc = "It's a domesticated goose. It still looks pretty angry."

CAPABILITIES(/mob/living/simple_mob/animal/space/goose/domesticated)
	configure(mob_rules(faction = "neutral"))
	profile(nameof(vore_prefs), /datum/record/vore_prefs, fields = list("can_be_drop_prey" = TRUE))


/mob/living/simple_mob/animal/space/goose/domesticated/casino
	name = "Donella"
	desc = "It's a golden goose named Donella, she is a beloved treasure of the golden goose casino, nobody knows where she comes from."
	icon_state = "golden_goose"
	icon_living = "golden_goose"
	icon_dead = "golden_goose_dead"
	icon = 'icons/mob/animal.dmi'


	endurance = 75

	harm_intent_damage = 10
	melee_damage_lower = 10
	melee_damage_upper = 10

CAPABILITIES(/mob/living/simple_mob/animal/space/goose/domesticated/casino)
	configure(mob_rules(faction = "neutral"))


// === merged from goose_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/datum/category_item/catalogue/fauna/geese
	name = "Planetary Fauna - Geese"
	desc = "A goose. HONK. Not much to catalogue, they're exactly the same as their earth counterparts."
	value = CATALOGUER_REWARD_EASY

/mob/living/simple_mob/animal/space/goose/virgo3b

CAPABILITIES(/mob/living/simple_mob/animal/space/goose/virgo3b)
	configure(mob_rules(faction = FACTION_VIRGO3B))
