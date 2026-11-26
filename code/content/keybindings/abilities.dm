// Ability keybinds. One row per ability op is generated into keybinding_definitions() (keybinding_defaults.dm); every row's command names this
// one verb with the op's key (the ABILITY_ID_* defines), mirroring the ".input-category" pattern in hover.dm. The verb only starts the op: the
// grant, the requirements and the cost are the op's.

/client/verb/use_ability(id as text)
	set name = ".use-ability"
	set hidden = TRUE
	set instant = FALSE

	if(!isliving(mob))
		return
	perform_op(mob, mob, id, null, ORIGIN_HOTKEY)

/// The hotkey of list slot `slot`: uses the ability that stands in that place of the Abilities tab (its refusal is told to the player). A key
/// pressed for an empty slot does nothing.
/client/verb/use_ability_slot(slot as num)
	set name = ".use-ability-slot"
	set hidden = TRUE
	set instant = FALSE

	mob?.use_ability_slot(slot)
