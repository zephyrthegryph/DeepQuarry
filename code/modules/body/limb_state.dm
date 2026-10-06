// Limb state the body derives (doc/rewrite/body_migration.md, slice 2): stance, grip, broken-bone jolts.
//
// The stance is derived from the legs and feet whenever a limb changes (the humanoid body's ORGANS invalidation, a splint,
// a dislocation), so movement reads a current number. What is genuinely periodic stays periodic, and only while there is
// limb trouble: a poor stance may give way, a malfunctioning prosthesis twitches and lets go, a broken arm can't hold on,
// and a broken bone jolts when you walk on it. One every(LIFE_CYCLE) per human gated by the tracked `limb_trouble`.

/// How likely a fractured limb holding organs jolts with pain per cycle while the human keeps moving.
#define LIMB_JOLT_CHANCE 10

/// TRUE while a limb gives trouble the body checks each cycle (a poor stance, a broken or malfunctioning limb): the body holds it.
STAT(/mob/living/carbon/human, limb_trouble, ANY)

/// The limb checks' entries, for the human's CAPABILITIES block: `active` is STAT_LIMB_TROUBLE.
/proc/limb_clock(active)
	return every(LIFE_CYCLE, then(TYPE_PROC_REF(/mob/living/carbon/human, limb_step)), when = active)

/// The humanoid body's organs changed: the limbs' derived state follows.
/datum/body/humanoid/invalidate(domains)
	..()
	var/mob/living/carbon/human/H = owner
	if(!istype(H))
		return
	if(domains & BODY_DIRTY_ORGANS)
		H.limb_refresh()
	// Deferred: asking the organs (factors, loads) here would consume the dirt this call just set.
	if(domains & (BODY_DIRTY_ORGANS | BODY_DIRTY_FACTORS | BODY_DIRTY_CHEMS))
		after(H, 0, TYPE_PROC_REF(/mob/living/carbon/human, organs_refresh), key = "organs_refresh")
	after(H, 0, TYPE_PROC_REF(/mob/living/carbon/human, pain_refresh), key = "pain_refresh")

/// Recomputes the stance and raises or drops the limb checks.
/mob/living/carbon/human/proc/limb_refresh()
	if(QDELETED(src))
		return
	stance_damage = stance_from_limbs()
	body_hold_flag(STAT_LIMB_TROUBLE, is_alive() && limb_trouble_now())

/mob/living/carbon/human/proc/limb_trouble_now()
	if(stance_damage > 0)
		return TRUE
	for(var/obj/item/organ/external/E as anything in organs)
		if(E.is_fractured() || E.is_dislocated() || E.is_malfunctioning())
			return TRUE
	return FALSE

/// Stance damage from the legs and feet, aids and gravity: 2 a missing or unusable part, 1 broken, 0.5 dislocated.
/mob/living/carbon/human/proc/stance_from_limbs()
	. = 0
	// Buckled to a bed or chair: sitting on something solid.
	if(istype(buckled_to(), /obj/structure/bed))
		return 0
	for(var/limb_tag in list(BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT))
		var/obj/item/organ/external/E = organs_by_name[limb_tag]
		if(!E || !E.is_usable())
			. += 2 // let it fail even if just foot and leg
		else if(E.is_broken())
			. += 1
		else if(E.is_dislocated())
			. += 0.5
	// Canes help you stand: one mitigates a broken leg and foot or a missing foot; two are needed for a lost leg.
	if(istype(get_equipped_item(SLOT_ID_HAND_L), /obj/item/cane))
		. -= 2
	if(istype(get_equipped_item(SLOT_ID_HAND_R), /obj/item/cane))
		. -= 2
	// Jetpacks in zero gravity hold you up.
	var/obj/item/tank/jetpack/thrust = get_jetpack()
	if(lastarea?.get_gravity() == FALSE && thrust?.stabilization_on)
		. -= 4

/mob/living/carbon/human/proc/limb_step(datum/act/timer/A)
	if(!is_alive())
		limb_refresh()
		return
	handle_stance()
	handle_grasp()
	broken_bone_jolt()
	limb_refresh()

/// A poor stance may give way; a malfunctioning leg counts as missing when it acts up.
/mob/living/carbon/human/proc/handle_stance()
	var/stance = stance_from_limbs()
	var/limb_pain = FALSE
	for(var/limb_tag in list(BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT))
		var/obj/item/organ/external/E = organs_by_name[limb_tag]
		if(E && E.is_usable() && E.is_malfunctioning() && !(lying || resting))
			// Malfunctioning only happens intermittently, so treat it as a missing limb when it acts up.
			stance += 2
			if(isturf(loc) && prob(10))
				act_message(src, null, others = "%U%'s [E.name] [pick("twitches", "shudders")] and sparks!")
				fx_sparks(src, 5, FALSE)
		if(E && (!E.is_usable() || E.is_broken() || E.is_dislocated()))
			limb_pain = E.organ_can_feel_pain()
	stance_damage = stance
	if(stance_damage >= 4 || (stance_damage >= 2 && prob(5)))
		if(!(lying || resting) && !isbelly(loc))
			if(limb_pain)
				emote("scream")
			automatic_custom_emote(VISIBLE_MESSAGE, "collapses!", check_stat = TRUE)
		if(!(lying || resting)) // stops permastun with SPINE sdisability
			status_at_least(STAT_WEAKENED, 5)

/// Moving around on a broken bone that holds organs (ribs, pelvis, skull) hurts enough to stagger you.
/mob/living/carbon/human/proc/broken_bone_jolt()
	if(lying || buckled_to() || stat || !can_feel_pain() || factor(BF_ANALGESIA) >= 50)
		return
	if(ELAPSED_SINCE(src, l_move_time, CLOCK_WORLD) >= BODY_MOVING_WINDOW)
		return
	for(var/obj/item/organ/external/E as anything in organs)
		if(!E.is_broken() || !length(E.held_organs()) || !prob(LIMB_JOLT_CHANCE))
			continue
		custom_pain("Pain jolts through your broken [E.encased ? E.encased : E.name], staggering you!", 50)
		emote("scream")
		drop_item(loc)
		status_at_least(STAT_STUNNED, 2)
		return
