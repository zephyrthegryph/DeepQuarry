
/mob/living/simple_mob/vore/ddraig
	name = "ddraig"
	desc = "A massive, slender dragon like creature. It's body is covered in slick, vibrant pink scales. Atop its back sits large, thin white wings that are reminiscent of those scene on butterflies."
	tt_desc = "Draconis glamoris"
	icon = 'icons/mob/vore96x96.dmi'
	icon_dead = "ddraig-dead"
	icon_living = "ddraig"
	icon_state = "ddraig"
	icon_rest = "ddraig_rest"
	faction = FACTION_GLAMOUR
	catalogue_data = list(/datum/category_item/catalogue/fauna/ddraig)
	old_x = -32
	old_y = 0
	vis_height = 92
	melee_damage_lower = 20
	melee_damage_upper = 15
	friendly = list("nudges", "sniffs on", "rumbles softly at", "nuzzles")
	default_pixel_x = -32
	pixel_x = -32
	pixel_y = 0
	response_help = "bumps"
	response_disarm = "shoves"
	response_harm = "bites"
	movement_cooldown = 1
	harm_intent_damage = 10
	melee_damage_lower = 15
	melee_damage_upper = 25
	endurance = 1000
	attacktext = list("mauled")
	see_in_dark = 8
	minbodytemp = 0
	max_buckled_mobs = 1
	mount_offset_y = 32
	can_buckle = TRUE
	buckle_movable = TRUE
	buckle_lying = FALSE
	min_oxy = 0
	max_oxy = 0
	min_tox = 0
	max_tox = 0
	min_co2 = 0
	max_co2 = 0
	min_n2 = 0
	max_n2 = 0
	minbodytemp = 0
	maxbodytemp = 99999
	heat_resist = 1

	var/flames
	var/charge_warmup = 3 SECOND
	var/tf_warmup = 2 SECOND

	special_attack_min_range = 2
	special_attack_max_range = 6
	special_attack_cooldown = 15 SECONDS

	var/leap_warmup = 2 SECOND // How long the leap telegraphing is.
	var/leap_sound = SFX_WEAPONS_SPIDERLUNGE

	status_flags = null

/mob/living/simple_mob/vore/ddraig

	vore_bump_chance = 25
	vore_digest_chance = 50
	vore_escape_chance = 5
	vore_pounce_chance = 100
	vore_active = 1
	vore_icons = 3
	vore_icons = SA_ICON_LIVING | SA_ICON_REST
	vore_capacity = 3
	swallowTime = 50
	vore_ignores_undigestable = TRUE
	vore_default_mode = DM_DIGEST
	vore_pounce_maxhealth = 125
	vore_bump_emote = "tries to devour"
	can_be_drop_prey = FALSE

/mob/living/simple_mob/vore/ddraig/faster
	special_attack_cooldown = 10 SECONDS
	charge_warmup = 1.5 SECOND
	tf_warmup = 1 SECOND
	leap_warmup = 1 SECOND
	movement_cooldown = -3

CAPABILITIES(/mob/living/simple_mob/vore/ddraig)
	immune_to_incapacitation()
	verb_entry(/mob/living/simple_mob/proc/animal_mount, login = TRUE)
	verb_entry(/mob/living/proc/toggle_rider_reins, login = TRUE)
	verb_entry(/mob/living/proc/set_size, login = TRUE)
	verb_entry(/mob/living/proc/polymorph, login = TRUE)
	verb_entry(/mob/living/proc/glamour_invisibility, login = TRUE)

/mob/living/simple_mob/vore/ddraig/Login()
	. = ..()
	if(!riding_datum)
		rel_set(src, nameof(riding_datum), new /datum/riding/simple_mob(src))
	movement_cooldown = -1

