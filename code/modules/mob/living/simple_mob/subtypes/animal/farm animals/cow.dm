/mob/living/simple_mob/animal/passive/cow
	name = "cow"
	desc = "Known for their milk, just don't tip them over."
	tt_desc = "E Bos taurus"
	icon_state = "cow"
	icon_living = "cow"
	icon_dead = "cow_dead"
	icon_gib = "cow_gib"

	endurance = 50

	response_help  = "pets"
	response_disarm = "gently pushes aside"
	response_harm   = "kicks"
	attacktext = list("kicked")

	organ_names = /datum/decl/mob_organ_names/cow

	say_list_type = /datum/say_list/cow

	meat_amount = 10
	meat_type = /obj/item/reagent_containers/food/snacks/meat

	var/datum/reagents/udder = null

CAPABILITIES(/mob/living/simple_mob/animal/passive/cow)
	owns_one(nameof(udder), /datum/reagents)

/mob/living/simple_mob/animal/passive/cow/Initialize(mapload)
	. = ..()

	rel_set(src, nameof(udder), new /datum/reagents(50)) // ALLOW(decl): holder takes constructor args
	rel_set(udder, nameof(udder.my_atom), src)

	add_hose_connector(/datum/hose_connector/output/cow) // Moo?

EXTEND_INTERACTIONS(/mob/living/simple_mob/animal/passive/cow, \
	INTERACT_ITEM(null, PROC_REF(cow_interaction_item)), \
	INTERACT_HAND_UNGATED_AS(I_DISARM, "Tip over", PROC_REF(cow_interaction_hand)))

/// Old attackby: milking.
/mob/living/simple_mob/animal/passive/cow/proc/cow_interaction_item(mob/user, obj/item/O, datum/interaction/interaction)
	. = TRUE
	var/obj/item/reagent_containers/glass/G = O
	if(stat == CONSCIOUS && istype(G) && G.is_open_container())
		act_message(user, src, null, MSG_OTHERS(span_notice("%U% milks %T% using %I%.")), item = O)
		var/transfered = udder.trans_id_to(G, REAGENT_ID_MILK, rand(5,10))
		if(G.reagents.total_volume >= G.volume)
			to_chat(user, span_red("The [O] is full."))
		if(!transfered)
			to_chat(user, span_red("The udder is dry. Wait a bit longer..."))
	else
		return FALSE

/mob/living/simple_mob/animal/passive/cow/life_type_post_due()
	return TRUE

/mob/living/simple_mob/animal/passive/cow/life_type_post(datum/seq_frame/life/F)
	..()
	if(src.stat == CONSCIOUS)
		if(src.udder && prob(5))
			src.udder.add_reagent(REAGENT_ID_MILK, rand(5, 10))

/// Old attack_hand: cow tipping.
/mob/living/simple_mob/animal/passive/cow/proc/cow_interaction_hand(mob/living/carbon/M, obj/item/held, datum/interaction/interaction)
	. = TRUE
	if(!stat && interaction.stance == I_DISARM && icon_state != icon_dead)
		act_message(M, src, MSG_SELF(span_notice("You tip over %T%.")), MSG_OTHERS(span_warning("%U% tips over %T%.")))
		status_at_least(EFFECT_WEAKENED, 30)
		icon_state = icon_dead
		after(src, rand(2 SECONDS, 5 SECONDS), PROC_REF(get_up_after_tipping), with = list(M))
	else
		return FALSE

/datum/say_list/cow
	speak = list("moo?","moo","MOOOOOO")
	emote_hear = list("brays", "moos","moos hauntingly")
	emote_see = list("shakes its head")

/datum/decl/mob_organ_names/cow
TYPE_TABLE(/datum/decl/mob_organ_names/cow, mob_organ_hit_zones, list("head", "torso", "left foreleg", "right foreleg", "left hind leg", "right hind leg", "udder"))

/mob/living/simple_mob/animal/passive/cow/proc/get_up_after_tipping(mob/M)
	if(!stat && M)
		icon_state = icon_living
		var/list/responses = list(	"[src] looks at you imploringly.",
									"[src] looks at you pleadingly",
									"[src] looks at you with a resigned expression.",
									"[src] seems resigned to its fate.")
		to_chat(M, pick(responses))

