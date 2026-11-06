/obj/item/reagent_containers/food/snacks/nugget
	name = "chicken nugget"
	icon_state = "nugget_lump"
	bitesize = 3

CAPABILITIES(/obj/item/reagent_containers/food/snacks/nugget)
	rolls(nameof(icon_state), PROC_REF(roll_look))
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 4)))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/item/reagent_containers/food/snacks/nugget/proc/roll_look(datum/roller/R)
	var/shape = R.choose(list("lump", "star", "lizard", "corgi"))
	desc = "A chicken nugget vaguely shaped like a [shape]."
	return "nugget_[shape]"