/mob/living/simple_mob/vore/ddraig/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "stomach"
	B.desc = "Despite the jaws of the dragon not being particular visible, once they begin to part it reveals a rather vast maw. More than wide enough to engulf your head and upper body, the ddraig lifts you effortlessly from the ground, standing up to full height with only your legs dangling from the beast's mouth. Inside you are engulfed in the wet, slimy and hot slobber of the creature. A massive tongue beneath your body curls over you to taste and lather every inch on offer. Soon enough, the dragon tosses its head backwards, sending your body beyond the throat, wrapped in the rippled lining of the creatures gullet for a slow, dark descent into the abyss below. It is a long journey through that seemingly endless neck, but eventually you are deposited in the creature's stomach. Little sound from the outside makes it inside, all drowned out by the cacophony of bodily functions groaning, burbling and beating around you. Despite the size of the beast, the gut is not massive, the walls clench down tight around your helplessly trapped body. The stomach lining grinds roughly over your body, smearing you in a slurry of slimy fluids."
	B.vore_sound = "Tauric Swallow"
	B.release_sound = "Pred Escape"
	B.mode_flags = DM_FLAG_THICKBELLY
	B.fancy_vore = 1
	B.selective_preference = DM_DIGEST
	B.vore_verb = "devour"
	B.digest_brute = 3
	B.digest_burn = 2
	B.digest_oxy = 0
	B.selectchance = 50
	B.absorbchance = 0
	B.escapechance = 3
	B.escape_stun = 5
	B.contamination_color = "grey"
	B.contamination_flavor = "Wet"
	B.own_emote_lists()
	B.emote_lists[DM_DIGEST] = list(
		"The ddraig coos contentedly as the walls crush and squeeze over your body!",
		"As the ddraig moves about, it becomes more difficult to keep yourself upright, being forced to turn and slip of the slime slickened stomach lining.",
		"You can't make out any sound from the outside as the gut grumbled and reverberates over your body.",
		"As the thinning air begins to make you feel dizzy, menacing bworps and grumbles fill that dark, constantly shifting organ!",
		"The constant, rhythmic kneading and massaging starts to take its toll along with the muggy heat, making you feel weaker and weaker!",
		"The slender creature has no issue showing off the weak movements of you inside, even the churning of the gut itself tosses you about, all bumps so very visible on its flesh.")

/datum/category_item/catalogue/fauna/ddraig
	name = "Extra-Realspace Fauna - Ddraig"
	desc = "Classification: Draconis glamoris\
	<br><br>\
	A massive dragon-like creature found to reside in the glamour, also known as whitespace. The ddraig is considered a rarity, even amongst this alien world, and often revered by other inhabitants. \
	It is rarely considered outright aggressive, but has been known to attack if it feels threatened. It is a sapiant creature and considered to be particularly intelligent. \
	It is a carnivorous creature and quite capable of hunting. Aside from the deadly claws and teeth, it is also able to breathe fire like realspace dragons, turn itself invisible at will, and transform other creatures temporarily."
	value = CATALOGUER_REWARD_HARD

/mob/living/simple_mob/vore/ddraig/do_special_attack(atom/A, stance)
	. = TRUE
	if(ckey)
		return
	var/specialattack = rand(1,3)
	if(specialattack == 1)
		lunge(A)
	if(specialattack == 2)
		firebreathstart(A)
	if(specialattack == 3)
		tfbeam(A)

/mob/living/simple_mob/vore/ddraig/proc/lunge(atom/A)	//Mostly copied from hunter.dm
	if(!isliving(A))
		return FALSE
	var/mob/living/L = A
	if(!L.devourable || !L.allowmobvore || !L.can_be_drop_prey || !L.throw_vore || L.unacidable)
		return FALSE

	ai_busy_begin()
	act_message(src, null, null, MSG_OTHERS(span_warning("%U% rears back, ready to lunge!")))
	to_chat(L, span_danger("\The [src] focuses on you!"))
	// Telegraph, since getting stunned suddenly feels bad.
	do_windup_animation(A, leap_warmup)
	after(src, leap_warmup, PROC_REF(lunge_1), with = list(L), keeps_dead = TRUE) // For the telegraphing.


