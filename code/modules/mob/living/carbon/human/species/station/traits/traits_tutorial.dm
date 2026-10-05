/*
A new Ability given to those human mobs that have a non-zero number of traits.
Verb is added by /datum/trait/proc/apply() in code\modules\mob\living\carbon\human\species\station\traits_vr\trait.dm file.
This proc gets called whenever the user is spawned, resleeved, autoresleeved and so forth.
If there are special cases that do NOT call this var that result in a completely new body -
I will fix it once I am informed of their existence.
Been tested - does NOT lead to multiples of the verb thanks to the |=.
Given the apply() proc is only called if they have verbs - this should avoid it erronously popping up for traitless people.

This ability intends to retrieve all positive, neutral and negative traits chosen in the character set-up
then retrieve their relevant vars by assuming the character's species has the full list. This should always work. Should

The ability is intended to be developed both as a message to chat and a tgui window.
The user is given the ability to choose which they would like whenever they press the ability to better suit whatever scenario they find themselves
thirsty for knowledge.

When adding new tutorials for trait subtypes, use <br> rather than \n newlines

TGUI backend path: code\modules\tgui\modules\trait_tutorial_tgui.dm
TGUI frontend path: tgui\packages\tgui\interfaces\TraitTutorial.tsx
*/





/mob/living/carbon/human/proc/trait_tutorial()
	set name = "Explain Custom Traits"
	set desc = "Click this verb to obtain a detailed tutorial on your selected traits. "
	set category = VERB_CAT_ABILITIES_GENERAL
	var/list/list_of_traits = species.traits
	if(!LAZYLEN(list_of_traits)) //Although we shouldn't show up if no traits, leaving this in case someone loses theirs after (re)spawning.
		to_chat(src, span_notice("You do not have any custom traits!"))
		return //Dont want an empty TGUI panel and list by accident after all.

	open_request(src, /datum/prompt/choice, PROC_REF(trait_tutorial_mode_chosen), answerer = src, title = "Choose preferred tutorial interface", question = "Would you like the tutorial text to be printed to chat?", choices = list("TGUI", "To Chat", "Cancel"), buttons = TRUE, timeout = 0)

/// The tutorial's tables: names, then name -> category, description and guide.
/mob/living/carbon/human/proc/trait_tutorial_tables()
	var/trait_names = list() //List of keys
	var/trait_category = list() // name:category
	var/trait_desc = list() // name:desc
	var/trait_tutorial = list() //name:tutorial
	for(var/trait in species.traits)
		var/datum/trait/T = GLOB.all_traits[trait]
		trait_names += T.name
		trait_desc[T.name] = T.desc
		trait_tutorial[T.name] = T.tutorial
		switch(T.category)
			if(TRAIT_TYPE_NEGATIVE)
				trait_category[T.name] = "Negative Trait"
			if(TRAIT_TYPE_NEUTRAL)
				trait_category[T.name] = "Neutral Trait"
			if(TRAIT_TYPE_POSITIVE)
				trait_category[T.name] = "Positive Trait"
	return list(trait_names, trait_category, trait_desc, trait_tutorial)

/mob/living/carbon/human/proc/trait_tutorial_mode_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/list/tables = trait_tutorial_tables()
	if(A.answer.value == "To Chat")
		open_request(src, /datum/prompt/choice, PROC_REF(trait_tutorial_trait_chosen), answerer = src, title = "Print to Chat", question = "Please choose the trait to be explained", choices = tables[1], timeout = 0)
	else if(A.answer.value == "TGUI")
		var/datum/tgui_module/trait_tutorial_tgui/fancy_UI = new /datum/tgui_module/trait_tutorial_tgui/
		fancy_UI.set_vars(tables[1], tables[2], tables[3], tables[4])
		fancy_UI.tgui_interact(src)

/mob/living/carbon/human/proc/trait_tutorial_trait_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/to_chat_choice = A.answer.value
	var/list/tables = trait_tutorial_tables()
	var/list/trait_category = tables[2]
	var/list/trait_desc = tables[3]
	var/list/trait_tutorial = tables[4]
	to_chat(src,span_notice(span_bold("Name:") + " [to_chat_choice] \n " + span_bold("Category:")  + " [trait_category[to_chat_choice]] \n " + span_bold("Description:")  + " [trait_desc[to_chat_choice]] \n " + span_bold("Guide:")  + " \n [trait_tutorial[to_chat_choice]]"))
