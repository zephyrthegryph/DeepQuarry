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

/// The designs a custom poster can show, by name.
/obj/item/poster/custom/proc/poster_options(datum/act/A)
	var/list/options = list()
	var/list/datum/decl/poster/posters = GLOB.decls_repository.get_decls_of_type(/datum/decl/poster)
	for(var/option in posters)
		options[posters[option].name] = posters[option]
	return options

/// Verb to change a custom poster's design
/obj/item/poster/custom/proc/select_poster_effect(datum/act/op/A)
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	var/picked = A.step_value("poster")
	var/list/options = poster_options(A)
	if(options[picked])
		poster_decl = options[picked]
		name = "rolled-up poly-poster - [poster_decl.name]"
		to_chat(A.actor, "The poster is now: [picked].")

// Wall object
/obj/structure/sign/poster/custom // placed wall object
	roll_type = /obj/item/poster/custom

/// Old object verbs.
CAPABILITIES(/obj/item/poster/custom)
	op("select_poster_effect", menu(), label("Set Poster type"), needs(carried()), asks(/datum/prompt/choice, fields = list("title" = "Customize Poster", "question" = "Choose a poster!", "choices" = computed(PROC_REF(poster_options)), "ask_flags" = ASK_ADJACENT | ASK_CAPABLE, "timeout" = 0), step = "poster"), then(PROC_REF(select_poster_effect)))