/mob/living/simple_mob/vore/ddraig/proc/lunge_1(mob/living/L)

	if(!L || L.z != z)	//Make sure you haven't disappeared to somewhere we can't go
		ai_busy_end()
		return FALSE

	// Do the actual leap.
	set_status_flags(status_flags | LEAPING) // Lets us pass over everything.
	visible_message(span_critical("\The [src] leaps at \the [L]!"))
	throw_at(get_step(L, get_turf(src)), special_attack_max_range+1, 1, src)
	playsound(src, leap_sound, 75, 1)

	after(src, 0.5 SECONDS, PROC_REF(lunge_2), with = list(L), keeps_dead = TRUE) // For the throw to complete. It won't hold up the AI ticker due to waitfor being false.

/mob/living/simple_mob/vore/ddraig/proc/lunge_2(mob/living/L)

	if(status_flags & LEAPING)
		set_status_flags(status_flags & ~LEAPING) // Revert special passage ability.

	ai_busy_end()
	if(L && Adjacent(L))	//We leapt at them but we didn't manage to hit them, let's see if we're next to them
		L.status_at_least(STAT_WEAKENED, 2)	//get knocked down, idiot

/mob/living/simple_mob/vore/ddraig/proc/firebreathstart(atom/A) //Borrowed from le big dragon
	set_glow_toggle(1)
	set_light(glow_range, glow_intensity, glow_color) //Setting it here so the light starts immediately
	flames = 1
	ai_busy_begin()
	act_message(src, null, null, MSG_OTHERS(span_warning("%U% opens its maw, emitting flames!")))
	do_windup_animation(A, charge_warmup)
	after(src, charge_warmup, PROC_REF(firebreathend), key = "firebreathtimer", with = list(A), keeps_dead = TRUE)
	playsound(src, "sound/magic/Fireball.ogg", 50, 1)

/mob/living/simple_mob/vore/ddraig/proc/firebreathend(atom/A)
	//make sure our target still exists and is on a turf
	if(QDELETED(A) || !isturf(get_turf(A)))
		ai_busy_end()
		return
	var/obj/item/projectile/P = new /obj/item/projectile/bullet/dragon(get_turf(src))
	act_message(src, A, null, MSG_OTHERS(span_danger("%U% spews fire at %T%!")))
	playsound(src, "sound/weapons/Flamer.ogg", 50, 1)
	P.launch_projectile(A, BP_TORSO, src)
	ai_busy_end()
	set_glow_toggle(0)
	flames = 0

/mob/living/simple_mob/vore/ddraig/proc/tfbeam(atom/A)
	if(!isturf(get_turf(A)))
		return
	ai_busy_begin()
	act_message(src, null, null, MSG_OTHERS(span_warning("%U% begins to shimmer with a rainbow hue!")))
	do_windup_animation(A, tf_warmup)
	after(src, tf_warmup, PROC_REF(tfbeam_1), with = list(A))


/mob/living/simple_mob/vore/ddraig/proc/tfbeam_1(atom/A)
	ai_busy_end()
	var/obj/item/projectile/P = new /obj/item/projectile/beam/mouselaser/ddraig(get_turf(src))
	act_message(src, A, null, MSG_OTHERS(span_danger("%U% breathes a beam at %T%!")))
	playsound(src, "sound/weapons/sparkle.ogg", 50, 1)
	P.launch_projectile(A, BP_TORSO, src)

/obj/item/projectile/beam/mouselaser/ddraig
	tf_admin_pref_override = TRUE //It will TF them regardless of their prefs because it is only very temporary
	icon_state = "rainbow"
	muzzle_type = /obj/effect/projectile/muzzle/rainbow
	tracer_type = /obj/effect/projectile/tracer/rainbow
	impact_type = /obj/effect/projectile/impact/rainbow

/obj/item/projectile/beam/mouselaser/ddraig/on_hit(atom/target)
	var/mob/living/M = target
	if(!istype(M))
		return
	if(target != firer)	//If you shot yourself, you probably want to be TFed so don't bother with prefs.
		if(!M.allow_spontaneous_tf && !tf_admin_pref_override)
			return
	if(M.tf_mob_holder)
		M.revert_mob_tf()
		return
	else
		if(M.stat == DEAD)	//We can let it undo the TF, because the person will be dead, but otherwise things get weird.
			return
		var/mob/living/new_mob = spawn_mob(M)

		M.tf_into(new_mob)

		after(new_mob, 30 SECONDS, TYPE_PROC_REF(/mob/living, revert_mob_tf))

