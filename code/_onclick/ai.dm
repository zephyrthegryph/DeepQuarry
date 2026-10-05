/*
	AI ClickOn()

	Note currently ai restrained() returns 0 in all cases,
	therefore restrained code has been removed

	The AI can double click to move the camera (this was already true but is cleaner),
	or double click a mob to track them.

	Note that AI have no need for the adjacency proc, and so this proc is a lot cleaner.
*/
/mob/living/silicon/ai/DblClickOn(atom/A, params)
	if(client.buildmode) // comes after object.Click to allow buildmode gui objects to be clicked
		build_click(src, client.buildmode, params, A)
		return

	if(control_disabled || stat) return

	if(ismob(A))
		ai_actual_track(A)
	else
		A.move_camera_by_click(src)


// AI clicks route through the input router with the AI adapter (adapters.dm) when no op of the target answered them first:
// its own click table, then its interactions (INTERACT_SILICON) and silicon_use.

/mob/living/silicon/ai/UnarmedAttack(atom/A)
	actor_use(/datum/input_adapter/ai, src, A)
/mob/living/silicon/ai/RangedAttack(atom/A)
	actor_use(/datum/input_adapter/ai, src, A)

/*
	The AI's modifier actions are a mob's own. What a machine does for an AI's shift-, ctrl-, alt- or middle-click is a remote() op of the
	machine pinned to that gesture (the airlock's remote_bolts, the APC's remote_breaker, ...), which the input inbox resolves before the click
	gets here: the AI reaches it through its interface provider (library/mob/silicon.dm). What no op answers lands here as any mob's action.
*/

//
// Override AdjacentQuick for AltClicking
//

/mob/living/silicon/ai/TurfAdjacent(turf/T)
	return (GLOB.cameranet && GLOB.cameranet.checkTurfVis(T))
