/obj/item/implant/reagent_generator/egg
	name = "regular egg laying implant"
	desc = "This is an implant that allows the user to lay eggs."
	generated_reagents = list("egg" = 2)
	usable_volume = 1500
	transfer_amount = 300
	var/verb_descriptor = list("squeezes", "pushes", "hugs")
	var/self_verb_descriptor = list("squeeze", "push", "hug")
	var/short_emote_descriptor = list("lays", "forces out", "pushes out")
	random_emote = list("lets out an embarrassed moan", "yelps in embarrassment", "quietly groans in a mixture of discomfort and pleasure")
	assigned_proc = /mob/living/carbon/human/proc/use_reagent_implant_egg
	var/eggtype = /obj/item/reagent_containers/food/snacks/egg
	var/cascade

TYPE_TABLE(/obj/item/implant/reagent_generator/egg, reagent_implant_self_emotes, list("lay", "force out", "push out"))

/obj/item/implant/reagent_generator/egg/post_implant(mob/living/carbon/source)
	set_generating(TRUE)
	to_chat(source, span_notice("You implant [source] with \the [src]."))
	grant(source, implant_verb(), src) // TGPanel
	grant(source, granted_verb(/mob/living/carbon/human/proc/toggle_cascade), src) // TGPanel
	return 1

/mob/living/carbon/human/proc/use_reagent_implant_egg()
	set name = "Force Someone Adjacent To Lay An Egg, If Applicable!"
	set desc = "Force someone adjacent to lay an egg by squeezing into their lower body! Whilst their reaction may vary, this is certainly going to overwhelm them for a moment!"
	set category = VERB_CAT_OBJECT
	set src in view(1)
	if(!isliving(usr) || !usr.checkClickCooldown())
		return

	if(usr.incapacitated() || usr.stat > CONSCIOUS)
		return

	var/obj/item/implant/reagent_generator/egg/rimplant
	for(var/obj/item/organ/external/E in organs)
		for(var/obj/item/implant/I in E.implants)
			if(istype(I, /obj/item/implant/reagent_generator))
				rimplant = I
				break

	if(!rimplant)
		return
	rimplant.empty_message = list("Your lower belly feels smooth and empty, clearly there are no eggs left to be had!", "The reduced pressure in your lower belly tells you there are no eggs left, for now...")
	rimplant.full_message = list("Your lower belly is a bit bloated, possessing a mildly bumpy texture if pressed against...", "Your lower abdomen feels really heavy, making it a bit hard to walk.")
	rimplant.emote_descriptor = list("an egg right out of [src]'s lower belly!", "into [src]'s belly firmly, forcing them to lay an egg!", "[src] really tight, who promptly lays an egg!")

	if(rimplant.reagents.total_volume >= rimplant.usable_volume*0.75)
		if(usr != src)
			to_chat(usr, span_notice("[src] is very full on eggs, squeezing them now may result in a cascade!"))
		to_chat(src, span_notice("[pick(rimplant.full_message)]"))

	if(rimplant.reagents.total_volume <= rimplant.transfer_amount)
		if(usr != src)
			to_chat(usr, span_notice("It seems that [src] is out of eggs!"))
		to_chat(src, span_notice("[pick(rimplant.empty_message)]"))
		return
	act_message(usr, src, others = span_danger("%U% starts squeezing %T%'s lower body firmly..."))
	om_task_timed(usr, 120, target = src, receiver = src, on_done = PROC_REF(use_reagent_implant_egg_done), done_args = list(usr, rimplant))

/mob/living/carbon/human/proc/use_reagent_implant_egg_done(mob/usr_mob, obj/item/implant/reagent_generator/egg/rimplant)
	if(src.Adjacent(usr_mob))
		var/egg = rimplant.eggtype
		new egg(get_turf(src))
		src.status_set(STAT_STUNNED, 3)
		play_sfx(src, SFX_VORE_INSERT)
		var/index = rand(1,3)

		if (usr_mob != src)
			var/emote = rimplant.emote_descriptor[index]
			var/verb_desc = rimplant.verb_descriptor[index]
			var/self_verb_desc = rimplant.self_verb_descriptor[index]
			act_message(src, usr_mob, MSG_SELF(span_notice("You [self_verb_desc] [emote]")), \
				MSG_OTHERS(span_notice("%T% [verb_desc] [emote]")))
		else
			act_message(src, null, MSG_SELF(span_notice("You [pick(TYPE_TABLE_GET(rimplant, reagent_implant_self_emotes))] an egg.")), \
				MSG_OTHERS(span_notice("%U% [pick(rimplant.short_emote_descriptor)] an egg.")))

		if(prob(15))
			act_message(src, null, others = span_notice("%U% [pick(rimplant.random_emote)]."))
		rimplant.reagents.remove_any(rimplant.transfer_amount)

		if(rimplant.cascade)
			to_chat(src, span_notice("You feel your legs quake as your muscles fail to stand strong!"))
			egg_cascade_next(rimplant, egg)