/obj/item/projectile/beam/mouselaser/ddraig/spawn_mob(mob/living/target)
	var/list/tf_list = list(/mob/living/simple_mob/animal/passive/mouse,
		/mob/living/simple_mob/animal/passive/mouse/rat/strong,
		/mob/living/simple_mob/vore/alienanimals/dustjumper,
		/mob/living/simple_mob/vore/woof,
		/mob/living/simple_mob/animal/passive/dog/corgi,
		/mob/living/simple_mob/animal/passive/cat,
		/mob/living/simple_mob/animal/passive/chicken,
		/mob/living/simple_mob/animal/passive/cow,
		/mob/living/simple_mob/animal/passive/lizard,
		/mob/living/simple_mob/vore/rabbit,
		/mob/living/simple_mob/animal/passive/fox,
		/mob/living/simple_mob/vore/fennec,
		/mob/living/simple_mob/animal/passive/fennec,
		/mob/living/simple_mob/vore/fennix,
		/mob/living/simple_mob/vore/redpanda,
		/mob/living/simple_mob/animal/passive/opossum,
		/mob/living/simple_mob/vore/horse,
		/mob/living/simple_mob/animal/space/goose,
		/mob/living/simple_mob/vore/sheep)
	tf_type = pick(tf_list)
	if(!ispath(tf_type))
		return
	var/new_mob = new tf_type(get_turf(target))
	return new_mob

//legacy engage_target override body removed.
////////////////////////////Player controlled verbs///////////////////////////////

/mob/living/proc/polymorph()
	set name = "Polymorph"
	set desc = "Take the form of a non-humanoid creature."
	set category = VERB_CAT_ABILITIES

	var/static/list/beast_options = list("Rabbit" = /mob/living/simple_mob/vore/rabbit,
									"Red Panda" = /mob/living/simple_mob/vore/redpanda,
									"Fennec" = /mob/living/simple_mob/vore/fennec,
									"Giant Frog" = /mob/living/simple_mob/vore/aggressive/frog,
									"Giant Rat" = /mob/living/simple_mob/vore/aggressive/rat,
									"Wolf" = /mob/living/simple_mob/vore/wolf,
									"Dire Wolf" = /mob/living/simple_mob/vore/wolf/direwolf,
									"Fox" = /mob/living/simple_mob/animal/passive/fox/beastmode,
									"Panther" = /mob/living/simple_mob/vore/aggressive/panther,
									"Giant Snake" = /mob/living/simple_mob/vore/aggressive/giant_snake,
									"Otie" = /mob/living/simple_mob/vore/otie,
									"Squirrel" = /mob/living/simple_mob/vore/squirrel,
									"Raptor" = /mob/living/simple_mob/vore/raptor,
									"Giant Bat" = /mob/living/simple_mob/vore/bat,
									"Horse" = /mob/living/simple_mob/vore/horse,
									"Horse (Big)" = /mob/living/simple_mob/vore/horse/big,
									"Kelpie" = /mob/living/simple_mob/vore/horse/kelpie,
									"Bear" = /mob/living/simple_mob/animal/space/bear/brown/beastmode,
									"Seagull" = /mob/living/simple_mob/vore/seagull,
									"Sheep" = /mob/living/simple_mob/vore/sheep,
									"Azure Tit" = /mob/living/simple_mob/animal/passive/bird/azure_tit/beastmode,
									"Robin" = /mob/living/simple_mob/animal/passive/bird/european_robin/beastmode,
									"Cat" = /mob/living/simple_mob/animal/passive/cat/black/beastmode,
									"Tamaskan Dog" = /mob/living/simple_mob/animal/passive/dog/tamaskan,
									"Corgi" = /mob/living/simple_mob/animal/passive/dog/corgi,
									"Bull Terrier" = /mob/living/simple_mob/animal/passive/dog/bullterrier,
									"Duck" = /mob/living/simple_mob/animal/sif/duck,
									"Cow" = /mob/living/simple_mob/animal/passive/cow,
									"Chicken" = /mob/living/simple_mob/animal/passive/chicken,
									"Goat" = /mob/living/simple_mob/animal/goat,
									"Penguin" = /mob/living/simple_mob/animal/passive/penguin,
									"Goose" = /mob/living/simple_mob/animal/space/goose
									)

	open_request(src, /datum/prompt/choice, PROC_REF(polymorph_chosen), answerer = src, title = "Choose Beast Form", question = "Which form would you like to take?", choices = beast_options, ask_flags = ASK_CONSCIOUS, timeout = 0)

