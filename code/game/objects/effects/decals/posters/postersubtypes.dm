/////////////////////////////////////////////////////////////////////////////////
// NT subtype
/////////////////////////////////////////////////////////////////////////////////
/obj/item/poster/nanotrasen // held object
	icon_state = "rolled_poster_nt"
	poster_type = /obj/structure/sign/poster/nanotrasen

/obj/item/poster/nanotrasen/Initialize(mapload, datum/decl/poster/P = null)
	if(!ispath(poster_decl) && !ispath(P) && !istype(P))
		poster_decl = get_poster_decl(/datum/decl/poster/nanotrasen, FALSE, null)
	return ..()

/obj/structure/sign/poster/nanotrasen // placed wall object
	roll_type = /obj/item/poster/nanotrasen


/////////////////////////////////////////////////////////////////////////////////
// Selectable "custom" subtype
/////////////////////////////////////////////////////////////////////////////////
/obj/item/poster/custom // held object
	name = "rolled-up poly-poster"
	desc = "The poster comes with its own automatic adhesive mechanism, for easy pinning to any vertical surface. This one is made from some kind of e-paper, and could display almost anything!"
	poster_type = /obj/structure/sign/poster/custom

/// Verb to change a custom poster's design
/obj/item/poster/custom/proc/select_poster_effect(mob/user, obj/item/held, datum/interaction/interaction)
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)

	var/mob/M = user
	var/list/options = list()
	var/list/datum/decl/poster/posters = GLOB.decls_repository.get_decls_of_type(/datum/decl/poster)
	for(var/option in posters)
		options[posters[option].name] = posters[option]

	om_ask(M, /datum/om/prompt/choice, PROC_REF(poster_chosen), choices = options, title = "Customize Poster", message = "Choose a poster!", requires = PROMPT_ADJACENT)

/obj/item/poster/custom/proc/poster_chosen(datum/om/prompt/choice/ask)
	if(ask.choices[ask.choice])
		poster_decl = ask.choices[ask.choice]
		name = "rolled-up poly-poster - [poster_decl.name]"
		to_chat(ask.answerer, "The poster is now: [ask.choice].")

// Wall object
/obj/structure/sign/poster/custom // placed wall object
	roll_type = /obj/item/poster/custom

/// Old object verbs.
EXTEND_INTERACTIONS(/obj/item/poster/custom, \
	INTERACT_VERB("Set Poster type", PROC_REF(select_poster_effect), REQ_IN_INVENTORY), \
)
