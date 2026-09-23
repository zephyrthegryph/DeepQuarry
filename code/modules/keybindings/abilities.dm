// Ability keybinds (doc/rewrite/rules.md §5, doc/rewrite/interactions.md §3).
// One row per ability is generated into keybinding_definitions()
// (keybinding_defaults.dm); every row's command names this one verb with the
// ability's id, mirroring the ".input-category" pattern in hover.dm.

/client/verb/use_ability(id as text)
	set name = ".use-ability"
	set hidden = TRUE
	set instant = FALSE

	if(!isliving(mob))
		return
	dq_use_ability(mob, id)
