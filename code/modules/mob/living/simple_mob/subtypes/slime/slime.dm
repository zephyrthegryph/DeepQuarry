GLOBAL_LIST_INIT(slime_default_emotes, list(
	/datum/decl/emote/audible/moan,
	/datum/decl/emote/visible/twitch,
	/datum/decl/emote/visible/sway,
	/datum/decl/emote/visible/shiver,
	/datum/decl/emote/visible/bounce,
	/datum/decl/emote/visible/jiggle,
	/datum/decl/emote/visible/lightup,
	/datum/decl/emote/visible/vibrate,
	/datum/decl/emote/slime,
	/datum/decl/emote/slime/pout,
	/datum/decl/emote/slime/sad,
	/datum/decl/emote/slime/angry,
	/datum/decl/emote/slime/frown,
	/datum/decl/emote/slime/smile
))

// The top-level slime defines. Xenobio slimes and feral slimes will inherit from this.
/mob/living/simple_mob/slime
	name = "slime"
	desc = "It's a slime."
	tt_desc = "A Macrolimbus vulgaris"
	icon = 'icons/mob/slime2.dmi'
	icon_state = "slime baby"
	icon_living = "slime baby"
	icon_dead = "slime baby dead"
	var/shiny = FALSE // If true, will add a 'shiny' overlay.
	var/icon_state_override = null // Used for special slime appearances like the rainbow slime.
	color = "#CACACA"
	glow_range = 3
	glow_intensity = 2
	gender = NEUTER

	faction = FACTION_SLIME // Note that slimes are hostile to other slimes of different color regardless of faction (unless Unified).
	endurance = 150
	movement_cooldown = -1
	pass_flags = PASSTABLE
	makes_dirt = FALSE	// Goop
	mob_class = MOB_CLASS_SLIME

	response_help = "pets"

	organ_names = /datum/decl/mob_organ_names/slime

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
	shock_resist = 0.5 // Slimes are resistant to electricity, and it actually charges them.
	taser_kill = FALSE
	water_resist = 0 // Slimes are very weak to water.

	melee_damage_lower = 10
	melee_damage_upper = 15
	base_attack_cooldown = 10 // One attack a second.
	attack_sound = SFX_WEAPONS_BITE
	attacktext = list("glomped")
	speak_emote = list("chirps")
	friendly = list("pokes")

	say_list_type = /datum/say_list/slime

	var/cores = 1 // How many cores you get when placed in a Processor.
	var/obj/item/clothing/head/hat = null // The hat the slime may be wearing.
	var/slime_color = "grey" // Used for updating the name and for slime color-ism.
	var/unity = FALSE // If true, slimes will consider other colors as their own.  Other slimes will see this slime as the same color as well.
	var/coretype = /obj/item/slime_extract/grey // What core is inside the slime, and what you get from the processor.
	var/reagent_injected = null // Some slimes inject reagents on attack.  This tells the game what reagent to use.
	var/injection_amount = 5 // This determines how much.
	var/mood = ":3" // Icon to use to display 'mood', as an overlay.

	can_be_drop_prey = FALSE

	species_sounds = "Slime"
	pain_emote_1p = list("squish", "squelch")
	pain_emote_3p = list("squishes", "squelches")

/mob/living/simple_mob/slime/get_available_emotes()
	return GLOB.slime_default_emotes.Copy()

/datum/say_list/slime
	speak = list("Blorp...", "Blop...")
	emote_see = list("bounces", "jiggles", "sways")
	emote_hear = list("squishes")

CAPABILITIES(/mob/living/simple_mob/slime)
	verb_entry(/mob/living/proc/ventcrawl)
	owns_one(nameof(hat), on_destroy = ON_DESTROY_SPILL)

/mob/living/simple_mob/slime/Initialize(mapload)
	update_mood()
	set_glow_color(color)
	refresh_glow()
	update_icon()
	return ..()

// Slime unique items
TYPE_TABLE(/mob/living/simple_mob/slime, ventcrawl_get_item_whitelist, list( \
		VENTCRAWL_BASE_WHITELIST, \
		VENTCRAWL_VORE_WHITELIST, \
		/obj/item/clothing/head, \
		))

/mob/living/simple_mob/slime/on_death(gibbed)
	// Make dead slimes stop glowing.
	set_glow_toggle(FALSE)
	refresh_glow()
	..()

/mob/living/simple_mob/slime/on_revived(reason, datum/source)
	. = ..()
	// Make revived slimes resume glowing.
	set_glow_toggle(initial(glow_toggle))
	refresh_glow()

DECLARE_APPEARANCE_PROC(/mob/living/simple_mob/slime, TYPE_PROC_REF(/atom, appearance_overlays), list())
/mob/living/simple_mob/slime/appearance_overlays()
	. = list()
	. += ..()

	if(stat != DEAD)
		// General slime shine.
		var/image/I = image(icon, src, "slime light")
		I.appearance_flags = RESET_COLOR
		. += I

		// 'Shiny' overlay, for gemstone-slimes.
		if(shiny)
			I = image(icon, src, "slime shiny")
			I.appearance_flags = RESET_COLOR
			. += I

		// Mood overlay.
		I = image(icon, src, "aslime-[mood]")
		I.appearance_flags = RESET_COLOR
		. += I

	// Hat simulator.
	if(hat)
		var/hat_state = hat.item_state ? hat.item_state : hat.icon_state
		var/image/I = image('icons/inventory/head/mob.dmi', src, hat_state)
		I.pixel_y = -7 // Slimes are small.
		I.color = hat.color
		I.appearance_flags = RESET_COLOR | KEEP_APART
		I.blend_mode = BLEND_OVERLAY
		. += I

