// Kururaks, large pack-hunting felinids that reside in coastal regions. Less slowdown in water, speed on rocky turf.

/datum/category_item/catalogue/fauna/kururak
	name = "Sivian Fauna - Kururak"
	desc = "Classification: S Felidae fluctursora \
	<br><br>\
	An uncommon sight to many Sivian residents, these creatures are hypercarnivores, with\
	their diets almost exclusively consisting of other fauna. This is achieved in the frozen \
	environments of Sif via the means of fishing, even going to the lengths of evolving a \
	third, dense lung only inflated for long dives. \
	<br>\
	One of the most distinguishing features of these animals are their four tails, capped in \
	reflective 'mirrors'. These mirrors are used for tricking fish and other prey into ambushes,\
	or distract would-be rivals. \
	<br>\
	Kururak packs are incredibly dangerous if faced alone, and should only be approached if prepared \
	for a fight."
	value = CATALOGUER_REWARD_HARD

/mob/living/simple_mob/animal/sif/kururak
	name = "kururak"
	desc = "A large animal with sleek fur."
	tt_desc = "S Felidae fluctursora"
	catalogue_data = list(/datum/category_item/catalogue/fauna/kururak)

	faction = FACTION_KURUAK

	icon_state = "bigcat"
	icon_living = "bigcat"
	icon_dead = "bigcat_dead"
	icon_rest = "bigcat_sleep"
	icon = 'icons/mob/64x64.dmi'

	default_pixel_x = -16
	pixel_x = -16
	minbodytemp = 175
	endurance = 200

	universal_understand = 1

	movement_cooldown = -1

	melee_damage_lower = 15
	melee_damage_upper = 20
	attack_armor_pen = 40
	base_attack_cooldown = 2 SECONDS
	attacktext = list("gouged", "bit", "cut", "clawed", "whipped")

	organ_names = /datum/decl/mob_organ_names/kururak
	meat_amount = 5

	armor_spec = "melee=30;bullet=15;laser=5;bomb=10;bio=100;rad=100"

	say_list_type = /datum/say_list/kururak

	special_attack_min_range = 0
	special_attack_max_range = 4
	special_attack_cooldown = 1 MINUTE

	vore_active = TRUE
	vore_capacity = 1
	vore_pounce_chance = 15

	// Players have 2 seperate cooldowns for these, while the AI must choose one. Both respect special_attack_cooldown
	COOLDOWN_DECLARE(strike_cooldown)
	COOLDOWN_DECLARE(flash_cooldown)

	var/instinct	// The points used by Kururaks to decide Who Is The Boss
	var/obey_pack_rule = TRUE	// Decides if the Kururak will automatically assign itself to follow the one with the highest instinct.

/mob/living/simple_mob/animal/sif/kururak/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "stomach"
	B.desc = "Blue innards of a sleek creature surround you in an overwhelmingly tight pressure. Walls, coated in slick, reflective mucus reflect \
		light from the pool of teal stomach juices, flashing you from random angles. The texture of the surroundings is only mildly soft, it feels \
		firm, muscular body ensuring you stay in your place, drenched in fluids, pacified by constant churning motions. Effective and agile predator \
		made sure you were helpless during the hunt, now its gut ensures you are as disoriented in this pit of flashing lights and bubbling acid."
	B.mode_flags = DM_FLAG_THICKBELLY | DM_FLAG_NUMBING
	B.digest_brute = 3
	B.digest_burn = 2
	B.digestchance = 0
	B.absorbchance = 0
	B.escapechance = 25
	B.escape_stun = 5

/datum/say_list/kururak
	speak = list("Kurr?","|R|rrh..", "Ksss...")
	emote_see = list("scratches its ear","flutters its tails", "flicks an ear", "shakes out its hair")
	emote_hear = list("chirps", "clicks", "grumbles", "chitters")

/mob/living/simple_mob/animal/sif/kururak/leader	// Going to be the starting leader. Has some base buffs to make it more likely to stay the leader.
	endurance = 250
	instinct = 50

