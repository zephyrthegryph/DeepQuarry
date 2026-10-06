/////////////////////////////////////////////////////////////////////////////////
// NT subtype
/////////////////////////////////////////////////////////////////////////////////
/obj/item/poster/nanotrasen // held object
	icon_state = "rolled_poster_nt"
	poster_type = /obj/structure/sign/poster/nanotrasen

/obj/item/poster/nanotrasen/choose_design(P)
	if(!ispath(poster_decl) && !ispath(P) && !istype(P, /datum/decl/poster))
		poster_decl = get_poster_decl(/datum/decl/poster/nanotrasen, FALSE, null)
	..()

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
/obj/item/poster/custom/proc/select_poster_effect(datum/act/op/A)
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	var/mob/user = A.actor

	var/mob/M = user
	var/list/options = list()
	var/list/datum/decl/poster/posters = GLOB.decls_repository.get_decls_of_type(/datum/decl/poster)
	for(var/option in posters)
		options[posters[option].name] = posters[option]

	open_request(src, /datum/prompt/choice, PROC_REF(poster_chosen), answerer = M, choices = options, title = "Customize Poster", question = "Choose a poster!", ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)

/obj/item/poster/custom/proc/poster_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/ask = A.answer
	if(ask.choices[ask.value])
		poster_decl = ask.choices[ask.value]
		name = "rolled-up poly-poster - [poster_decl.name]"
		to_chat(ask.answerer, "The poster is now: [ask.value].")

// Wall object
/obj/structure/sign/poster/custom // placed wall object
	roll_type = /obj/item/poster/custom

/// Old object verbs.
CAPABILITIES(/obj/item/poster/custom)
	op("select_poster_effect", menu(), label("Set Poster type"), needs(carried()), then(PROC_REF(select_poster_effect)))
