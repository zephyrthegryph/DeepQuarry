/*
CONTAINS:
RSF

*/

GLOBAL_LIST_INIT(robot_glass_options, list(
		"metamorphic glass" = /obj/item/reagent_containers/food/drinks/metaglass,
		"metamorphic pint glass" = /obj/item/reagent_containers/food/drinks/metaglass/metapint,
		"half-pint glass" = /obj/item/reagent_containers/food/drinks/glass2/square,
		"rocks glass" = /obj/item/reagent_containers/food/drinks/glass2/rocks,
		"milkshake glass" = /obj/item/reagent_containers/food/drinks/glass2/shake,
		"cocktail glass" = /obj/item/reagent_containers/food/drinks/glass2/cocktail,
		"shot glass" = /obj/item/reagent_containers/food/drinks/glass2/shot,
		"pint glass" = /obj/item/reagent_containers/food/drinks/glass2/pint,
		"mug" = /obj/item/reagent_containers/food/drinks/glass2/mug,
		"wine glass" = /obj/item/reagent_containers/food/drinks/glass2/wine,
		"condiment bottle" = /obj/item/reagent_containers/food/condiment
		))

/obj/item/rsf
	name = "\improper Rapid-Service-Fabricator"
	desc = "A device used to rapidly deploy service items."
	icon = 'icons/obj/tools_vr.dmi'
	icon_state = "rsf"
	opacity = 0
	density = FALSE
	anchored = FALSE
	MATERIAL_BULK(DEFAULT_WALL_MATERIAL, 25000)
	var/stored_matter = 30
	var/mode = "container"
	var/glasstype_name = "metamorphic glass"

	w_class = ITEMSIZE_NORMAL

/obj/item/rsf/examine(mob/user)
	. = ..()
	if(get_dist(user, src) == 0)
		. += span_notice("It currently holds [stored_matter]/30 fabrication-units.")

/// Old attackby.
/obj/item/rsf/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if (istype(W, /obj/item/rcd_ammo))

		if ((stored_matter + 10) > 30)
			balloon_alert(user, "the fabricator can't hold any more matter.")
			return INTERACTION_HANDLED_PASS

		if(!consume(W, user))
			return INTERACTION_HANDLED_PASS

		stored_matter += 10
		play_sfx(src, SFX_MACHINES_CLICK, 0.2)
		balloon_alert(user,"the fabricator now holds [stored_matter]/30 fabrication-units.")
		return INTERACTION_HANDLED_PASS
	return INTERACTION_HANDLED_PASS

/obj/item/rsf/item_ctrl_click(mob/living/user)
	if(!Adjacent(user) || !istype(user))
		balloon_alert(user,"you are too far away.")
		return

	open_request(src, /datum/prompt/choice, PROC_REF(glass_chosen), answerer = user, choices = GLOB.robot_glass_options, anchor = user, radius = 40, radial = TRUE, autopick_single_option = TRUE, timeout = 0)

/obj/item/rsf/proc/glass_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/glass_choice = A.answer.answer_value
	if(glass_choice)
		balloon_alert(user, "container chosen: [glass_choice]")
		glasstype_name = glass_choice

DECLARE_INTERACTIONS(/obj/item/rsf, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_self.
/obj/item/rsf/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	var/options = list(
		"card deck" = image(icon = 'icons/obj/playing_cards.dmi', icon_state = "deck"),
		"card deck (big)" = image(icon = 'icons/obj/playing_cards.dmi', icon_state = "deck"),
		"casino chips (replica) x200" = image(icon = 'icons/obj/casino.dmi', icon_state = "spacecasinocash200"),
		"cigarette" = image(icon = 'icons/inventory/face/item.dmi', icon_state = "cig"),
		"container" = GLOB.robot_glass_options[glasstype_name],
		"dice pack (d6)" = image(icon = 'icons/obj/dice.dmi', icon_state = "dicebag"),
		"dice pack (gaming)" = image(icon = 'icons/obj/dice.dmi', icon_state = "magicdicebag"),
		"paper" = image(icon = 'icons/obj/bureaucracy.dmi', icon_state = "paper"),
		"pen" = image(icon = 'icons/obj/bureaucracy.dmi', icon_state = "pen"))
	open_request(src, /datum/prompt/choice, PROC_REF(product_chosen), answerer = user, choices = options, anchor = user, radius = 40, radial = TRUE, autopick_single_option = TRUE, timeout = 0)
	return TRUE

/obj/item/rsf/proc/product_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/choice = A.answer.answer_value
	if(choice)
		mode = choice
		play_sfx(src, SFX_EFFECTS_POP)
		balloon_alert(user, "you will synthesize: [mode]")

/obj/item/rsf/afterattack(atom/A, mob/user as mob, proximity)

	if(!proximity) return

	if(istype(user,/mob/living/silicon/robot))
		var/mob/living/silicon/robot/R = user
		if(R.stat || !R.cell || R.cell.charge <= 0)
			return
	else
		if(stored_matter <= 0)
			return

	if(!istype(A, /obj/structure/table) && !istype(A, /turf/simulated/floor))
		return

	play_sfx(src, SFX_MACHINES_CLICK, 0.2)
	var/used_energy = 0
	var/obj/product

	switch(mode)
		if("card deck")
			product = new /obj/item/deck/cards()
			used_energy = 200
		if("card deck (big)")
			product = new /obj/item/deck/cards/triple()
			used_energy = 600
		if("casino chips (replica) x200")
			product = new /obj/item/spacecasinocash_fake/c200()
			used_energy = 400
		if("cigarette")
			product = new /obj/item/clothing/mask/smokable/cigarette()
			used_energy = 10
		if("container")
			var/glasstype = GLOB.robot_glass_options[glasstype_name]
			product = new glasstype()
			used_energy = 50
		if("dice pack (d6)")
			product = new /obj/item/storage/pill_bottle/dice()
			used_energy = 200
		if("dice pack (gaming)")
			product = new /obj/item/storage/pill_bottle/dice_nerd()
			used_energy = 200
		if("paper")
			product = new /obj/item/paper()
			used_energy = 10
		if("pen")
			product = new /obj/item/pen()
			used_energy = 50

	balloon_alert(user, "dispensing [product ? product : "product"]...")
	if(!product)
		return
	product.forceMove(get_turf(A))

	if(isrobot(user))
		var/mob/living/silicon/robot/R = user
		R.draw_power(ROBOT_CELL_JOULES(used_energy), src, 0, TRUE)
	else
		stored_matter--
		to_chat(user,span_notice("the fabricator now holds [stored_matter]/30 fabrication-units."))
