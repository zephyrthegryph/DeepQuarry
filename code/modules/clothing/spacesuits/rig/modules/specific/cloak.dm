/obj/item/rig_module/stealth_field

	name = "active camouflage module"
	desc = "A robust hardsuit-integrated stealth module."
	icon_state = "cloak"

	toggleable = 1
	disruptable = 1
	disruptive = 0

	use_power_cost = 50
	active_power_cost = 10
	passive_power_cost = 0
	module_cooldown = 30

	activate_string = "Enable Cloak"
	deactivate_string = "Disable Cloak"

	interface_name = "integrated stealth system"
	interface_desc = "An integrated active camouflage system."

	suit_overlay_active =   "stealth_active"
	suit_overlay_inactive = "stealth_inactive"

/obj/item/rig_module/stealth_field/activate(skip_engage = 0, mob/user)

	if(!..())
		return 0

	var/mob/living/carbon/human/H = holder.wearer()

	to_chat(H, span_boldnotice("You are now nearly invisible to normal detection."))
	H.alpha = 5

	anim(get_turf(H), H, 'icons/effects/effects.dmi', "electricity",null,20,null)

	act_message(H, null, others = "%U% vanishes into thin air!")

/obj/item/rig_module/stealth_field/deactivate(forced = FALSE, mob/user)

	if(!..())
		return 0

	var/mob/living/carbon/human/H = holder.wearer()

	to_chat(H, span_danger("You are now visible."))

	anim(get_turf(H), H,'icons/mob/mob.dmi',,"uncloak",,H.dir)
	anim(get_turf(H), H, 'icons/effects/effects.dmi', "electricity",null,20,null)
	H.alpha = initial(H.alpha)

	act_message(H, null, others = "%U% appears from thin air!")
	play_sfx(H, SFX_EFFECTS_STEALTHOFF, 1.5, extrarange = 0)
