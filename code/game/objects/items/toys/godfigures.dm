/obj/item/godfig
	name = "religious icon"
	desc = "A painted holy figure of a plain looking human man in a robe."
	icon = 'icons/obj/chaplain.dmi'
	icon_state = "mrobe"
	force = 10
	throw_speed = 1
	throw_range = 4
	throwforce = 10
	w_class = ITEMSIZE_SMALL


/obj/item/godfig/proc/resprite_figure_effect(datum/act/op/A)
	var/mob/user = A.actor

	var/mob/M = user
	var/list/options = list()
	options["Painted - Robed Human Female"] = "frobe"
	options["Painted - Robed Human Male (Pale)"] = "mrobe"
	options["Painted - Robed Human Male (Dark)"] = "mrobedark"
	options["Painted - Bearded Human"] = "mpose"
	options["Painted - Human Male Warrior"] = "mwarrior"
	options["Painted - Human Female Warrior"] = "fwarrior"
	options["Painted - Human Male Hammer"] = "hammer"
	options["Painted - Horned God"] = "horned"
	options["Obsidian - Human Male"] = "onyxking"
	options["Obsidian - Human Female"] = "onyxqueen"
	options["Obsidian - Animal Headed Male"] = "onyxanimalm"
	options["Obsidian - Animal Headed Female"] = "onyxanimalf"
	options["Obsidian - Bird Headed Figure"] = "onyxbird"
	options["Stone - Seated Figure"] = "stoneseat"
	options["Stone - Head"] = "stonehead"
	options["Stone - Dwarf"] = "stonedwarf"
	options["Stone - Animal"] = "stoneanimal"
	options["Stone - Fertility"] = "stonevenus"
	options["Stone - Snake"] = "stonesnake"
	options["Bronze - Elephantine"] = "elephant"
	options["Bronze - Many-armed"] = "bronzearms"
	options["Robot"] = "robot"
	options["Singularity"] = "singularity"
	options["Gemstone Eye"] = "gemeye"
	options["Golden Skull"] = "skull"
	options["Goatman"] = "devil"
	options["Sun Gem"] = "sun"
	options["Moon Gem"] = "moon"
	options["Tajaran Figure"] = "catrobe"

	om_ask(M, /datum/om/prompt/choice, PROC_REF(figure_chosen), title = "Customize Figure", message = "Choose your icon!", choices = options, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE)

/obj/item/godfig/proc/figure_chosen(datum/om/prompt/choice/ask)
	var/list/options = ask.choices
	var/choice = ask.choice
	icon_state = options[choice]
	if(options[choice] == "frobe")
		desc = "A painted holy figure of a plain looking human woman in a robe."
	else if(options[choice] == "mrobe")
		desc = "A painted holy figure of a plain looking human man in a robe."
	else if(options[choice] == "mrobedark")
		desc = "A painted holy figure of a plain looking human man in a robe.."
	else if(options[choice] == "mpose")
		desc = "A painted holy figure of a rather grandiose bearded human."
	else if(options[choice] == "mwarrior")
		desc = "A painted holy figure of a powerful human male warrior."
	else if(options[choice] == "fwarrior")
		desc = "A painted holy figure of a powerful human female warrior."
	else if(options[choice] == "hammer")
		desc = "A painted holy figure of a human holding a hammer aloft."
	else if(options[choice] == "horned")
		desc = "A painted holy figure of a human man crowned with antlers."
	else if(options[choice] == "onyxking")
		desc = "An obsidian holy figure of a human man wearing a grand hat."
	else if(options[choice] == "onyxqueen")
		desc = "An obsidian holy figure of a human woman wearing a grand hat."
	else if(options[choice] == "onyxanimalm")
		desc = "An obsidian holy figure of a human man with the head of an animal."
	else if(options[choice] == "onyxanimalf")
		desc = "An obsidian holy figure of a human woman with the head of an animal."
	else if(options[choice] == "onyxbird")
		desc = "An obsidian holy figure of a human with the head of a bird."
	else if(options[choice] == "stoneseat")
		desc = "A stone holy figure of a cross-legged human."
	else if(options[choice] == "stonehead")
		desc = "A stone holy figure of an imposing crowned head."
	else if(options[choice] == "stonedwarf")
		desc = "A stone holy figure of a somewhat ugly dwarf."
	else if(options[choice] == "stoneanimal")
		desc = "A stone holy figure of a four-legged animal of some sort."
	else if(options[choice] == "stonevenus")
		desc = "A stone holy figure of a lovingly rendered pregnant woman."
	else if(options[choice] == "stonesnake")
		desc = "A stone holy figure of a coiled snake ready to strike."
	else if(options[choice] == "elephant")
		desc = "A bronze holy figure of a dancing human with the head of an elephant."
	else if(options[choice] == "bronzearms")
		desc = "A bronze holy figure of a human.with four arms."
	else if(options[choice] == "robot")
		desc = "A titanium holy figure of a synthetic humanoid."
	else if(options[choice] == "singularity")
		desc = "A holy figure of some kind of energy formation."
	else if(options[choice] == "gemeye")
		desc = "A gemstone holy figure of a sparkling eye."
	else if(options[choice] == "skull")
		desc = "A golden holy figure of a humanoid skull."
	else if(options[choice] == "devil")
		desc = "A painted holy figure of a seated humanoid goat with wings."
	else if(options[choice] == "sun")
		desc = "A holy figure of a star."
	else if(options[choice] == "moon")
		desc = "A holy figure of a small planetoid."
	else if(options[choice] == "catrobe")
		desc = "A painted holy figure of a plain looking Tajaran in a robe."

	to_chat(ask.answerer, "The religious icon is now a [choice]. All hail!")
	return 1



/obj/item/godfig/proc/rename_fig_effect(datum/act/op/A)
	var/mob/user = A.actor

	var/mob/M = user
	if(!M.mind)	return 0

	om_ask(M, /datum/om/prompt/text, PROC_REF(figure_named), message = "What do you want to name the icon?", default = "", max_length = MAX_NAME_LEN, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE)

/obj/item/godfig/proc/figure_named(datum/om/prompt/text/ask)
	var/mob/M = ask.answerer
	var/input = ask.text
	if(input)
		name = "icon of " + input
		to_chat(M, "You name the figure. Glory to [input]!.")

/// Old object verbs.
CAPABILITIES(/obj/item/godfig)
	op("resprite_figure_effect", menu(), label("Customize Figure"), needs(carried()), then(PROC_REF(resprite_figure_effect)))
	op("rename_fig_effect", menu(), label("Name Figure"), needs(carried()), then(PROC_REF(rename_fig_effect)))