// Controls the 'mood' overlay. Overrided in subtypes for specific behaviour.
/mob/living/simple_mob/slime/proc/update_mood()
	mood = "feral" // This is to avoid another override in the /feral subtype.

/mob/living/simple_mob/slime/proc/unify()
	unity = TRUE

// Interface override, because slimes are supposed to attack other slimes of different color regardless of faction.
// (unless Unified, of course).
/mob/living/simple_mob/slime/IIsAlly(mob/living/L)
	. = ..()
	if(istype(L, /mob/living/simple_mob/slime)) // Slimes should care about their color subfaction compared to another's.
		var/mob/living/simple_mob/slime/S = L
		if(S.unity || src.unity)
			return TRUE
		if(S.slime_color == src.slime_color)
			return TRUE
		else
			return FALSE
	if(ishuman(L))
		var/mob/living/carbon/human/H = L
		if(istype(H.species, /datum/species/monkey))	// Monke always food
			return FALSE
	// The other stuff was already checked in parent proc, and the . variable will implicitly return the correct value.

// Slimes regenerate passively.
/mob/living/simple_mob/slime/life_special_due()
	return TRUE

/mob/living/simple_mob/slime/life_special(datum/seq_frame/life/F)
	src.mend(TREAT_OXYGENATION, 1)
	src.mend(TREAT_ANTITOXIN, 1)
	src.mend(TREAT_BURN_CARE, 1)
	src.mend(TREAT_GENETIC_REPAIR, 1)
	src.mend(TREAT_TISSUE_REPAIR, 1)

// Clicked on by empty hand.
EXTEND_INTERACTIONS(/mob/living/simple_mob/slime, \
	INTERACT_ITEM(null, PROC_REF(slime_interaction_item)), \
	INTERACT_HAND_UNGATED_AS(I_GRAB, "Take hat off", PROC_REF(slime_interaction_hand)))

/// Old attack_hand: grab the hat off.
/mob/living/simple_mob/slime/proc/slime_interaction_hand(mob/living/L, obj/item/held, datum/interaction/interaction)
	. = TRUE
	if(hat)
		remove_hat(L)
	else
		return FALSE

// Clicked on while holding an object.
/// Old attackby: hat simulator, and weapons may pass through.
/mob/living/simple_mob/slime/proc/slime_interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	. = TRUE
	if(istype(I, /obj/item/clothing/head)) // Handle hat simulator.
		give_hat(I, user)
		return

	var/can_miss = TRUE
	for(var/item_type in allowed_attack_types)
		if(istype(I, item_type))
			can_miss = FALSE
			break

	// Otherwise they're probably fighting the slime.
	if(prob(25) && can_miss)
		act_message(user, src, null, MSG_OTHERS(span_warning("%U%'s %I% passes right through %T%!")), item = I)
		user.setClickCooldown(user.get_attack_speed(I))
		return
	return FALSE

// Called when hit with an active slimebaton (or xeno taser).
// Subtypes react differently.
/mob/living/simple_mob/slime/proc/slimebatoned(mob/living/user, amount)
	return

// Hat simulator
/mob/living/simple_mob/slime/proc/give_hat(obj/item/clothing/head/new_hat, mob/living/user)
	if(!istype(new_hat))
		to_chat(user, span_warning("\The [new_hat] isn't a hat."))
		return
	if(hat)
		to_chat(user, span_warning("\The [src] is already wearing \a [hat]."))
		return
	else
		if(!move_into(src, nameof(src.hat), new_hat, user))
			return
		to_chat(user, span_notice("You place \a [new_hat] on \the [src].  How adorable!"))
		update_icon()
		return

/mob/living/simple_mob/slime/proc/remove_hat(mob/living/user)
	if(!hat)
		to_chat(user, span_warning("\The [src] doesn't have a hat to remove."))
	else
		var/obj/item/clothing/head/old_hat = own_take(src, nameof(hat))
		old_hat.forceMove(get_turf(src))
		user.put_in_hands(old_hat)
		to_chat(user, span_warning("You take away \the [src]'s [old_hat.name].  How mean."))
		update_icon()

/mob/living/simple_mob/slime/proc/drop_hat()
	if(!hat)
		return
	var/obj/item/clothing/head/old_hat = own_take(src, nameof(hat))
	old_hat.forceMove(get_turf(src))
	update_icon()

/mob/living/simple_mob/slime/speech_bubble_appearance()
	return "slime"

/mob/living/simple_mob/slime/proc/squish()
	play_sfx(src, SFX_EFFECTS_SLIME_SQUISH, vary = FALSE)
	act_message(src, null, null, MSG_OTHERS(span_infoplain(span_bold("%U%") + " squishes!")))

/datum/decl/mob_organ_names/slime
TYPE_TABLE(/datum/decl/mob_organ_names/slime, mob_organ_hit_zones, list("cytoplasmic membrane"))

// === merged from slime_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/mob/living/simple_mob/slime
	base_attack_cooldown = 2 SECONDS
	var/static/list/allowed_attack_types = list(
							/obj/item/melee/baton/slime,
							/obj/item/slimepotion)
