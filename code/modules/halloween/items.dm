#define CANDYBOWL_EMPTY "the candy bowl is empty"

/obj/item/storage/bag/plasticbag/halloween
	name = "halloween bag"
	icon = 'icons/obj/halloween/trash.dmi'
	icon_state = "halloween_bag"


CAPABILITIES(/obj/item/storage/bag/plasticbag/halloween)
	configure(storage(accepts = list(
		/obj/item/reagent_containers/food/snacks/candy,
		/obj/item/reagent_containers/food/snacks/candy_corn,
		/obj/item/reagent_containers/food/snacks/chocolatebar,
		/obj/item/reagent_containers/food/snacks/chocolatepiece,
		/obj/item/reagent_containers/food/snacks/chocolatepiece/white,
		/obj/item/reagent_containers/food/snacks/chocolatepiece/truffle,
		/obj/item/reagent_containers/food/snacks/chocolateegg,
		/obj/item/reagent_containers/food/snacks/no_raisin,
		/obj/item/reagent_containers/food/snacks/butterscotch,
		/obj/item/reagent_containers/food/snacks/spicy_boys,
		/obj/item/reagent_containers/food/snacks/welders_original,
		/obj/item/reagent_containers/food/snacks/organ,
		/obj/item/reagent_containers/food/snacks/mint,
		/obj/item/storage/box/admints,
		/obj/item/reagent_containers/food/snacks/cookiesnack,
		/obj/item/reagent_containers/food/snacks/cb01,
		/obj/item/reagent_containers/food/snacks/cb02,
		/obj/item/reagent_containers/food/snacks/cb03,
		/obj/item/reagent_containers/food/snacks/cb04,
		/obj/item/reagent_containers/food/snacks/cb05,
		/obj/item/reagent_containers/food/snacks/cb06,
		/obj/item/reagent_containers/food/snacks/cb07,
		/obj/item/reagent_containers/food/snacks/cb08,
		/obj/item/reagent_containers/food/snacks/cb09,
		/obj/item/reagent_containers/food/snacks/cb10,
		/obj/item/reagent_containers/food/snacks/reishicup,
		/obj/item/reagent_containers/food/snacks/antball,
		/obj/item/reagent_containers/food/snacks/honey_candy,
		/obj/item/storage/box/winegum,
		/obj/item/storage/box/shrimpsandbananas,
		/obj/item/clothing/mask/chewable/candy/lolli), refuses = list(/obj/item/disk/nuclear)))

/obj/structure/candybowl
	name = "candy bowl"
	desc = "It's a bowl, with candy! Take only one, please."
	anchored = FALSE
	density = FALSE
	icon = 'icons/obj/halloween/bowls.dmi'
	icon_state = "fullcandy"

	var/has_candy = TRUE



	var/static/list/badcandy = list(
		/obj/item/reagent_containers/food/snacks/no_raisin,
		/obj/item/reagent_containers/food/snacks/egg/rotten,
		/obj/item/reagent_containers/food/snacks/hakarl
	)

	var/list/treated

TYPE_TABLE_DECLARE(/obj/structure/candybowl, candy_choices, list( \
		/obj/item/reagent_containers/food/snacks/cb01, \
		/obj/item/reagent_containers/food/snacks/cb02, \
		/obj/item/reagent_containers/food/snacks/cb03, \
		/obj/item/reagent_containers/food/snacks/cb04, \
		/obj/item/reagent_containers/food/snacks/cb05, \
		/obj/item/reagent_containers/food/snacks/cb06, \
		/obj/item/reagent_containers/food/snacks/cb07, \
		/obj/item/reagent_containers/food/snacks/cb08, \
		/obj/item/reagent_containers/food/snacks/cb09, \
		/obj/item/reagent_containers/food/snacks/cb10, \
		/obj/item/reagent_containers/food/snacks/candy_corn, \
		/obj/item/reagent_containers/food/snacks/triton, \
		/obj/item/reagent_containers/food/snacks/saturn, \
		/obj/item/reagent_containers/food/snacks/jupiter, \
		/obj/item/reagent_containers/food/snacks/pluto, \
		/obj/item/reagent_containers/food/snacks/mars, \
		/obj/item/reagent_containers/food/snacks/venus, \
		/obj/item/reagent_containers/food/snacks/oort \
	))

DECLARE_INTERACTIONS(/obj/structure/candybowl, \
	INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand), REQ_TARGET_STATE(/obj/structure/candybowl/proc/can_search)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Requirement: TRUE, or why the bowl can't be searched.
/obj/structure/candybowl/proc/can_search(mob/user, atom/target, obj/item/held)
	if(!has_candy)
		return "there is no candy, someone took too many"
	if(task_busy(src))
		return "someone is already looking through \the [src]"
	return TRUE

/// Old attack_hand.
/obj/structure/candybowl/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)

	task_timed(user, 5 SECONDS, src, src, PROC_REF(search_done), list(user), claims = TRUE)
	return TRUE

/obj/structure/candybowl/proc/search_done(mob/user)
	if(!has_candy)
		return
	if(LAZYACCESS(treated, user.ckey))
		open_request(src, /datum/prompt/choice/candybowl_repeat, PROC_REF(candybowl_repeat_answered), answerer = user)
		return
	finish_candy_search(user, null)

/obj/structure/candybowl/proc/candybowl_repeat_answered(datum/act/request/context)
	if(!context.answer)
		if(!isnull(context.request.value) && context.request.last_error == CANDYBOWL_EMPTY)
			SStgui.update_uis(src)
		return
	finish_candy_search(context.request.answerer, context.answer.value)
	SStgui.update_uis(src)