CAPABILITIES(/mob/living/simple_mob/animal/sif/kururak)
	rolls(nameof(instinct), PROC_REF(roll_instinct))
	op("rend_hatch", ai(), takes("mech"), wait(1 SECOND), then(PROC_REF(rending_strike_kururak_done)))

/// Rolled before init (rolls()): one in five is a natural leader.
/mob/living/simple_mob/animal/sif/kururak/proc/roll_instinct(datum/roller/R)
	return R.chance(20) ? R.number(6, 10) : R.number(0, 5)

/mob/living/simple_mob/animal/sif/kururak/IIsAlly(mob/living/L)
	. = ..()
	if(!.)
		if(issilicon(L))	// Metal things are usually reflective, or in general aggrivating.
			return FALSE
		if(ishuman(L))	// Might be metal, but they're humanoid shaped.
			var/mob/living/carbon/human/H = L
			if(H.get_active_hand())
				var/obj/item/I = H.get_active_hand()
				if(I.force <= 1.25 * melee_damage_upper)
					return TRUE
		else if(isanimal(L))
			var/mob/living/simple_mob/S = L
			if(S.melee_damage_upper > 1.5 * melee_damage_upper)
				return TRUE

/mob/living/simple_mob/animal/sif/kururak/life_special_due()
	return TRUE

/mob/living/simple_mob/animal/sif/kururak/life_special(datum/seq_frame/life/F)
	..()
	if(src.client)
		src.pack_gauge()

/mob/living/simple_mob/animal/sif/kururak/apply_melee_effects(atom/A)	// Only gains instinct.
	instinct += rand(1, 2)
	return ..()

/mob/living/simple_mob/animal/sif/kururak/should_special_attack(atom/A)
	return has_body_effect(/datum/body_effect/ace)

/mob/living/simple_mob/animal/sif/kururak/do_special_attack(atom/A, stance)
	. = TRUE
	switch(stance)
		if(I_DISARM) // Ranged mob flash, will also confuse borgs rather than stun.
			tail_flash(A)
		if(I_GRAB) // Armor-ignoring hit, causes agonizing wounds.
			ai_busy_begin()
			rending_strike(A)
			ai_busy_end()
	return ..()

/mob/living/simple_mob/animal/sif/kururak/verb/do_flash()
	set category = VERB_CAT_ABILITIES_KURURAK
	set name = "Tail Blind"
	set desc = "Disorient a creature within range."

	if(!COOLDOWN_FINISHED(src, flash_cooldown))
		to_chat(src, span_warning("You do not have the focus to do this so soon.."))
		return

	COOLDOWN_START(src, flash_cooldown, special_attack_cooldown)
	tail_flash()

/mob/living/simple_mob/animal/sif/kururak/proc/tail_flash(atom/A)
	if(stat)
		to_chat(src, span_warning("You cannot move your tails in this state.."))
		return

	if(!A && src.client)
		var/list/choices = list()
		for(var/mob/living/carbon/C in view(1,src))
			if(src.Adjacent(C))
				choices += C

		for(var/obj/mecha/M in view(1,src))
			if(src.Adjacent(M))
				choices += M

		if(!choices.len)
			choices["radial"] = get_turf(src)

		// A cancel (optional) flashes everyone around, as the tails flare either way.
		open_request(src, /datum/prompt/choice, PROC_REF(tail_flash_chosen), answerer = src, title = "Target Choice", question = "What do we wish to flash?", choices = choices, ask_flags = ASK_CONSCIOUS, timeout = 0)
		return
	tail_flash_now(A)

/mob/living/simple_mob/animal/sif/kururak/proc/tail_flash_chosen(datum/act/request/A)
	var/datum/request/R = A.request
	// An explicit close still flares the tails; a failed conscious recheck does not.
	if(!A.answer && (R.outcome != REQ_CANCELLED || !isnull(R.value)))
		return
	var/target = A.answer ? A.answer.value : null
	if(isdatum(target))
		var/datum/target_datum = target
		if(QDELETED(target_datum))
			return
	tail_flash_now(isatom(target) ? target : null)

