/datum/genetics/side_effect
	var/name 				// name of the side effect, to use as a header in the manual
	var/duration = 0 		// delay between start() and finish()
	var/antidote_reagent 	// What type of reagent we require to stop the specific side effect from happening
	/// The human suffering it (who owns it, in genetic_side_effects): a relation view.
	var/mob/living/carbon/human/host

/proc/trigger_side_effect(mob/living/carbon/human/H)
	if(!ishuman(H)) return
	var/tp = pick(subtypesof(/datum/genetics/side_effect))
	var/datum/genetics/side_effect/S = new tp

	S.start(H)
	after(H, 2 SECONDS, TYPE_PROC_REF(/datum, status_at_least), with = list(STAT_WEAKENED, 4))
	after(S, S.duration, TYPE_PROC_REF(/datum/genetics/side_effect, complete))
	//above is doing: Call S.finish() in S.duration (dropped if H, and so S, is deleted first)

/datum/genetics/side_effect/proc/start(mob/living/carbon/human/H)
	if(H && ishuman(H))
		rel_add(H, nameof(H.genetic_side_effects), src)
		rel_set(src, nameof(host), H)
	// start the side effect, this should give some cue as to what's happening,
	// such as gasping. These cues need to be unique among side-effects.

/// The timer's end: runs finish(), then the host disposes of the side effect.
/datum/genetics/side_effect/proc/complete()
	var/mob/living/carbon/human/H = host
	finish()
	if(H && !QDELETED(src))
		own_remove(H, nameof(H.genetic_side_effects), src)

/datum/genetics/side_effect/proc/finish()
	var/mob/living/carbon/human/H = host
	if(!H || !ishuman(H)) return FALSE
	if(antidote_reagent && (H.reagents.has_reagent(antidote_reagent)|| H.ingested.has_reagent(antidote_reagent) || H.touching.has_reagent(antidote_reagent)))
		return TRUE
	return FALSE
	// Finish the side-effect. This should first check whether the cure has been
	// applied, and if not, cause bad things to happen.

/datum/genetics/side_effect/genetic_burn
	name = "Genetic Burn"
	duration = 30 SECONDS
	antidote_reagent = REAGENT_ID_DEXALIN

/datum/genetics/side_effect/genetic_burn/start(mob/living/carbon/human/H)
	..()
	H.automatic_custom_emote(VISIBLE_MESSAGE, "starts turning very red..", check_stat = TRUE)

/datum/genetics/side_effect/genetic_burn/finish()
	if(..()) return
	var/mob/living/carbon/human/H = host
	if(!ishuman(H))
		return
	for(var/organ_name in BP_ALL)
		var/obj/item/organ/external/E = H.get_organ(organ_name)
		if(E)
			H.injure(INJURY_BURN, 5, E)

/datum/genetics/side_effect/bone_snap
	name = "Genetic Bone Snap"
	duration = 60 SECONDS
	antidote_reagent = REAGENT_ID_BICARIDINE

/datum/genetics/side_effect/bone_snap/start(mob/living/carbon/human/H)
	..()
	H.automatic_custom_emote(VISIBLE_MESSAGE, "'s limbs start shivering uncontrollably.", check_stat = TRUE)

/datum/genetics/side_effect/bone_snap/finish()
	if(..()) return
	var/mob/living/carbon/human/H = host
	var/organ_name = pick(BP_ALL)
	var/obj/item/organ/external/E = H.get_organ(organ_name)
	if(!E)
		return
	H.injure(INJURY_BLUNT, 20, E)
	E.fracture()

/datum/genetics/side_effect/confuse
	name = "Genetic Confusion"
	duration = 30 SECONDS
	antidote_reagent = REAGENT_ID_ANTITOXIN

/datum/genetics/side_effect/confuse/start(mob/living/carbon/human/H)
	..()
	H.automatic_custom_emote(VISIBLE_MESSAGE, "has drool running down from [H.p_their()] mouth.", check_stat = TRUE)

/datum/genetics/side_effect/confuse/finish()
	if(..()) return
	var/mob/living/carbon/human/H = host
	H.status_at_least(STAT_CONFUSED, 100)
