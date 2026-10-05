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
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/selectable_item/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	open_request(src, /datum/prompt/yes_no, PROC_REF(preface_confirmed), answerer = user, title = preface_title, question = preface_string, ask_flags = ASK_CARRIED | ASK_CAPABLE, timeout = 0)
	return TRUE

/obj/item/selectable_item/proc/preface_confirmed(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	open_request(src, /datum/prompt/choice, PROC_REF(item_selected), answerer = A.request.answerer, title = selection_title, question = selection_string, choices = TYPE_TABLE_GET(src, selectable_item_options), ask_flags = ASK_CARRIED | ASK_CAPABLE, timeout = 0)

/obj/item/selectable_item/proc/item_selected(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/chosen_item = TYPE_TABLE_GET(src, selectable_item_options)[A.answer.value]
	if(chosen_item)
		if(!consume(src, user))
			return
		var/obj/item/result = new chosen_item(get_turf(user))
		user.put_in_active_hand(result)
		result.add_fingerprint(user)
	return


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
