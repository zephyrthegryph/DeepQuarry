GLOBAL_LIST_INIT(nymph_default_emotes, list(
	/datum/decl/emote/visible,
	/datum/decl/emote/visible/scratch,
	/datum/decl/emote/visible/drool,
	/datum/decl/emote/visible/nod,
	/datum/decl/emote/visible/sway,
	/datum/decl/emote/visible/sulk,
	/datum/decl/emote/visible/twitch,
	/datum/decl/emote/visible/dance,
	/datum/decl/emote/visible/roll,
	/datum/decl/emote/visible/shake,
	/datum/decl/emote/visible/jump,
	/datum/decl/emote/visible/shiver,
	/datum/decl/emote/visible/collapse,
	/datum/decl/emote/visible/spin,
	/datum/decl/emote/visible/sidestep,
	/datum/decl/emote/audible/hiss,
	/datum/decl/emote/audible,
	/datum/decl/emote/audible/scretch,
	/datum/decl/emote/audible/choke,
	/datum/decl/emote/audible/gnarl,
	/datum/decl/emote/audible/bug_hiss,
	/datum/decl/emote/audible/bug_chitter,
	/datum/decl/emote/audible/chirp
))

/mob/living/carbon/alien/diona
	name = "diona nymph"
	voice_name = "diona nymph"
	adult_form = /mob/living/carbon/human
	can_namepick_as_adult = 1
	adult_name = "diona gestalt"
	speak_emote = list("chirrups")
	icon_state = "nymph"
	item_state = "nymph"
	language = LANGUAGE_ROOTLOCAL
	species_language = LANGUAGE_ROOTLOCAL
	only_species_language = 1
	death_message = "expires with a pitiful chirrup..."
	universal_understand = 0
	universal_speak = 0      // Dionaea do not need to speak to people other than other dionaea.

	can_pull_size = ITEMSIZE_SMALL
	can_pull_mobs = MOB_PULL_SMALLER

	holder_type = /obj/item/holder/diona
	var/obj/item/hat

/mob/living/carbon/alien/diona/get_available_emotes()
	return GLOB.nymph_default_emotes.Copy()

/mob/living/carbon/alien/diona/Initialize(mapload)
	. = ..()
	proto_set(src, nameof(species), GLOB.all_species[SPECIES_DIONA])
	add_language(LANGUAGE_ROOTGLOBAL)
	add_language(LANGUAGE_GALCOM)
	grant(src, granted_verb(/mob/living/carbon/alien/diona/proc/merge), src)

/mob/living/carbon/alien/diona/put_in_hands(obj/item/W) // No hands.
	W.forceMove(get_turf(src))
	return 1

/mob/living/carbon/alien/diona/proc/wear_hat(obj/item/new_hat)
	if(hat)
		return
	rel_set(src, nameof(hat), new_hat)
	new_hat.forceMove(src)
	update_icons()

/mob/living/carbon/alien/diona/proc/npc_behaviour(mob/living/carbon/alien/diona/D)
	if(D.stat != CONSCIOUS)
		return
	if(prob(33) && D.canmove && isturf(D.loc) && !D?.pulled_by_mob()) //won't move if being pulled
		step(D, pick(GLOB.cardinal))
	if(prob(1))
		D.emote(pick("scratch","jump","chirp","roll"))

CAPABILITIES(/mob/living/carbon/alien/diona)
	owns_one(nameof(hat), on_destroy = ON_DESTROY_SPILL)
	op("diona_interaction_hat", item(/obj/item/clothing/head), stance(I_HELP), label("Put on hat"), needs(req_is(nameof(hat), FALSE, because = /datum/msg/req_failed)), then(PROC_REF(diona_interaction_hat)))