/mob/living/simple_mob/animal/sif/kururak/proc/tail_flash_now(atom/A)
	act_message(src, null, null, MSG_OTHERS(span_alien("%U% flares its tails!")))
	if(isliving(A))
		var/mob/living/L = A
		if(iscarbon(L))
			var/mob/living/carbon/C = L
			if(C.stat != DEAD)
				var/safety = C.eyecheck()
				if(safety <= 0)
					var/flash_strength = 5
					if(ishuman(C))
						var/mob/living/carbon/human/H = C
						flash_strength *= H.species.flash_mod
						if(flash_strength > 0)
							to_chat(H, span_alien("You are disoriented by \the [src]!"))
							H.status_at_least(STAT_BLURRY, flash_strength + 5)
							H.flash_eyes()
							H.injure(INJURY_BURN, flash_strength * H.species.flash_burn/5, BP_HEAD, src)

		else if(issilicon(L))
			if(isrobot(L))
				var/flashfail = FALSE
				var/mob/living/silicon/robot/R = L
				if(R.has_active_type(/obj/item/borg/combat/shield))
					var/obj/item/borg/combat/shield/shield = locate_in_list(R, /obj/item/borg/combat/shield)
					if(shield)
						if(shield.active)
							shield.adjust_flash_count(R, 1)
							flashfail = TRUE
				if(!flashfail)
					to_chat(R, span_alien("Your optics are scrambled by \the [src]!"))
					R.status_at_least(STAT_CONFUSED, 10)
					R.flash_eyes()

		else
			L.status_at_least(STAT_CONFUSED, 10)
			L.flash_eyes()

	else
		for(var/mob/living/carbon/C in oviewers(special_attack_max_range, null))
			var/safety = C.eyecheck()
			if(!safety)
				if(!C.blinded)
					C.flash_eyes()
		for(var/mob/living/silicon/robot/R in oviewers(special_attack_max_range, null))
			if(R.has_active_type(/obj/item/borg/combat/shield))
				var/obj/item/borg/combat/shield/shield = locate_in_list(R, /obj/item/borg/combat/shield)
				if(shield)
					if(shield.active)
						continue
			R.flash_eyes()

/mob/living/simple_mob/animal/sif/kururak/verb/do_strike()
	set category = VERB_CAT_ABILITIES_KURURAK
	set name = "Rending Strike"
	set desc = "Strike viciously at an entity within range."

	if(!COOLDOWN_FINISHED(src, strike_cooldown))
		to_chat(src, span_warning("Your claws cannot take that much stress in so short a time.."))
		return

	COOLDOWN_START(src, strike_cooldown, special_attack_cooldown)
	rending_strike()

/mob/living/simple_mob/animal/sif/kururak/proc/rending_strike_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/atom/target = A.answer.value
	if(QDELETED(target))
		return
	rending_strike(target)

/mob/living/simple_mob/animal/sif/kururak/proc/rending_strike(atom/A)
	if(stat)
		to_chat(src, span_warning("You cannot strike in this state.."))
		return

	if(!A && src.client)
		var/list/choices = list()
		for(var/mob/living/carbon/C in view(1,src))
			if(src.Adjacent(C))
				choices += C

		for(var/obj/mecha/M in view(1,src))
			if(src.Adjacent(M))
				choices += M

		if(!choices.len)
			to_chat(src, span_warning("There are no viable targets within range..."))
			return

		open_request(src, /datum/prompt/choice, PROC_REF(rending_strike_chosen), answerer = src, title = "Target Choice", question = "What do we wish to strike?", choices = choices, ask_flags = ASK_CONSCIOUS, timeout = 0)
		return

	if(!A) return

	if(!(src.Adjacent(A))) return

	var/damage_to_apply = rand(melee_damage_lower, melee_damage_upper) + 10
	if(isliving(A))
		act_message(src, A, null, MSG_OTHERS(span_danger("%U% rakes its claws across %T%.")))
		var/mob/living/L = A
		if(ishuman(L))
			var/mob/living/carbon/human/H = L
			H.injure(INJURY_CUT, damage_to_apply, BP_TORSO, src)

		else
			L.injure(INJURY_CUT, damage_to_apply, source = src)

		L.apply_body_effect(/datum/body_effect/grievous_wounds, 60 SECONDS)

	else if(istype(A, /obj/mecha))
		act_message(src, A, null, MSG_OTHERS(span_danger("%U% rakes its claws against %T%.")))
		var/obj/mecha/M = A
		M.take_damage(damage_to_apply)
		if(prob(3))
			act_message(src, M, null, MSG_OTHERS(span_critical("%U% begins digging its claws into %T%'s hatch!")))
			perform_op(src, src, "rend_hatch", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("mech" = M))

	else
		generic_hit(A, src, damage_to_apply, "rakes its claws against")	// Well it's not a mob, and it's not a mech.

