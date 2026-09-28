/obj/item/selectable_item
	name = "selectable item"
	desc = "If you find this, you should definitely report this..."
	icon = 'icons/obj/gifts.dmi'
	icon_state = "gift1"
	var/preface_string = "You are about to select an item. Are you sure you want to use it and select one?"
	var/preface_title = "selectable item"
	var/selection_string = "Select an item:"
	var/selection_title = "Item Selection"
	var/list/item_options = list("Gift" = /obj/item/a_gift, // ALLOW(instance_list): c: read-only per-subtype constant table (2 subtype overrides); a getter would share it, not worth it on a rare type
									"Health Analyzer" = /obj/item/healthanalyzer)

DECLARE_INTERACTIONS(/obj/item/selectable_item, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/selectable_item/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	om_ask(user, /datum/om/prompt/confirm, PROC_REF(preface_confirmed), title = preface_title, message = preface_string, ask_flags = ASK_CARRIED | ASK_CAPABLE)
	return TRUE

/obj/item/selectable_item/proc/preface_confirmed(datum/om/prompt/confirm/ask)
	om_ask(ask.answerer, /datum/om/prompt/choice, PROC_REF(item_selected), title = selection_title, message = selection_string, choices = item_options, ask_flags = ASK_CARRIED | ASK_CAPABLE)

/obj/item/selectable_item/proc/item_selected(datum/om/prompt/choice/ask)
	var/mob/user = ask.answerer
	var/chosen_item = item_options[ask.choice]
	if(chosen_item)
		user.drop_item()
		var/obj/item/result = new chosen_item(get_turf(user))
		user.put_in_active_hand(result)
		result.add_fingerprint(user)
		consume(src, user)
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
	item_options = list("Macrocillin" = /obj/item/reagent_containers/glass/beaker/vial/macrocillin,
						"Microcillin" = /obj/item/reagent_containers/glass/beaker/vial/microcillin,
						"Normalcillin" = /obj/item/reagent_containers/glass/beaker/vial/normalcillin)

/obj/item/selectable_item/chemistrykit/gender
	name = "gender chemistry kit"
	desc = "A pre-arranged home chemistry kit. This one is for rather specific set of gender-altering chemicals."
	preface_string = "This kit can be used to create a vial of a gender-altering chemical, but there's only enough material for one."
	preface_title = "Gender Chemistry Kit"
	item_options = list(REAGENT_ANDROROVIR = /obj/item/reagent_containers/glass/beaker/vial/androrovir,
						REAGENT_GYNOROVIR = /obj/item/reagent_containers/glass/beaker/vial/gynorovir,
						REAGENT_ANDROGYNOROVIR = /obj/item/reagent_containers/glass/beaker/vial/androgynorovir)
