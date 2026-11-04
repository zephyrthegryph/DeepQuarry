/mob/living/simple_mob/slime/xenobio/ruby/get_mechanics_info(list/additional_information)
	return ..(list("This slime is unnaturally stronger, allowing it to hit much harder, take less damage, and be stunned for less time. \
	Their glomp attacks also send the victim flying.") + additional_information)

/mob/living/simple_mob/slime/xenobio/ruby
	desc ="This slime has great physical strength."
	color = "#FF3333"
	slime_color = "ruby"
	shiny = TRUE
	glow_toggle = TRUE
	coretype = /obj/item/slime_extract/ruby
	player_msg = "Your <b>attacks knock back the target</b> a fair distance.<br>\
	You also hit harder, take less damage, and stuns affect you for less time."

	melee_attack_delay = 1 SECOND

	slime_mutation = list(
		/mob/living/simple_mob/slime/xenobio/dark_purple,
		/mob/living/simple_mob/slime/xenobio/dark_purple,
		/mob/living/simple_mob/slime/xenobio/ruby,
		/mob/living/simple_mob/slime/xenobio/ruby
	)

CAPABILITIES(/mob/living/simple_mob/slime/xenobio/ruby)
	body_effect(/datum/body_effect/slime_strength) // always swole

/mob/living/simple_mob/slime/xenobio/ruby/apply_melee_effects(atom/A, stance = I_HURT)
	..()

	if(isliving(A) && stance == I_HURT)
		var/mob/living/L = A
		if(L.mob_size <= MOB_MEDIUM)
			act_message(src, L, null, MSG_OTHERS(span_danger("%U% sends %T% flying with the impact!")))
			play_sfx(src, SFX_PUNCH)
			L.status_at_least(STAT_WEAKENED, 1)
			var/throwdir = get_dir(src, L)
			L.throw_at(get_edge_target_turf(L, throwdir), 3, 1, src)
		else
			to_chat(L, span_warning("\The [src] hits you with incredible force, but you remain in place."))
			act_message(src, L, null, MSG_OTHERS(span_danger("%U% hits %T% with incredible force, to no visible effect!")))
			play_sfx(src, SFX_PUNCH)