/mob/living/simple_mob/animal/sif/kururak/proc/rending_strike_kururak_done(datum/act/op/A)
	var/obj/mecha/M = A.arg("mech")
	if(QDELETED(M) || !Adjacent(M)) // the mech got away while the claws dug in
		return
	act_message(src, M, null, MSG_OTHERS(span_critical("%U% rips %T%'s access hatch open, dragging [M?.slot_item(MECHA_SLOT_PILOT)] out!")))
	M.go_out()

/mob/living/simple_mob/animal/sif/kururak/verb/rally_pack()	// Mostly for telling other players to follow you. AI Kururaks will auto-follow, if set to.
	set name = "Rally Pack"
	set desc = "Tries to command your fellow pack members to follow you."
	set category = VERB_CAT_ABILITIES_KURURAK

	if(has_body_effect(/datum/body_effect/ace))
		for(var/mob/living/simple_mob/animal/sif/kururak/K in hearers(7, src))
			if(K == src)
				continue
			if(!K.ai_brain)
				continue
			if(K.faction != src.faction)
				continue
			var/datum/ai_brain/AI = K.ai_brain
			to_chat(K, span_notice("The pack leader wishes for you to follow them."))
			AI.set_follow(src)

/mob/living/simple_mob/animal/sif/kururak/proc/detect_instinct()	// Will return the Kururak within 10 tiles that has the highest instinct.
	var/mob/living/simple_mob/animal/sif/kururak/A

	var/pack_count = 0

	for(var/mob/living/simple_mob/animal/sif/kururak/K in hearers(10, src))
		if(K == src)
			continue
		if(K.stat != DEAD)
			pack_count++
			if(K.instinct > src.instinct)
				A = K

	if(!A && pack_count)
		A = src

	return A

/mob/living/simple_mob/animal/sif/kururak/proc/pack_gauge()	// Check incase we have a client.
	var/mob/living/simple_mob/animal/sif/kururak/highest_instinct = detect_instinct()
	if(highest_instinct == src)
		apply_body_effect(/datum/body_effect/ace, 60 SECONDS)
	else
		remove_body_effect(/datum/body_effect/ace)

/mob/living/simple_mob/animal/sif/kururak/hibernate/Initialize(mapload)
	. = ..()
	lay_down()
	instinct = 0

/*
 * Kururak AI
 */

// Kururak Ace modifier, given to the one with the highest Instinct.

/datum/body_effect/ace
	name = "Ace"
	desc = "You are universally superior, in terms of physical prowess."
	on_created_text = "You feel superior."
	on_expired_text = "You feel your superiority lessen..."
	stacks = MODIFIER_STACK_EXTEND

	mob_overlay_state = "ace"

	factors = alist(BF_BLEEDING = 0.7, BF_EVASION = 20, BF_ATTACK_SPEED = 0.8, BF_MELEE_DAMAGE = 1.5, BF_INCOMING_ALL = 0.7, BF_DISABLE_DURATION = 0.8, BF_HEALING_RECEIVED = 1.5, BF_ENDURANCE_FLAT = 25, BF_ENDURANCE_MULT = 1.2)

/datum/decl/mob_organ_names/kururak
TYPE_TABLE(/datum/decl/mob_organ_names/kururak, mob_organ_hit_zones, list("head", "chest", "left foreleg", "right foreleg", "left hind leg", "right hind leg", "far left tail", "far right tail", "left middle tail", "right middle tail"))
