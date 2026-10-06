/// An info button that, when clicked, puts some text in the user's chat
/obj/effect/abstract/info
	name = "info"
	icon = 'icons/effects/effects.dmi'
	icon_state = "info"

	mouse_opacity = MOUSE_OPACITY_OPAQUE

	/// What should the info button display when clicked?
	var/info_text

CAPABILITIES(/obj/effect/abstract/info)
	param(nameof(info_text), pos = 1)

/obj/effect/abstract/info/Click()
	. = ..()
	to_chat(usr, info_text)

/obj/effect/abstract/info/MouseEntered(location, control, params)
	. = ..()
	icon_state = "info_hovered"

/obj/effect/abstract/info/MouseExited()
	. = ..()
	icon_state = initial(icon_state)
