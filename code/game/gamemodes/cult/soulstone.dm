/////////////////////////
//		Soulstone
/////////////////////////

/obj/item/soulstone
	name = "Soul Stone Shard"
	icon = 'icons/obj/wizard.dmi'
	icon_state = "soulstone"
	item_state = "electronic"
	desc = "A fragment of the legendary treasure known simply as the 'Soul Stone'. The shard still flickers with a fraction of the full artefacts power."
	w_class = ITEMSIZE_SMALL
	slot_flags = SLOT_BELT
	var/imprinted = "empty"
	var/possible_constructs = list("Juggernaut","Wraith","Artificer","Harvester")

/obj/item/soulstone/cultify()
	return

//////////////////////////////Capturing////////////////////////////////////////////////////////

/obj/item/soulstone/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!ishuman(M))//If target is not a human.
		return ..()
	if(istype(M, /mob/living/carbon/human/dummy))
		return ..()
	if(jobban_isbanned(M, JOB_CULTIST))
		to_chat(user, span_warning("This person's soul is too corrupt and cannot be captured!"))
		return ..()

	if(M.has_brain_worms()) //Borer stuff - RR
		to_chat(user, span_warning("This being is corrupted by an alien intelligence and cannot be soul trapped."))
		return ..()

	add_attack_logs(user,M,"Soulstone'd with [src.name]")
	transfer_soul("VICTIM", M, user)
	return ITEM_INTERACT_SUCCESS


///////////////////Options for using captured souls///////////////////////////////////////

// TGUI migration. attack_self opens Soulstone.tsx; Topic
// "Summon" handler moves to tgui_act.
CAPABILITIES(/obj/item/soulstone)
	op("self", in_hand(), then(PROC_REF(interaction_self)))
	interface("Soulstone", title = "Soul Stone")
	without("ui_open")
	op("summon", ui_act("summon"), then(PROC_REF(ui_act_summon)))

/// Old attack_self.
/obj/item/soulstone/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(!in_range(src, user))
		return TRUE
	tgui_interact(user)
	return TRUE

