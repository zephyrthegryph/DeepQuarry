/obj/item/deadringer
	name = "silver pocket watch"
	desc = "A fancy silver-plated digital pocket watch. Looks expensive."
	icon = 'icons/obj/deadringer.dmi'
	icon_state = "deadringer"
	w_class = ITEMSIZE_SMALL
	slot_flags = SLOT_ID | SLOT_BELT | SLOT_TIE
	var/bruteloss_prev = 999999
	var/fireloss_prev = 999999
	var/tmp/mob/living/carbon/human/corpse
	var/tmp/mob/living/carbon/human/watchowner

/// Armed: watching the holder for injury.
/obj/item/deadringer/var/activated = FALSE
TRACKED(/obj/item/deadringer, activated)
/// Cooldown steps left after triggering.
/obj/item/deadringer/var/timer = 0
TRACKED(/obj/item/deadringer, timer)
/// Armed or cooling down: periodic_step() runs (its every()).
CAPABILITIES(/obj/item/deadringer)
	every(2 SECONDS, then(PROC_REF(deadringer_step)), when = cond_any(nameof(activated), nameof(timer)))
	op("self", in_hand(), label("Use"), needs(req(PROC_REF(can_use_ringer_holds), because = PROC_REF(can_use_ringer_refusal))), then(PROC_REF(interaction_self)))

/obj/item/deadringer/proc/ringer_busy()
	return activated || timer

// an invisible wearer is revealed.
/obj/item/deadringer/on_destroy(force) //just in case some smartass tries to stay invisible by destroying the watch
	reveal()
	..()

/obj/item/deadringer/dropped(mob/user, equipping, slot)
	if(equipping)
		return ..() //Don't break cloak if we're being put in a pocket.
	..()
	if(timer > 20)
		reveal()
		rel_clear(src, nameof(watchowner))

/// Requirement: TRUE, or why the ringer can't be used.
/obj/item/deadringer/proc/can_use_ringer(mob/user, atom/target, obj/item/held)
	if(!ishuman(loc))
		return "you have no clue what to do with this thing"
	return TRUE

