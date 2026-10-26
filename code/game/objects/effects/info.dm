/// An info button that, when clicked, puts some text in the user's chat
/obj/effect/abstract/info
	name = "info"
	icon = 'icons/effects/effects.dmi'
	icon_state = "info"

	mouse_opacity = MOUSE_OPACITY_OPAQUE

	/// What should the info button display when clicked?
	var/info_text

CAPABILITIES(/obj/effect/abstract/info)
	click_on(PROC_REF(info_clicked))
	hover(PROC_REF(info_hovered))
	param(nameof(info_text), pos = 1)

/obj/effect/abstract/info/proc/info_clicked(datum/act/input/A)
	input_resolve_click(new /datum/input_event/click(A.actor, src, A.native?["location"], A.native?["control"], A.params))
	to_chat(A.actor, info_text)
	return TRUE

/// The button lights up while the mouse is over it.
/obj/effect/abstract/info/proc/info_hovered(datum/act/input/A)
	set_icon_state(A.entered ? "info_hovered" : initial(icon_state))
