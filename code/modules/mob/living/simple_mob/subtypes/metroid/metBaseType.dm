// The top-level metroid defines. Xenobio slimes and feral slimes will inherit from this. Stolen from as much slime code as possible.

/mob/living/simple_mob/metroid
	name = "metroid"
	desc = "Some sort of person eaty thing! This is the prototype mob and shouldn't be spawned. If you see this, yell at your local dev or event manager who spawned this one >.>"
	tt_desc = "Headamus Suckumus"
	icon = 'icons/mob/metroid/small.dmi'
	icon_state = "metroid"
	icon_living = "metroid"
	icon_dead = "metroid_dead"
	layer = MOB_LAYER + 1 // Need them on top of other mobs or it looks weird when consuming something.
	var/icon_state_override = null // Used for special slime appearances like the rainbow slime.
	gender = NEUTER

	faction = "metroids"
	endurance = 25
	movement_cooldown = 1.7
	pass_flags = PASSTABLE

	response_help = "pets"

	// Atmos stuff.
	minbodytemp = T0C-30
	heat_damage_per_tick = 0
	cold_damage_per_tick = 40

	min_oxy = 0
	max_oxy = 0
	min_tox = 0
	max_tox = 0
	min_co2 = 0
	max_co2 = 0
	min_n2 = 0
	max_n2 = 0
	unsuitable_atoms_damage = 0

	melee_damage_lower = 10
	melee_damage_upper = 15
	attack_sound = SFX_METROID_METROIDATTACK
	attacktext = list("suckulated")
	speak_emote = list("chirps")
	friendly = list("pokes")

	say_list_type = /datum/say_list/metroid

	harm_intent_damage = 5 //When someone uses fists. Default is 3

	vore_active = 1
	vore_pounce_chance = 25
	vore_icons = SA_ICON_LIVING

	max_nutrition = 2200
	var/evo_point = 0
	var/evo_limit = 0
	var/next



/// The screech it gives as it appears (after_init()), or null for a quiet kind.
/mob/living/simple_mob/metroid/var/arrival_sound = null

/mob/living/simple_mob/metroid/proc/screech_on_arrival(datum/act/timer/A)
	if(arrival_sound)
		play_sfx(src, arrival_sound)

CAPABILITIES(/mob/living/simple_mob/metroid)
	configure(mob_kind(mob_class = MOB_CLASS_SLIME, attack_cooldown = 10))
	configure(mob_movement(makes_dirt = FALSE))
	after_init(0, then(PROC_REF(screech_on_arrival)))
	verb_entry(/mob/living/proc/ventcrawl) // TGPanel //May not do anything at the moment.


/datum/say_list/metroid
	speak = list("Skree.", "Eree.", "Errer?")
	emote_see = list("floats about","looks around", "rubs its talons")
	emote_hear = list("chitters")
	say_understood = list("Eree.")
	say_cannot = list("Errerr.")
	say_maybe_target = list("Eree?")
	say_got_target = list("Ereet!")
	say_threaten = list("Skree!")
	say_stand_down = list("Eee.")
	say_escalate = list("SKREE!")
	threaten_sound = 'sound/metroid/metroidsee.ogg'
	stand_down_sound = 'sound/metroid/metroiddetach.ogg'


/mob/living/simple_mob/metroid/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected_of(src)
	B.set_digest_brute(1)
	B.set_digest_burn(1)
	B.set_vore_verb("swallow")
	B.name = "membrane" //THERE IS A RUNTIME HERE SOMEHOW
	B.desc	= "The metroid positions itself above you and swoops down, lazily enveloping you through its tight mouth and sending you straight to its bulbous membrane for all to see."
	B.own_emote_lists()
	B.set_emote_lists_at(DM_HOLD, list(
	"The metroid's cortex tentacles wriggle over you, violating and teasing you as they sopped you in viscous slime.",
	"The cortex you are forced against pulses with life, gently squeezing you between it and the stretchy membrane around you.",
	"You press your face against the transparent membrane, watching how the world distorts as it stretches over your eyes.",
	"The air around you is so thick. You struggle to breathe occasionally, choking on the heat and moisture.",
	"You struggle a bit, making the membrane swell out."
	))
	B.own_emote_lists()
	B.set_emote_lists_at(DM_DIGEST, list(
	"The cortex tentacles are pulsating like lines of power streaking away from you as it drains you. Waves of sleepiness wash over you as the areas most closest to the tentacles are drained of energy.",
	"The air feels a tinge incendiary as the cortex you rest on heats up, fueled by your own body as the metroid draws your strenght away from you.",
	"As you grow weaker, your movements against the membrane grow weaker as well, making you feel as if the membrane is closing around you, wrapping and squeezing you, draining you for all you are worth.",
	"You feel faint as the tentacles wrapped around you sap you of your strength, seemingly eager to drain and claim you for food."
	))
	B.set_digest_messages_prey(list(
	"You can't stay awake anymore, the clear world around you going fuzzy until you can see it no more.",
	"The tinge of the air grows to a crescendo and then fades away, just as the rest of your body fizzles into energy for the metroid.",
	"The tentacles squeeze you one last time as the last of your energy is sapped and your body is claimed as food for the metroid.",
	"The metroid swells as it absorbs the rest of your life force and nutrients into its body, making it stronger and even hungry for more."
	))

/mob/living/simple_mob/metroid/on_death(gibbed)
	..()


/mob/living/simple_mob/metroid/starting_nutrition() //This actually gets overridden further down on initialize.
	return 1000

/mob/living/simple_mob/metroid/starting_nutrition() //Have them start off pretty hungry still.
	return 100
