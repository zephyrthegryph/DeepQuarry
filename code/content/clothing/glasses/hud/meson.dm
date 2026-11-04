/obj/item/clothing/glasses/omnihud/eng/meson
	name = "meson scanner HUD"
	desc = "A headset equipped with a scanning lens and mounted retinal projector. It doesn't provide any eye protection, but it's less obtrusive than goggles."
	icon = 'icons/vore/custom_items_vr.dmi'
	icon_override = 'icons/vore/custom_clothes_vr.dmi'
	icon_state = "projector"
	off_state = "projector-off"
	toggleable = 1
	vision_flags = SEE_TURFS //but they can spot breaches. Due to the way HUDs work, they don't provide darkvision up-close the way mesons do.
	flash_protection = 0 //it's an open, single-eye retinal projector. there's no way it protects your eyes from flashes or welders.
	can_shade = FALSE
	specialty_goggles = TRUE
	hud_goggles = TRUE

CAPABILITIES(/obj/item/clothing/glasses/omnihud/eng/meson)
	configure(item_worn(covers = 0))
	op("omnihud_meson_projector_self", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Toggle projector"), then(PROC_REF(omnihud_meson_projector_self)))
	op("meson_toggleprojector_verb", menu(), label("Toggle projector"), needs(carried()), then(PROC_REF(meson_toggleprojector_verb)))

/// Old attack_self.
/obj/item/clothing/glasses/omnihud/eng/meson/proc/omnihud_meson_projector_self(datum/act/op/A)
	if(!active)
		meson_toggleprojector_verb(A)

/// Old verb "Toggle projector".
/obj/item/clothing/glasses/omnihud/eng/meson/proc/meson_toggleprojector_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(!isliving(user)) return
	if(user.stat) return
	if(toggleable)
		if(active)
			active = 0
			set_icon_state(off_state)
			set_item_state("[initial(item_state)]-off")
			to_chat(user, "You deactivate the retinal projector on the [src].")
		else
			active = 1
			set_icon_state(initial(icon_state))
			set_item_state(initial(item_state))
			to_chat(user, "You activate the retinal projector on the [src].")
		user.update_mob_action_buttons()