/mob/living/proc/polymorph_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/ask = A.answer
	var/chosen_beast = ask.value
	var/list/beast_options = ask.choices

	var/mob/living/M = src
	if(!istype(M))
		return

	if(M.stat)	//We can let it undo the TF, because the person will be dead, but otherwise things get weird.
		to_chat(src, span_warning("You can't do that in your condition."))
		return

	if(M.vitality() * M.get_endurance() <= 10)	//We can let it undo the TF, because the person will be dead, but otherwise things get weird.
		to_chat(src, span_warning("You are too injured to transform into a beast."))
		return

	act_message(src, null, null, MSG_OTHERS("<b>%U%</b> begins significantly shifting their form."))
	task_start(/datum/task/timed/living_polymorph_living, src, src, beast_options = beast_options, chosen_beast = chosen_beast)
	return TRUE

/datum/task/timed/living_polymorph_living
	duration = 10 SECONDS
	complete_proc = /mob/living/proc/polymorph_living_done
	cancel_proc = /mob/living/proc/polymorph_living_failed
	var/list/beast_options
	var/chosen_beast

/mob/living/proc/polymorph_living_done(datum/task/timed/living_polymorph_living/task)
	var/list/beast_options = task.beast_options
	var/chosen_beast = task.chosen_beast

	var/image/coolanimation = image('icons/obj/glamour.dmi', null, "animation")
	coolanimation.plane = PLANE_LIGHTING_ABOVE
	src.overlays += coolanimation
	after(src, 1 SECOND, PROC_REF(finish_polymorph), with = list(coolanimation, chosen_beast, beast_options[chosen_beast]))

/mob/living/proc/polymorph_living_failed(datum/task/timed/living_polymorph_living/task)
	act_message(src, null, null, MSG_OTHERS("<b>%U%</b> ceases shifting their form."))
	return 0

/mob/living/proc/spawn_polymorph_mob(chosen_beast)
	var/tf_type = chosen_beast
	if(!ispath(tf_type))
		return
	var/new_mob = new tf_type(get_turf(src))
	return new_mob

/mob/living/proc/glamour_invisibility()
	set name = "Invisibility"
	set desc = "Change your appearance to match your surroundings, becoming completely invisible to the naked eye."
	set category = VERB_CAT_ABILITIES

	if(stat)
		to_chat(src, span_warning("You can't go invisible when weakened like this."))
		return

	if(!dq_get_cloaked(src))
		cloak()
		to_chat(src, span_warning("Your skin shimmers and shifts around you, hiding you from the naked eye."))
	else
		uncloak()
		to_chat(src, span_warning("The shifting of your skin settles down and you become visible once again."))

/// The end of a polymorph, a second after the animation starts.
/mob/living/proc/finish_polymorph(image/coolanimation, chosen_beast, beast_type)
	overlays -= coolanimation
	var/mob/living/new_mob = spawn_polymorph_mob(beast_type)
	if(new_mob && isliving(new_mob))
		new_mob.faction = faction
		grant(new_mob, granted_verb(/mob/living/proc/revert_beast_form), new_mob)
		grant(new_mob, granted_verb(/mob/living/proc/set_size), new_mob)
		transfer_mob_identity(new_mob)
		new_mob.visible_message("<b>\The [src]</b> has transformed into \the [chosen_beast]!")