/mob/living/carbon/human/proc/egg_cascade_next(obj/item/implant/reagent_generator/egg/rimplant, egg)
	if(rimplant.reagents.total_volume >= rimplant.transfer_amount)
		om_task_timed(src, 30, target = src, receiver = src, on_done = PROC_REF(use_reagent_implant_egg_timed_done), done_args = list(rimplant, egg))

/mob/living/carbon/human/proc/use_reagent_implant_egg_timed_done(obj/item/implant/reagent_generator/egg/rimplant, egg)
	src.status_set(STAT_STUNNED, 3)
	play_sfx(src, SFX_VORE_INSERT)
	src.apply_effect(10,STUTTER,0)
	new egg(get_turf(src))
	rimplant.reagents.remove_any(rimplant.transfer_amount)
	if(prob(25))
		act_message(src, null, others = span_notice("%U% [pick(rimplant.random_emote)]."))
	egg_cascade_next(rimplant, egg)

/mob/living/carbon/human/proc/toggle_cascade()

	set name = "Toggle cascading"
	set desc = "Toggle whether or not being forced to lay an egg will cause you to lay all others as well, in rapid succession"
	set category = VERB_CAT_OBJECT

	var/obj/item/implant/reagent_generator/egg/rimplant
	for(var/obj/item/organ/external/E in organs)
		for(var/obj/item/implant/I in E.implants)
			if(istype(I, /obj/item/implant/reagent_generator))
				rimplant = I
				break

	if(rimplant.cascade)
		rimplant.cascade = 0
		to_chat(src, span_notice("You toggle cascading off"))
	else
		rimplant.cascade = 1
		to_chat(src, span_notice("You toggle cascading on"))


/obj/item/implant/reagent_generator/egg/slow
	name = "slow egg laying implant"
	usable_volume = 3000
	transfer_amount = 600

/obj/item/implant/reagent_generator/egg/veryslow
	name = "very slow egg laying implant"
	usable_volume = 6000
	transfer_amount = 1200

/obj/item/implant/reagent_generator/egg/hicap
	name = "high capacity egg laying implant" // Note that the capacity does not affect the regeneration rate, rather, the transfer amount does
	usable_volume = 3000 // Effectively, the transfer_amount is the cost/time of making an egg. Usable volume is simply the max number of eggs.
	transfer_amount = 300

/obj/item/implant/reagent_generator/egg/doublehicap
	name = "extreme capacity egg laying implant"
	usable_volume = 6000
	transfer_amount = 300

/obj/item/implant/reagent_generator/egg/slowlowcap
	name = "slow, low capacity egg laying implant"
	usable_volume = 3000
	transfer_amount = 3000

/obj/item/implant/reagent_generator/egg/veryslowlowcap
	name = "very slow, low capacity egg laying implant"
	usable_volume = 6000
	transfer_amount = 6000


/obj/item/implant/reagent_generator
	name = "reagent generator implant"
	desc = "This is an implant that has attached storage and generates a reagent."
	implant_color = "r"
	// ALLOW(instance_list): d: replaced per instance at runtime (1 assignments)
	var/list/generated_reagents = list(REAGENT_ID_WATER = 2) //Any number of reagents, the associated value is how many units are generated per process()
	var/reagent_name = REAGENT_ID_WATER //What is shown when reagents are removed, doesn't need to be an actual reagent
	var/gen_cost = 0.5 //amount of nutrient taken from the host per process tick
	var/transfer_amount = 30 //amount transferred when using verb
	var/usable_volume = 120

	var/list/empty_message = list("You feel as though your internal reagent implant is almost empty.") // ALLOW(instance_list): d: replaced per instance at runtime (1 assignments)
	var/list/full_message = "You feel as though your internal reagent implant is full."
	// ALLOW(instance_list): d: replaced per instance at runtime (2 assignments)
	var/list/emote_descriptor = list("tranfers something") //In format of [x] [emote_descriptor] into [container]
	var/list/random_emote //An emote the person with the implant may be forced to perform after a prob check, such as [X] meows.
	var/assigned_proc = /mob/living/carbon/human/proc/use_reagent_implant
	var/verb_name = "Transfer From Reagent Implant"
	var/verb_desc = "Remove reagents from an internal reagent into a container"