/// Old attack_self.
/// Requirement (was REQ_* can_use_ringer): the legacy check answers TRUE to pass.
/obj/item/deadringer/proc/can_use_ringer_holds(datum/act/op/A)
	var/answer = can_use_ringer(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_use_ringer_holds refuses: the legacy check's text, else the clause's own reason.
/obj/item/deadringer/proc/can_use_ringer_refusal(datum/act/op/A)
	var/answer = can_use_ringer(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/obj/item/deadringer/proc/interaction_self(datum/act/op/A)
	var/mob/living/H = src.loc
	if(!activated)
		if(timer == 0)
			to_chat(H, span_blue("You press a small button on [src]'s side. It starts to hum quietly."))
			bruteloss_prev = H.injury_load(INJURY_CATEGORY_PHYSICAL)
			fireloss_prev = H.injury_load(INJURY_CATEGORY_THERMAL)
			set_activated(TRUE)
			return TRUE
		else
			to_chat(H, span_blue("You press a small button on [src]'s side. It buzzes a little."))
			return TRUE
	if(activated)
		to_chat(H, span_blue("You press a small button on [src]'s side. It stops humming."))
		set_activated(FALSE)
		return TRUE
	return TRUE

/obj/item/deadringer/proc/deathprevent()
	for(var/mob/living/simple_mob/D in oviewers(7, src))
		if(!(D.ai_brain != null))
			continue
		D.ai_brain.lose_target()
	watchowner().alpha = 7 //10 is too visible, 5 is too in-visible... 7 is difficult to see but manageable.
	makeacorpse(watchowner())
	return

/obj/item/deadringer/proc/reveal()
	if(watchowner())
		watchowner().alpha = 255
		play_sfx(src, SFX_EFFECTS_UNCLOAK)
	return

/obj/item/deadringer/proc/makeacorpse(mob/living/carbon/human/H)
	if(HAS_SYNTHETIC_BIOLOGY(H))
		return
	rel_set(src, nameof(corpse), new /mob/living/carbon/human(H.loc))
	own_clear(corpse(), nameof(/mob::dna), OWN_DELETE)
	rel_set(corpse(), nameof(/mob::dna), H.dna.Clone())
	var/obj/item/clothing/temp = null
	if(H.get_equipped_item(SLOT_ID_UNIFORM))
		corpse().equip_to_slot_or_del(new /obj/item/clothing/under/chameleon/changeling(corpse()), SLOT_ID_UNIFORM)
		temp = corpse().get_equipped_item(SLOT_ID_UNIFORM)
		var/obj/item/clothing/c_type = H.get_equipped_item(SLOT_ID_UNIFORM)
		temp.disguise(c_type.type)
		temp.canremove = FALSE
	if(H.get_equipped_item(SLOT_ID_SUIT))
		corpse().equip_to_slot_or_del(new /obj/item/clothing/suit/chameleon/changeling(corpse()), SLOT_ID_SUIT)
		temp = corpse().get_equipped_item(SLOT_ID_SUIT)
		var/obj/item/clothing/c_type = H.get_equipped_item(SLOT_ID_SUIT)
		temp.disguise(c_type.type)
		temp.canremove = FALSE
	if(H.get_equipped_item(SLOT_ID_SHOES))
		corpse().equip_to_slot_or_del(new /obj/item/clothing/shoes/chameleon/changeling(corpse()), SLOT_ID_SHOES)
		temp = corpse().get_equipped_item(SLOT_ID_SHOES)
		var/obj/item/clothing/c_type = H.get_equipped_item(SLOT_ID_SHOES)
		temp.disguise(c_type.type)
		temp.canremove = FALSE
	if(H.get_equipped_item(SLOT_ID_GLOVES))
		corpse().equip_to_slot_or_del(new /obj/item/clothing/gloves/chameleon/changeling(corpse()), SLOT_ID_GLOVES)
		temp = corpse().get_equipped_item(SLOT_ID_GLOVES)
		var/obj/item/clothing/c_type = H.get_equipped_item(SLOT_ID_GLOVES)
		temp.disguise(c_type.type)
		temp.canremove = FALSE
	if(H.get_equipped_item(SLOT_ID_EAR_L))
		temp = H.get_equipped_item(SLOT_ID_EAR_L)
		corpse().equip_to_slot_or_del(new temp.type(corpse()), SLOT_ID_EAR_L)
		temp = corpse().get_equipped_item(SLOT_ID_EAR_L)
		temp.canremove = FALSE
	if(H.get_equipped_item(SLOT_ID_EYES))
		corpse().equip_to_slot_or_del(new /obj/item/clothing/glasses/chameleon/changeling(corpse()), SLOT_ID_EYES)
		temp = corpse().get_equipped_item(SLOT_ID_EYES)
		var/obj/item/clothing/c_type = H.get_equipped_item(SLOT_ID_EYES)
		temp.disguise(c_type.type)
		temp.canremove = FALSE
	if(H.get_equipped_item(SLOT_ID_MASK))
		corpse().equip_to_slot_or_del(new /obj/item/clothing/mask/chameleon/changeling(corpse()), SLOT_ID_MASK)
		temp = corpse().get_equipped_item(SLOT_ID_MASK)
		var/obj/item/clothing/c_type = H.get_equipped_item(SLOT_ID_MASK)
		temp.disguise(c_type.type)
		temp.canremove = FALSE
	if(H.get_equipped_item(SLOT_ID_HEAD))
		corpse().equip_to_slot_or_del(new /obj/item/clothing/head/chameleon/changeling(corpse()), SLOT_ID_HEAD)
		temp = corpse().get_equipped_item(SLOT_ID_HEAD)
		var/obj/item/clothing/c_type = H.get_equipped_item(SLOT_ID_HEAD)
		temp.disguise(c_type.type)
		temp.canremove = FALSE
	if(H.get_equipped_item(SLOT_ID_BELT))
		corpse().equip_to_slot_or_del(new /obj/item/storage/belt/chameleon/changeling(corpse()), SLOT_ID_BELT)
		temp = corpse().get_equipped_item(SLOT_ID_BELT)
		var/obj/item/clothing/c_type = H.get_equipped_item(SLOT_ID_BELT)
		temp.disguise(c_type.type)
		temp.canremove = FALSE
	if(H.get_equipped_item(SLOT_ID_BACK))
		corpse().equip_to_slot_or_del(new /obj/item/storage/backpack/chameleon/changeling(corpse()), SLOT_ID_BACK)
		temp = corpse().get_equipped_item(SLOT_ID_BACK)
		var/obj/item/clothing/c_type = H.get_equipped_item(SLOT_ID_BACK)
		temp.disguise(c_type.type)
		temp.canremove = FALSE
	corpse().identifying_gender = H.identifying_gender
	corpse().flavor_texts = H.flavor_texts?.Copy()
	corpse().real_name = H.real_name
	corpse().name = H.name
	corpse().emote("deathgasp") //Done after the name is set.
	corpse().death(1) //Kills the new mob
	corpse().set_species(corpse().dna.species)
	corpse().change_hair(H.h_style)
	corpse().change_facial_hair(H.f_style)
	corpse().change_hair_color(H.r_hair, H.g_hair, H.b_hair)
	corpse().change_facial_hair_color(H.r_facial, H.g_facial, H.b_facial)
	corpse().change_skin_color(H.r_skin, H.g_skin, H.b_skin)
	corpse().injure(INJURY_BURN, H.injury_load(INJURY_CATEGORY_THERMAL), null, null, 0, null, INJURE_SILENT)
	corpse().injure(INJURY_BLUNT, H.injury_load(INJURY_CATEGORY_PHYSICAL), null, null, 0, null, INJURE_SILENT)
	corpse().UpdateAppearance()
	corpse().regenerate_icons()
	var/list/corpse_organs = corpse().internal_organ_list()
	QDEL_LIST(corpse_organs)

// === merged from deadringer_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
/// Watches its holder while armed and counts its cooldown; idle, it sleeps.
/obj/item/deadringer/proc/deadringer_step(datum/act/timer/A)
	if(activated)
		if (ismob(src.loc))
			var/mob/living/carbon/human/H = src.loc
			rel_set(src, nameof(watchowner), H)
			if(isbelly(watchowner().loc)) //No spawning people in bellies.
				return
			if(H.injury_load(INJURY_CATEGORY_PHYSICAL) > bruteloss_prev || H.injury_load(INJURY_CATEGORY_THERMAL) > fireloss_prev)
				deathprevent()
				set_activated(FALSE)
				if(HAS_SYNTHETIC_BIOLOGY(watchowner()))
					to_chat(watchowner(), span_blue("You fade into nothingness! [src]'s screen blinks, being unable to copy your synthetic body!"))
				else
					to_chat(watchowner(), span_blue("You fade into nothingness, leaving behind a fake body!"))
				icon_state = "deadringer_cd"
				set_timer(5)
				return
	if(timer > 0)
		set_timer(timer - 1)
	if(timer == 2)
		reveal()
		if(corpse())
			replace_with(corpse(), /obj/effect/effect/smoke/chem)
	if(timer == 0)
		icon_state = "deadringer"
	return

/// the watchowner this refers to (a relation view: null once it is deleted).
/obj/item/deadringer/proc/watchowner() as /mob/living/carbon/human
	return watchowner

/// the corpse this refers to (a relation view: null once it is deleted).
/obj/item/deadringer/proc/corpse() as /mob/living/carbon/human
	return corpse