/obj/item/soulstone/ui_data(datum/act/eval/A)
	var/list/data = list()
	var/list/merged_1 = ui_data_obj_item_soulstone(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/soulstone's window data.
/obj/item/soulstone/proc/ui_data_obj_item_soulstone(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	var/mob/living/simple_mob/construct/shade/A = locate_within(src, /mob/living/simple_mob/construct/shade)
	data["has_shade"] = !!A
	data["shade_name"] = A ? A.name : ""
	return data

/obj/item/soulstone/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(!in_range(src, user))
		return FALSE
	add_fingerprint(user)
	return TRUE

/obj/item/soulstone/proc/ui_act_summon(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	for(var/mob/living/simple_mob/construct/shade/A2 in contents_of(src))
		A2.disable_godmode()
		A2.canmove = 1
		to_chat(A2, span_infoplain(span_bold("You have been released from your prison, but you are still bound to [user.name]'s will. Help them suceed in their goals at all costs.")))
		A2.forceMove(user.loc)
		A2.cancel_camera()
		icon_state = "soulstone"
	return TRUE

///////////////////////////Transferring to constructs/////////////////////////////////////////////////////
/obj/structure/constructshell
	name = "empty shell"
	icon = 'icons/obj/wizard.dmi'
	icon_state = "construct"
	desc = "A wicked machine used by those skilled in magical arts. It is inactive."

/obj/structure/constructshell/cultify()
	return

/obj/structure/constructshell/cult
	icon_state = "construct-cult"
	desc = "This eerie contraption looks like it would come alive if supplied with a missing ingredient."

CAPABILITIES(/obj/structure/constructshell)
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attackby.
/obj/structure/constructshell/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if(istype(O, /obj/item/soulstone))
		var/obj/item/soulstone/S = O;
		S.transfer_soul("CONSTRUCT",src,user)
	return OP_PASS


////////////////////////////Proc for moving soul in and out off stone//////////////////////////////////////
/obj/item/soulstone/proc/transfer_human(mob/living/carbon/human/T,mob/U)
	if(!istype(T))
		return;
	if(src.imprinted != "empty")
		to_chat(U, span_danger("Capture failed!") + ": The soul stone has already been imprinted with [src.imprinted]'s mind!")
		return
	if (!T.is_critical() && T.stat != DEAD)
		to_chat(U, span_danger("Capture failed!") + ": Kill or maim the victim first!")
		return
	if(T.client == null)
		to_chat(U, span_danger("Capture failed!") + ": The soul has already fled it's mortal frame.")
		return
	if(contents_count(src))
		to_chat(U, span_danger("Capture failed!") + ": The soul stone is full! Use or free an existing soul to make room.")
		return

	for(var/obj/item/W in contents_of(T))
		T.drop_from_inventory(W)

	new /obj/effect/decal/remains/human(T.loc) //Spawns a skeleton
	T.invisibility = INVISIBILITY_ABSTRACT

	var/atom/movable/overlay/animation = new /atom/movable/overlay( T.loc )
	animation.icon_state = "blank"
	animation.icon = 'icons/mob/mob.dmi'
	rel_set(animation, nameof(animation.master), T)
	flick("dust-h", animation)
	lapsed(animation)

	var/mob/living/simple_mob/construct/shade/S = new /mob/living/simple_mob/construct/shade( T.loc )
	S.forceMove(src) //put shade in stone
	S.enable_godmode()
	S.canmove = 0//Can't move out of the soul stone
	S.name = "Shade of [T.real_name]"
	S.real_name = "Shade of [T.real_name]"
	S.icon = T.icon
	S.icon_state = T.icon_state
	S.overlays = T.overlays
	S.color = rgb(254,0,0)
	S.alpha = 127
	if (T.client)
		T.client.mob = S
	S.cancel_camera()


	src.icon_state = "soulstone2"
	src.name = "Soul Stone: [S.real_name]"
	to_chat(S, "Your soul has been captured! You are now bound to [U.name]'s will, help them suceed in their goals at all costs.")
	to_chat(U, span_notice("Capture successful!") + ": [T.real_name]'s soul has been ripped from their body and stored within the soul stone.")
	to_chat(U, "The soulstone has been imprinted with [S.real_name]'s mind, it will no longer react to other souls.")
	src.imprinted = "[S.name]"
	consumed(T, src)

/obj/item/soulstone/proc/transfer_shade(mob/living/simple_mob/construct/shade/T,mob/U)
	if(!istype(T))
		return;
	if (T.stat == DEAD)
		to_chat(U, span_danger("Capture failed!") + ": The shade has already been banished!")
		return
	if(contents_count(src))
		to_chat(U, span_danger("Capture failed!") + ": The soul stone is full! Use or free an existing soul to make room.")
		return
	if(T.name != src.imprinted)
		to_chat(U, span_danger("Capture failed!") + ": The soul stone has already been imprinted with [src.imprinted]'s mind!")
		return

	T.forceMove(src) //put shade in stone
	T.enable_godmode()
	T.canmove = 0
	T.fully_heal()
	src.icon_state = "soulstone2"

	to_chat(T, "Your soul has been recaptured by the soul stone, its arcane energies are reknitting your ethereal form")
	to_chat(U, span_notice("Capture successful!") + ": [T.name]'s has been recaptured and stored within the soul stone.")

/obj/item/soulstone/proc/transfer_construct(obj/structure/constructshell/T,mob/U)
	var/mob/living/simple_mob/construct/shade/A = locate_within(src, /mob/living/simple_mob/construct/shade)
	if(!A)
		to_chat(U, span_danger("Capture failed!") + ": The soul stone is empty! Go kill someone!")
		return;
	open_request(src, /datum/prompt/choice, PROC_REF(construct_type_chosen), answerer = U, choices = possible_constructs, subject = T, title = "Construct Type", question = "Please choose which type of construct you wish to create.", ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, timeout = 0)

/obj/item/soulstone/proc/construct_type_chosen(datum/act/request/A)
	if(!A.answer)
		return
	return apply_construct_type_chosen(A)

/obj/item/soulstone/proc/apply_construct_type_chosen(datum/act/request/answer)
	var/datum/request/ask = answer.request
	var/mob/U = ask.answerer
	var/construct_class = answer.answer.value
	var/obj/structure/constructshell/T = ask.subject
	var/mob/living/simple_mob/construct/shade/A = locate_within(src, /mob/living/simple_mob/construct/shade)
	if(!A)
		return
	switch(construct_class)
		if("Juggernaut")
			var/mob/living/simple_mob/construct/juggernaut/Z = new /mob/living/simple_mob/construct/juggernaut (get_turf(T.loc))
			move_player(A, Z, "shade bound into [Z]")
			if(iscultist(U))
				GLOB.cult.add_antagonist(Z.mind)
			replaced_by(T, Z)
			to_chat(Z, span_infoplain(span_bold("You are playing a Juggernaut. Though slow, you can withstand extreme punishment, and rip apart enemies and walls alike.")))
			to_chat(Z, span_infoplain(span_bold("You are still bound to serve your creator, follow their orders and help them complete their goals at all costs.")))
			Z.cancel_camera()
			consume(src, U)
		if("Wraith")
			var/mob/living/simple_mob/construct/wraith/Z = new /mob/living/simple_mob/construct/wraith (get_turf(T.loc))
			move_player(A, Z, "shade bound into [Z]")
			if(iscultist(U))
				GLOB.cult.add_antagonist(Z.mind)
			replaced_by(T, Z)
			to_chat(Z, span_infoplain(span_bold("You are playing a Wraith. Though relatively fragile, you are fast, deadly, and even able to phase through walls.")))
			to_chat(Z, span_infoplain(span_bold("You are still bound to serve your creator, follow their orders and help them complete their goals at all costs.")))
			Z.cancel_camera()
			consume(src, U)
		if("Artificer")
			var/mob/living/simple_mob/construct/artificer/Z = new /mob/living/simple_mob/construct/artificer (get_turf(T.loc))
			move_player(A, Z, "shade bound into [Z]")
			if(iscultist(U))
				GLOB.cult.add_antagonist(Z.mind)
			replaced_by(T, Z)
			to_chat(Z, span_infoplain(span_bold("You are playing an Artificer. You are incredibly weak and fragile, but you are able to construct fortifications, repair allied constructs (by clicking on them), and even create new constructs")))
			to_chat(Z, span_infoplain(span_bold("You are still bound to serve your creator, follow their orders and help them complete their goals at all costs.")))
			Z.cancel_camera()
			consume(src, U)
		if("Harvester")
			var/mob/living/simple_mob/construct/harvester/Z = new /mob/living/simple_mob/construct/harvester (get_turf(T.loc))
			move_player(A, Z, "shade bound into [Z]")
			if(iscultist(U))
				GLOB.cult.add_antagonist(Z.mind)
			replaced_by(T, Z)
			to_chat(Z, span_infoplain(span_bold("You are playing a Harvester. You are relatively weak, but your physical frailty is made up for by your ranged abilities.")))
			to_chat(Z, span_infoplain(span_bold("You are still bound to serve your creator, follow their orders and help them complete their goals at all costs.")))
			Z.cancel_camera()
			consume(src, U)
		if("Behemoth")
			var/mob/living/simple_mob/construct/juggernaut/behemoth/Z = new /mob/living/simple_mob/construct/juggernaut/behemoth (get_turf(T.loc))
			move_player(A, Z, "shade bound into [Z]")
			if(iscultist(U))
				GLOB.cult.add_antagonist(Z.mind)
			replaced_by(T, Z)
			to_chat(Z, span_infoplain(span_bold("You are playing a Behemoth. You are incredibly slow, though your slowness is made up for by the fact your shell is far larger than any of your bretheren. You are the Unstoppable Force, and Immovable Object.")))
			to_chat(Z, span_infoplain(span_bold("You are still bound to serve your creator, follow their orders and help them complete their goals at all costs.")))
			Z.cancel_camera()
			consume(src, U)

/obj/item/soulstone/proc/transfer_soul(choice as text, target, mob/U as mob)
	switch(choice)
		if("VICTIM")
			transfer_human(target,U)
		if("SHADE")
			transfer_shade(target,U)
		if("CONSTRUCT")
			transfer_construct(target,U)