// In format of You [self_emote_descriptor] some [generated_reagent] into [container]
TYPE_TABLE_DECLARE(/obj/item/implant/reagent_generator, reagent_implant_self_emotes, list("transfer"))

DECLARE_REAGENTS(/obj/item/implant/reagent_generator, "usable_volume", null)

/// Makes its reagents every 2 s from implantation on.
/obj/item/implant/reagent_generator/var/generating = FALSE
TRACKED(/obj/item/implant/reagent_generator, generating)
CAPABILITIES(/obj/item/implant/reagent_generator)
	every(2 SECONDS, then(PROC_REF(reagent_step)), when = nameof(generating))

/obj/item/implanter/reagent_generator
	var/implant_type = /obj/item/implant/reagent_generator

/obj/item/implanter/reagent_generator/ownership()
	. = ..()
	. += owns(nameof(imp), policy = OWN_CONTAINED, starts = nameof(implant_type))

/obj/item/implanter/reagent_generator
	icon_state = "implanter1_1" // loaded: what update() would show

/// The verb this implant gives its host: assigned_proc under the implant's verb_name/verb_desc.
/obj/item/implant/reagent_generator/proc/implant_verb()
	return granted_verb(assigned_proc, verb_name = verb_name, verb_desc = verb_desc)

/// Egg implants give the verb under its own name.
/obj/item/implant/reagent_generator/egg/implant_verb()
	return granted_verb(assigned_proc)

/obj/item/implant/reagent_generator/post_implant(mob/living/carbon/source)
	set_generating(TRUE)
	to_chat(source, span_notice("You implant [source] with \the [src]."))
	grant(source, implant_verb(), src)
	return 1

/obj/item/implant/reagent_generator/proc/reagent_step(datum/act/timer/A)
	var/before_gen
	if(isliving(imp_in()) && generated_reagents)
		before_gen = reagents.total_volume
		var/mob/living/L = imp_in()
		if(reagents.total_volume < reagents.maximum_volume)
			if(L.nutrition >= gen_cost)
				do_generation(L)
		else
			return
	else
		revoke(imp_in(), implant_verb(), src)
		return

	if(reagents)
		if(reagents.total_volume == reagents.maximum_volume * 0.05)
			to_chat(imp_in(), span_notice("[pick(empty_message)]"))
		else if(reagents.total_volume == reagents.maximum_volume && before_gen < reagents.maximum_volume)
			to_chat(imp_in(), span_warning("[pick(full_message)]"))

/obj/item/implant/reagent_generator/proc/do_generation(mob/living/L)
	L.adjust_nutrition(-gen_cost)
	for(var/reagent in generated_reagents)
		reagents.add_reagent(reagent, generated_reagents[reagent])

/mob/living/carbon/human/proc/use_reagent_implant()
	set name = "Transfer From Reagent Implant"
	set desc = "Remove reagents from am internal reagent into a container."
	set category = VERB_CAT_OBJECT
	set src in view(1)

	do_reagent_implant(usr)

/mob/living/carbon/human/proc/do_reagent_implant(mob/living/carbon/human/user)
	if(!isliving(user) || !user.checkClickCooldown())
		return

	if(user.incapacitated() || user.stat > CONSCIOUS)
		return

	var/obj/item/reagent_containers/container = user.get_active_hand()
	if(!container)
		to_chat(user,span_notice("You need an open container to do this!"))
		return


	var/obj/item/implant/reagent_generator/rimplant
	for(var/obj/item/organ/external/E in organs)
		for(var/obj/item/implant/I in E.implants)
			if(istype(I, /obj/item/implant/reagent_generator))
				rimplant = I
				break
	if(rimplant)
		if(container.reagents.total_volume < container.volume)
			var/container_name = container.name
			if(rimplant.reagents.trans_to(container, amount = rimplant.transfer_amount))
				act_message(user, null, MSG_SELF(span_notice("You [pick(TYPE_TABLE_GET(rimplant, reagent_implant_self_emotes))] some [rimplant.reagent_name] into \the [container_name].")), \
					MSG_OTHERS(span_notice("%U% [pick(rimplant.emote_descriptor)] into \the [container_name].")))
				if(prob(5))
					act_message(src, null, others = span_notice("%U% [pick(rimplant.random_emote)].")) // M-mlem.
			if(rimplant.reagents.total_volume == rimplant.reagents.maximum_volume * 0.05)
				to_chat(src, span_notice("[pick(rimplant.empty_message)]"))
