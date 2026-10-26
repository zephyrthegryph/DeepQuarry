/obj/item/selectable_item
	name = "selectable item"
	desc = "If you find this, you should definitely report this..."
	icon = 'icons/obj/gifts.dmi'
	icon_state = "gift1"
	var/preface_string = "You are about to select an item. Are you sure you want to use it and select one?"
	var/preface_title = "selectable item"
	var/selection_string = "Select an item:"
	var/selection_title = "Item Selection"

TYPE_TABLE_DECLARE(/obj/item/selectable_item, selectable_item_options, list("Gift" = /obj/item/a_gift, \
									"Health Analyzer" = /obj/item/healthanalyzer))

CAPABILITIES(/obj/item/selectable_item)
	op("self", in_hand(),
		asks(/datum/prompt/yes_no, fields = list("title" = nameof(preface_title), "question" = nameof(preface_string), "ask_flags" = ASK_CARRIED | ASK_CAPABLE, "timeout" = 0), step = "preface"),
		asks(/datum/prompt/choice, fields = list("title" = nameof(selection_title), "question" = nameof(selection_string), "choices" = computed(PROC_REF(item_choices)), "ask_flags" = ASK_CARRIED | ASK_CAPABLE, "timeout" = 0), step = "item", when = PROC_REF(preface_confirmed)),
		then(PROC_REF(interaction_self)))

/// The items the holder may pick from.
/obj/item/selectable_item/proc/item_choices(datum/act/A)
	return TYPE_TABLE_GET(src, selectable_item_options)

/// The preface was answered yes: the selection is asked next.
/obj/item/selectable_item/proc/preface_confirmed(datum/act/op/A)
	return !!A.step_value("preface")

/// Old attack_self: the item picked is swapped for the selectable item.
/obj/item/selectable_item/proc/interaction_self(datum/act/op/A)
	var/picked = A.step_value("item")
	if(!isnull(picked))
		exchange_for(A.actor, picked)
	return TRUE

/// A request's answer (the selection-kit unit tests answer through it): the same exchange.
/obj/item/selectable_item/proc/item_selected(datum/act/request/A)
	if(!A.answer)
		return
	exchange_for(A.request.answerer, A.answer.value)

/// The kit is used up for the item named `picked` in the user's hand.
/obj/item/selectable_item/proc/exchange_for(mob/user, picked)
	var/chosen_item = TYPE_TABLE_GET(src, selectable_item_options)[picked]
	if(chosen_item)
		if(!consume(src, user))
			return
		var/obj/item/result = new chosen_item(get_turf(user))
		user.put_in_active_hand(result)
		result.add_fingerprint(user)


/obj/item/selectable_item/chemistrykit
	icon = 'icons/obj/chemical.dmi'
	icon_state = "chemkit"
	selection_string = "Select a chemical:"
	selection_title = "Chemical Selection"

/obj/item/selectable_item/chemistrykit/size
	name = "size chemistry kit"
	desc = "A pre-arranged home chemistry kit. This one is for rather specific set of size-altering chemicals."
	preface_string = "This kit can be used to create a vial of a size-altering chemical, but there's only enough material for one."
	preface_title = "Size Chemistry Kit"

TYPE_TABLE(/obj/item/selectable_item/chemistrykit/size, selectable_item_options, list("Macrocillin" = /obj/item/reagent_containers/glass/beaker/vial/macrocillin, \
						"Microcillin" = /obj/item/reagent_containers/glass/beaker/vial/microcillin, \
						"Normalcillin" = /obj/item/reagent_containers/glass/beaker/vial/normalcillin))

/obj/item/selectable_item/chemistrykit/gender
	name = "gender chemistry kit"
	desc = "A pre-arranged home chemistry kit. This one is for rather specific set of gender-altering chemicals."
	preface_string = "This kit can be used to create a vial of a gender-altering chemical, but there's only enough material for one."
	preface_title = "Gender Chemistry Kit"

TYPE_TABLE(/obj/item/selectable_item/chemistrykit/gender, selectable_item_options, list(REAGENT_ANDROROVIR = /obj/item/reagent_containers/glass/beaker/vial/androrovir, \
						REAGENT_GYNOROVIR = /obj/item/reagent_containers/glass/beaker/vial/gynorovir, \
						REAGENT_ANDROGYNOROVIR = /obj/item/reagent_containers/glass/beaker/vial/androgynorovir))
