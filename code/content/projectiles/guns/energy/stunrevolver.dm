/*
 * Stun Revolver
 */
/obj/item/gun/energy/stunrevolver
	name = "stun revolver"
	desc = "A LAEP20 \"Aktzin\". Designed and produced by Lawson Arms under the wing of Hephaestus, \
	several TSCs have been trying to get a hold of the blueprints for half a decade."
	icon = 'icons/obj/gun.dmi' // Gun Sprites
	icon_state = "stunrevolver"
	item_state = "stunrevolver"
	projectile_type = /obj/item/projectile/energy/electrode/strong
	charge_cost = 400

CAPABILITIES(/obj/item/gun/energy/stunrevolver)
	configure(atom_rules(description_fluff = "Lawson Arms is Hephaestus Industries’ main personal-energy-weapon branding, \
	often sold alongside MarsTech projectile weapons to security and law enforcement agencies. \
	The Aktzin's capsule-based stun ammunition is a closely guarded Hephaestus Industries patent, \
	and the company has been particularly litigious towards any attempted imitators."))

/*
 * Detective Stun Revolver
 */
/obj/item/gun/energy/stunrevolver/detective
	desc = "A LAEP20 \"Aktzin\". Designed and produced by Lawson Arms under the wing of Hephaestus, \
	several TSCs have been trying to get a hold of the blueprints for half a decade."
	var/unique_reskin


/// The detective's revolver is drawn from the sprite it was reskinned to.
/obj/item/gun/energy/stunrevolver/detective/charge_state_name()
	return unique_reskin ? unique_reskin : initial(icon_state)

CAPABILITIES(/obj/item/gun/energy/stunrevolver/detective)
	op("rename", menu(), label("Name Gun"), needs(carried()),
		asks(/datum/prompt/text, fields = list("question" = "What do you want to name the gun?", "title" = "Rename Gun", "max_len" = MAX_NAME_LEN, "encode" = FALSE, "name_text" = TRUE, "timeout" = 0), step = "name"),
		then(PROC_REF(det_stunrevolver_verb_rename)))
	op("reskin", menu(), label("Resprite gun"), needs(carried()),
		asks(/datum/prompt/choice, fields = list("question" = "Choose your sprite!", "title" = "Resprite Gun", "choices" = computed(PROC_REF(reskin_choices)), "timeout" = 0), step = "sprite"),
		then(PROC_REF(det_stunrevolver_verb_reskin)))

/// Old Name Gun verb: Rename your gun. If you're Security.
/obj/item/gun/energy/stunrevolver/detective/proc/det_stunrevolver_verb_rename(datum/act/op/A)
	var/mob/M = A.actor
	if(!security_naming_ok(M))
		to_chat(M, span_warning("You don\'t feel cool enough to name this gun, chump."))
		return OP_DECLINE
	if(!M.mind)
		return OP_DECLINE
	var/input = sanitizeSafe(A.step_value("name"))

	if(src && input && !M.stat && in_range(M,src))
		name = input
		to_chat(M, "You name the gun [input]. Say hello to your new friend.")
		return OP_OK
	return OP_DECLINE

/obj/item/gun/energy/stunrevolver/detective/reskin_options()
	var/list/options = list()
	options["Lawson Arms LAEP20"] = "stunrevolver"
	options["Lawson Arms LTX1020"] = "vinstunrevolver"
	options["Lawson Arms LTX1010"] = "snubstun2revolver"
	options["Lawson Arms LTX1020 (Blued)"] = "bluedstunrevolver"
	options["Lawson Arms LTX1020 (Stainless)"] = "stainstunrevolver"
	options["Lawson Arms LTX1020 (Ace)"] = "snubstunrevolver"
	options["Lawson Arms LTX1020 (Gold)"] = "goldstunrevolver"
	return options

/// Old Resprite gun verb: Click to choose a sprite for your gun.
/obj/item/gun/energy/stunrevolver/detective/proc/det_stunrevolver_verb_reskin(datum/act/op/A)
	var/mob/M = A.actor
	var/choice = A.step_value("sprite")
	var/list/options = reskin_options()
	if(src && choice && !M.stat && in_range(M,src))
		set_unique_reskin(options[choice])
		to_chat(M, "Your gun is now sprited as [choice]. Say hello to your new friend.")
		return OP_OK
	return OP_DECLINE

/*
 * Vintage Stun Revolver
 */
/obj/item/gun/energy/stunrevolver/vintage
	name = "vintage stun revolver"
	desc = "An older model stun revolver that is still in service across the frontier."
	icon_state = "vinstunrevolver"
	item_state = "stunrevolver"

CAPABILITIES(/obj/item/gun/energy/stunrevolver/vintage)
	configure(atom_rules(description_fluff = "The LTX1020 \"Bolter\", a Firefly Co. staple from when the company was in its hayday. \
	While Firefly Co. has sadly been dissmantled due to bankruptcy, their iconic weapons can still be found \
	across the frontier as anything from collectors items to surplus equipment. The LTX1020 falls under \
	the latter category. Several companies have been known to use the base tech within the Bolter to create \
	their own variants of the Stun Revolver."))

/*
 * Snubnose Stun Revolver
 */
/obj/item/gun/energy/stunrevolver/snubnose
	name = "snub stun revolver"
	desc = "A snub nose stun revolver sporting a rather elegant look."
	icon_state = "snubstunrevolver"
	item_state = "stunrevolver"
	w_class = ITEMSIZE_SMALL //small pistol is small

CAPABILITIES(/obj/item/gun/energy/stunrevolver/snubnose)
	configure(atom_rules(description_fluff = "The LTX1010 \"Stubby\", a Firefly Co. staple from when the company was in its hayday. \
	While Firefly Co. has sadly been dissmantled due to bankruptcy, their iconic weapons can still be found \
	across the frontier as anything from collectors items to surplus equipment. The LTX1010 falls under \
	the latter category. Gangsters and other gentlemanly criminals alike use the Stubby as a means of policing \
	within their ranks. Hard to argue with the boss with 12000 volts shooting through you."))