/obj/structure/candybowl/proc/finish_candy_search(mob/user, choice)
	var/thegoods
	if(LAZYACCESS(treated, user.ckey))
		if(choice == "Reach in...")
			if(prob(35))
				thegoods = pick(badcandy)
				to_chat(user, span_danger("That's one too many! The bowl is empty now..."))
				empty()
			else
				thegoods = pick(TYPE_TABLE_GET(src, candy_choices))
	else
		thegoods = pick(TYPE_TABLE_GET(src, candy_choices))
		LAZYSET(treated, user.ckey, TRUE)

	add_fingerprint(user)
	if(!thegoods)
		return
	var/goodie = new thegoods(src)
	user.put_in_hands(goodie)

/// Old attackby.
/obj/structure/candybowl/proc/interaction_item(mob/user, obj/item/O, datum/interaction/interaction)
	if(istype(O, /obj/item/reagent_containers/food/snacks) && !has_candy)
		to_chat(user, span_notice("You add \the [O] to the bowl."))
		if(prob(20))
			fill()
		consume(O, user)
	return INTERACTION_HANDLED_PASS

/obj/structure/candybowl/proc/empty()
	var/newname = "empty " + initial(name)
	name = newname
	desc = "An empty bowl! Someone took too many candies..."
	icon_state = "nocandy"
	has_candy = FALSE

	update_icon()

/obj/structure/candybowl/proc/fill()
	name = initial(name)
	desc = initial(desc)
	icon_state = "fullcandy"
	has_candy = TRUE

	update_icon()

/obj/structure/candybowl/medical
	name = "medical candy bowl"

TYPE_TABLE(/obj/structure/candybowl/medical, candy_choices, ..() + list( \
		/obj/item/clothing/mask/chewable/candy/lolli, \
		/obj/item/reagent_containers/food/snacks/organ, \
		/obj/item/storage/box/shrimpsandbananas \
	))

/obj/structure/candybowl/engineering
	name = "engineering candy bowl"

TYPE_TABLE(/obj/structure/candybowl/engineering, candy_choices, ..() + list( \
		/obj/item/reagent_containers/food/snacks/welders_original, \
		/obj/item/reagent_containers/food/snacks/butterscotch, \
		/obj/item/reagent_containers/food/snacks/chocolatepiece \
	))

/obj/structure/candybowl/cargo
	name = "cargo candy bowl"

TYPE_TABLE(/obj/structure/candybowl/cargo, candy_choices, ..() + list( \
		/obj/item/reagent_containers/food/snacks/butterscotch, \
		/obj/item/reagent_containers/food/snacks/honey_candy, \
		/obj/item/storage/box/winegum, \
	))

/obj/structure/candybowl/science
	name = "science candy bowl"

TYPE_TABLE(/obj/structure/candybowl/science, candy_choices, ..() + list( \
		/obj/item/reagent_containers/food/snacks/reishicup, \
		/obj/item/reagent_containers/food/snacks/antball, \
		/obj/item/storage/box/winegum, \
		/obj/item/reagent_containers/food/snacks/chocolatepiece/truffle \
	))

/obj/structure/candybowl/security
	name = "security candy bowl"

TYPE_TABLE(/obj/structure/candybowl/security, candy_choices, ..() + list( \
		/obj/item/reagent_containers/food/snacks/spicy_boys, \
		/obj/item/reagent_containers/food/snacks/chocolatepiece/white, \
		/obj/item/reagent_containers/food/snacks/candy_corn \
	))

/obj/structure/boxpile
	name = "box pile"
	desc = "It's a bunch of costume boxes! Maybe one could fit you..."
	icon = 'icons/obj/halloween/trash64x64.dmi'
	icon_state = "bigboxes"

	anchored = TRUE

	var/list/ckeys_that_took
	var/list/costumes

/obj/structure/boxpile/Initialize(mapload)
	. = ..()

	costumes = typesof(/obj/item/storage/box/halloween/)

DECLARE_INTERACTIONS(/obj/structure/boxpile, INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand)))

/// Old attack_hand.
/obj/structure/boxpile/proc/interaction_hand(mob/living/user, obj/item/held, datum/interaction/interaction)
	task_timed(user, 5 SECONDS, src, src, PROC_REF(rummage_done), list(user), claims = TRUE)
	return TRUE

/obj/structure/boxpile/proc/rummage_done(mob/living/user)
	if(!user.ckey)
		return
	if(LAZYACCESS(ckeys_that_took, user.ckey))
		to_chat(user, span_notice("Nothing else fits you here!"))
		return
	to_chat(user, span_notice("After looking around, you found a costume that fits you!"))
	LAZYSET(ckeys_that_took, user.ckey, TRUE)
	var/obj/item/box = pick(costumes)
	new box(loc)

/datum/prompt/choice/candybowl_repeat
	question = "You already took one! Take more?"
	title = "Take another..."
	choices = list("Reach in...", "Leave it!")
	buttons = TRUE
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/candybowl_repeat/recheck_extra()
	var/mob/user = answerer
	var/obj/structure/candybowl/bowl = owner
	if(!istype(user) || QDELETED(user) || !istype(bowl) || QDELETED(bowl))
		return "gone"
	return bowl.has_candy ? null : CANDYBOWL_EMPTY

#undef CANDYBOWL_EMPTY
