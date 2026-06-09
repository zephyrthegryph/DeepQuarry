/obj/item/implant/reagent_generator/egg
	name = "regular egg laying implant"
	desc = "This is an implant that allows the user to lay eggs."
	generated_reagents = list("egg" = 2)
	usable_volume = 1500
	transfer_amount = 300
	var/verb_descriptor = list("squeezes", "pushes", "hugs")
	var/self_verb_descriptor = list("squeeze", "push", "hug")
	var/short_emote_descriptor = list("lays", "forces out", "pushes out")
	self_emote_descriptor = list("lay", "force out", "push out")
	random_emote = list("lets out an embarrassed moan", "yelps in embarrassment", "quietly groans in a mixture of discomfort and pleasure")
	assigned_proc = /mob/living/carbon/human/proc/use_reagent_implant_egg
	var/eggtype = /obj/item/reagent_containers/food/snacks/egg
	var/cascade

/obj/item/implant/reagent_generator/egg/post_implant(mob/living/carbon/source)
	START_PROCESSING(SSobj, src)
	to_chat(source, span_notice("You implant [source] with \the [src]."))
	add_verb(source,assigned_proc) // TGPanel
	add_verb(source,/mob/living/carbon/human/proc/toggle_cascade) // TGPanel
	return 1

/mob/living/carbon/human/proc/use_reagent_implant_egg()
	set name = "Force Someone Adjacent To Lay An Egg, If Applicable!"
	set desc = "Force someone adjacent to lay an egg by squeezing into their lower body! Whilst their reaction may vary, this is certainly going to overwhelm them for a moment!"
	set category = "Object"
	set src in view(1)
	//do_reagent_implant(usr)
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
	visible_message(span_danger("[usr] starts squeezing [src]'s lower body firmly..."))
	if (rimplant && do_after(usr,120,src))
		if(src.Adjacent(usr))
			var/egg = rimplant.eggtype
			new egg(get_turf(src))
			src.SetStunned(3)
			playsound(src,'sound/vore/insert.ogg',50,1)
			var/index = rand(1,3)

			if (usr != src)
				var/emote = rimplant.emote_descriptor[index]
				var/verb_desc = rimplant.verb_descriptor[index]
				var/self_verb_desc = rimplant.self_verb_descriptor[index]
				visible_message(span_notice("[usr] [verb_desc] [emote]"),
								span_notice("You [self_verb_desc] [emote]"))
			else
				visible_message(span_notice("[src] [pick(rimplant.short_emote_descriptor)] an egg."),
									span_notice("You [pick(rimplant.self_emote_descriptor)] an egg."))

			if(prob(15))
				visible_message(span_notice("[src] [pick(rimplant.random_emote)]."))
			rimplant.reagents.remove_any(rimplant.transfer_amount)

			if(rimplant.cascade)
				to_chat(src, span_notice("You feel your legs quake as your muscles fail to stand strong!"))
				while(rimplant.reagents.total_volume >= rimplant.transfer_amount)
					if(do_after(src,30,src))
						src.SetStunned(3)
						playsound(src,'sound/vore/insert.ogg',50,1)
						src.apply_effect(10,STUTTER,0)
						new egg(get_turf(src))
						rimplant.reagents.remove_any(rimplant.transfer_amount)
						if(prob(25))
							visible_message(span_notice("[src] [pick(rimplant.random_emote)]."))
					else
						return

/mob/living/carbon/human/proc/toggle_cascade()

	set name = "Toggle cascading"
	set desc = "Toggle whether or not being forced to lay an egg will cause you to lay all others as well, in rapid succession"
	set category = "Object"

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


// === merged from implantreagent_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/implant/reagent_generator
	name = "reagent generator implant"
	desc = "This is an implant that has attached storage and generates a reagent."
	implant_color = "r"
	var/list/generated_reagents = list(REAGENT_ID_WATER = 2) //Any number of reagents, the associated value is how many units are generated per process()
	var/reagent_name = REAGENT_ID_WATER //What is shown when reagents are removed, doesn't need to be an actual reagent
	var/gen_cost = 0.5 //amount of nutrient taken from the host per process tick
	var/transfer_amount = 30 //amount transferred when using verb
	var/usable_volume = 120

	var/list/empty_message = list("You feel as though your internal reagent implant is almost empty.")
	var/list/full_message = "You feel as though your internal reagent implant is full."
	var/list/emote_descriptor = list("tranfers something") //In format of [x] [emote_descriptor] into [container]
	var/list/self_emote_descriptor = list("transfer") //In format of You [self_emote_descriptor] some [generated_reagent] into [container]
	var/list/random_emote = list() //An emote the person with the implant may be forced to perform after a prob check, such as [X] meows.
	var/assigned_proc = /mob/living/carbon/human/proc/use_reagent_implant
	var/verb_name = "Transfer From Reagent Implant"
	var/verb_desc = "Remove reagents from an internal reagent into a container"

/obj/item/implant/reagent_generator/Initialize(mapload)
	. = ..()
	create_reagents(usable_volume)

/obj/item/implanter/reagent_generator
	var/implant_type = /obj/item/implant/reagent_generator

/obj/item/implanter/reagent_generator/Initialize(mapload)
	. = ..()
	imp = new implant_type(src)
	update()

/obj/item/implant/reagent_generator/post_implant(mob/living/carbon/source)
	START_PROCESSING(SSobj, src)
	to_chat(source, span_notice("You implant [source] with \the [src]."))
	assigned_proc = new assigned_proc(source, verb_name, verb_desc)
	return 1

/obj/item/implant/reagent_generator/process()
	var/before_gen
	if(isliving(imp_in) && generated_reagents)
		before_gen = reagents.total_volume
		var/mob/living/L = imp_in
		if(reagents.total_volume < reagents.maximum_volume)
			if(L.nutrition >= gen_cost)
				do_generation(L)
		else
			return
	else
		remove_verb(imp_in, assigned_proc)
		return

	if(reagents)
		if(reagents.total_volume == reagents.maximum_volume * 0.05)
			to_chat(imp_in, span_notice("[pick(empty_message)]"))
		else if(reagents.total_volume == reagents.maximum_volume && before_gen < reagents.maximum_volume)
			to_chat(imp_in, span_warning("[pick(full_message)]"))

/obj/item/implant/reagent_generator/proc/do_generation(mob/living/L)
	L.adjust_nutrition(-gen_cost)
	for(var/reagent in generated_reagents)
		reagents.add_reagent(reagent, generated_reagents[reagent])

/mob/living/carbon/human/proc/use_reagent_implant()
	set name = "Transfer From Reagent Implant"
	set desc = "Remove reagents from am internal reagent into a container."
	set category = "Object"
	set src in view(1)

	do_reagent_implant(usr)

/mob/living/carbon/human/proc/do_reagent_implant(mob/living/carbon/human/user = usr)
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
				user.visible_message(span_notice("[user] [pick(rimplant.emote_descriptor)] into \the [container_name]."),
									span_notice("You [pick(rimplant.self_emote_descriptor)] some [rimplant.reagent_name] into \the [container_name]."))
				if(prob(5))
					src.visible_message(span_notice("[src] [pick(rimplant.random_emote)].")) // M-mlem.
			if(rimplant.reagents.total_volume == rimplant.reagents.maximum_volume * 0.05)
				to_chat(src, span_notice("[pick(rimplant.empty_message)]"))
