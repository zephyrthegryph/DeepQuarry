/obj/machinery/photocopier
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "photocopier"
	desc = "Copy all your important papers here!"
	icon = 'icons/obj/library.dmi'
	icon_state = "photocopier"
	var/insert_anim = "photocopier_scan"
	anchored = TRUE
	density = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 30
	active_power_usage = 200
	power_channel = EQUIP
	circuit = /obj/item/circuitboard/photocopier
	can_buckle = TRUE
	var/obj/item/copyitem = null	//what's in the copier!
	var/copies = 1	//how many copies to print!
	var/toner = 30 //how much toner is left! woooooo~
	var/maxcopies = 10	//how many copies can be copied at once- idea shamelessly stolen from bs12's copier!
	var/copying = FALSE // Is the printer busy with something? Sanity check variable.

/obj/machinery/photocopier/examine(mob/user as mob)
	. = ..()
	if(Adjacent(user))
		. += "The screen shows there's [toner ? "[toner]" : "no"] toner left in the printer."

// The copier's window. An AI's photo print asks which of its pictures (asks()), when it has one to print.
CAPABILITIES(/obj/machinery/photocopier)
	interface("Photocopier")
	without("ui_open")
	op("make_copy", ui_act(), then(PROC_REF(ui_act_make_copy)))
	op("remove", ui_act("remove"), then(PROC_REF(ui_act_remove)))
	op("set_copies", ui_act("set_copies", arg("num_copies", num())), then(PROC_REF(ui_act_set_copies)))
	op("ai_photo", ui_act("ai_photo"), asks(/datum/prompt/choice, fields = list("question" = "Select image (numbered in order taken)", "title" = "Picture Choice", "choices" = computed(PROC_REF(album_names)), "timeout" = 0), step = "picture", when = PROC_REF(album_ready)),
		then(PROC_REF(ui_act_ai_photo)))
	op("use_crowbar", tool(TOOL_CROWBAR), priority(OP_PRIORITY_DEFAULT - 1), wait(0), then(PROC_REF(crowbar_used)))
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT - 1), wait(0), then(PROC_REF(wrench_used)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT - 1), wait(0), then(PROC_REF(screwdriver_used)))
	op("insert", inputs(item(/obj/item/paper), item(/obj/item/photo), item(/obj/item/paper_bundle)), priority(OP_PRIORITY_DEFAULT - 1), label("Insert"), then(PROC_REF(interaction_insert)))
	op("insert_toner", item(/obj/item/toner), priority(OP_PRIORITY_DEFAULT - 1), label("Insert toner"), then(PROC_REF(interaction_insert_toner)))
	op("swallow", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(TYPE_PROC_REF(/atom, op_swallow)))
	default_parts()

/// The window data.
/obj/machinery/photocopier/ui_data(datum/act/eval/A)
	var/list/data = ..()
	data["current_toner"] = toner
	data["num_copies"] = copies
	data["max_copies"] = maxcopies
	var/list/computed = ui_data_obj_machinery_photocopier(A.actor, null, null)
	for(var/key in computed)
		data[key] = computed[key]
	return data

/// The computed part of the window data (ui_data()).
/obj/machinery/photocopier/proc/ui_data_obj_machinery_photocopier(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["has_item"] = copyitem || has_buckled_mobs() // Ass copying
	data["isAI"] = issilicon(user)
	data["can_AI_print"] = (toner >= 5)
	data["has_toner"] =	!!toner
	data["max_toner"] = 40

	return data

/obj/machinery/photocopier/proc/ui_act_make_copy(datum/act/op/A)
	after(src, 0, PROC_REF(copy_operation), with = list(A.actor))
	return OP_OK

/obj/machinery/photocopier/proc/ui_act_remove(datum/act/op/A)
	var/mob/user = A.actor
	if(copyitem)
		copyitem.forceMove(user.loc)
		user.put_in_hands(copyitem)
		to_chat(user, span_notice("You take \the [copyitem] out of \the [src]."))
		own_take(src, nameof(copyitem))
	else if(has_buckled_mobs())
		to_chat(src?.buckled_mob_list()[1], span_notice("You feel a slight pressure on your ass.")) // It can't eject your asscheeks, but it'll try.
	return TRUE

/obj/machinery/photocopier/proc/ui_act_set_copies(datum/act/op/A, num_copies)
	copies = clamp(num_copies, 1, maxcopies)
	return TRUE

/// The camera album of the AI working the copier, or null (anyone else, or a silicon with no camera).
/obj/machinery/photocopier/proc/ai_album(datum/act/op/A)
	var/mob/living/silicon/tempAI = A.actor
	if(!istype(tempAI) || !tempAI.aiCamera)
		return null
	return tempAI.aiCamera.getsource(tempAI)

/// The AI's photo print asks for a picture when the copier can print one and the album has one.
/obj/machinery/photocopier/proc/album_ready(datum/act/op/A)
	var/mob/living/silicon/tempAI = A.actor
	return istype(tempAI) && toner >= 5 && length(tempAI.aiCamera?.aipictures) // ALLOW(reads): asked once, when the button is pressed, to decide whether its question opens

/obj/machinery/photocopier/proc/album_names(datum/act/op/A)
	. = list()
	var/obj/item/camera/siliconcam/source_cam = ai_album(A)
	for(var/obj/item/photo/photo in source_cam?.aipictures)
		. += photo.name

/obj/machinery/photocopier/proc/ui_act_ai_photo(datum/act/op/A)
	var/mob/living/silicon/tempAI = A.actor
	var/obj/item/camera/siliconcam/source_cam = ai_album(A)
	if(!source_cam || !operable() || toner < 5)
		return
	if(!length(source_cam.aipictures))
		to_chat(tempAI, span_userdanger("No images saved"))
		return
	var/picked = A.step_value("picture")
	var/obj/item/photo/selection
	for(var/obj/item/photo/photo in source_cam.aipictures)
		if(photo.name == picked)
			selection = photo
			break
	if(!selection)
		return
	var/obj/item/photo/p = photocopy(selection)
	if(p.desc == "")
		p.desc += "Copied by [tempAI.name]"
	else
		p.desc += " - Copied by [tempAI.name]"
	toner -= 5
	return TRUE

/// Makes `copies` copies, one after another (each a few steps on the machine's timers).
/obj/machinery/photocopier/proc/copy_operation(mob/user)
	if(copying)
		return FALSE
	copying = TRUE
	copy_next(user, copies)

/// Starts the next copy, `left` to go.
/obj/machinery/photocopier/proc/copy_next(mob/user, left)
	if(left <= 0 || toner <= 0)
		copying = FALSE
		return
	if (istype(copyitem, /obj/item/paper) || istype(copyitem, /obj/item/photo))
		playsound(src, "sound/machines/copier.ogg", 100, 1)
		after(src, 1.1 SECONDS, PROC_REF(copy_print), with = list(user, left, copyitem.type))
	else if (istype(copyitem, /obj/item/paper_bundle))
		after(src, 1.1 SECONDS, PROC_REF(copy_print), with = list(user, left, copyitem.type))
	else if (has_buckled_mobs()) // EDIT: For ass-copying.
		playsound(src, "sound/machines/copier.ogg", 100, 1)
		audible_message(span_notice("You can hear [src] whirring as it attempts to scan."), runemessage = "whirr")
		// Sit with your bare ass on the copier for a random time, feel like a fool, get stared at.
		after(src, rand(2 SECONDS,4.5 SECONDS), PROC_REF(copy_ass_scan), with = list(user, left))
	else
		to_chat(user, span_warning("\The [copyitem] can't be copied by [src]."))
		playsound(src, "sound/machines/buzz-two.ogg", 100)
		copying = FALSE

/obj/machinery/photocopier/proc/copy_print(mob/user, left, copy_type)
	if(!copyitem || copyitem.type != copy_type) // removed/swapped during the wait
		copying = FALSE
		return
	var/finish_delay = 0
	if (istype(copyitem, /obj/item/paper))
		copy(copyitem)
	else if (istype(copyitem, /obj/item/photo))
		photocopy(copyitem)
	else
		playsound(src, "sound/machines/copier.ogg", 100, 1)
		var/obj/item/paper_bundle/B = bundlecopy(copyitem)
		finish_delay = 1.1 SECONDS * length(B?.pages)
	after(src, finish_delay, PROC_REF(copy_finished), with = list(user, left))

/obj/machinery/photocopier/proc/copy_ass_scan(mob/user, left)
	copyass(user)
	after(src, 1.5 SECONDS, PROC_REF(copy_finished), with = list(user, left))

/obj/machinery/photocopier/proc/copy_finished(mob/user, left)
	audible_message(span_notice("You can hear [src] whirring as it finishes printing."), runemessage = "whirr")
	playsound(src, "sound/machines/buzzbeep.ogg", 30)
	use_power(active_power_usage)
	copy_next(user, left - 1)

/obj/machinery/photocopier/proc/interaction_insert(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if(!copyitem)
		if(!move_into(src, nameof(src.copyitem), O, user))
			return OP_OK
		to_chat(user, span_notice("You insert \the [O] into \the [src]."))
		playsound(src, "sound/machines/click.ogg", 100, 1)
		flick(insert_anim, src)
	else
		to_chat(user, span_notice("There is already something in \the [src]."))
	return OP_OK

/obj/machinery/photocopier/proc/interaction_insert_toner(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/toner/O = A.held
	if(toner <= 10) //allow replacing when low toner is affecting the print darkness
		var/refill_amount = O.toner_amount
		if(!consume(O, user))
			return OP_OK
		to_chat(user, span_notice("You insert the toner cartridge into \the [src]."))
		flick("photocopier_toner", src)
		play_sfx(loc, SFX_MACHINES_CLICK)
		toner += refill_amount
	else
		to_chat(user, span_notice("This cartridge is not yet ready for replacement! Use up the rest of the toner."))
		flick("photocopier_notoner", src)
		play_sfx(loc, SFX_MACHINES_BUZZ_TWO, 1.5, vary = TRUE)
	return OP_OK

/obj/machinery/photocopier/proc/screwdriver_used(datum/act/op/A)
	return OP_DECLINE

/obj/machinery/photocopier/proc/crowbar_used(datum/act/op/A)
	return OP_DECLINE

/obj/machinery/photocopier/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	playsound(src, tool.usesound, 50, TRUE)
	set_anchored(!anchored)
	to_chat(user, span_notice("You [anchored ? "wrench" : "unwrench"] \the [src]."))
	return OP_OK

DAMAGE_REACTION(/obj/machinery/photocopier, DAMAGE_EXPLOSION, PROC_REF(photocopier_blast_spill))

/// A blast can burst the toner out onto the floor.
/obj/machinery/photocopier/proc/photocopier_blast_spill(datum/damage_packet/packet)
	if(packet.severity >= 2 && prob(50) && toner > 0)
		new /obj/effect/decal/cleanable/blood/oil(get_turf(src))
		toner = 0

/obj/machinery/photocopier/proc/copy(obj/item/paper/copy, need_toner=1)
	var/obj/item/paper/c = new /obj/item/paper (loc)
	if(toner > 10)	//lots of toner, make it dark
		c.info = "<font color = #101010>"
	else			//no toner? shitty copies for you!
		c.info = "<font color = #808080>"
	var/copied = html_decode(copy.info)
	copied = replacetext(copied, "<font face=\"[c.deffont]\" color=", "<font face=\"[c.deffont]\" nocolor=")	//state of the art techniques in action
	copied = replacetext(copied, "<font face=\"[c.crayonfont]\" color=", "<font face=\"[c.crayonfont]\" nocolor=")	//This basically just breaks the existing color tag, which we need to do because the innermost tag takes priority.
	c.info += copied
	c.info += "</font>"//</font>
	c.name = copy.name // -- Doohl
	c.fields = copy.fields
	c.stamps = copy.stamps
	c.stamped = copy.stamped
	c.ico = copy.ico
	c.offset_x = copy.offset_x
	c.offset_y = copy.offset_y
	var/evidence_id = copy.medical_scan_evidence?["evidence_id"]
	if(evidence_id)
		c.attach_contract_evidence(evidence_id)
	var/list/temp_overlays = copy.overlays       //Iterates through stamps
	var/image/img                                //and puts a matching
	for (var/j = 1, j <= min(temp_overlays.len, length(copy.ico)), j++) //gray overlay onto the copy
		if (findtext(LAZYACCESS(copy.ico, j), "cap") || findtext(LAZYACCESS(copy.ico, j), "cent"))
			img = image('icons/obj/bureaucracy.dmi', "paper_stamp-circle")
		else if (findtext(LAZYACCESS(copy.ico, j), "tal"))
			img = image('icons/obj/bureaucracy.dmi', "paper_stamp-square")
		else if (findtext(LAZYACCESS(copy.ico, j), "deny"))
			img = image('icons/obj/bureaucracy.dmi', "paper_stamp-x")
		else
			img = image('icons/obj/bureaucracy.dmi', "paper_stamp-dots")
		img.pixel_x = copy.offset_x[j]
		img.pixel_y = copy.offset_y[j]
		c.add_overlay(img)
	c.updateinfolinks()
	if(need_toner)
		toner--
	if(toner == 0)
		playsound(src, "sound/machines/buzz-sigh.ogg", 100)
		visible_message(span_notice("A [span_red("red")] light on \the [src] flashes, indicating that it is out of toner."))
	return c

/obj/machinery/photocopier/proc/photocopy(obj/item/photo/photocopy, need_toner=1)
	var/obj/item/photo/p = photocopy.copy()
	p.forceMove(src.loc)

	var/icon/I = icon(photocopy.icon, photocopy.icon_state)
	if(toner > 10)	//plenty of toner, go straight greyscale
		I.MapColors(rgb(77,77,77), rgb(150,150,150), rgb(28,28,28), rgb(0,0,0))		//I'm not sure how expensive this is, but given the many limitations of photocopying, it shouldn't be an issue.
		p.img.MapColors(rgb(77,77,77), rgb(150,150,150), rgb(28,28,28), rgb(0,0,0))
		p.tiny.MapColors(rgb(77,77,77), rgb(150,150,150), rgb(28,28,28), rgb(0,0,0))
	else			//not much toner left, lighten the photo
		I.MapColors(rgb(77,77,77), rgb(150,150,150), rgb(28,28,28), rgb(100,100,100))
		p.img.MapColors(rgb(77,77,77), rgb(150,150,150), rgb(28,28,28), rgb(100,100,100))
		p.tiny.MapColors(rgb(77,77,77), rgb(150,150,150), rgb(28,28,28), rgb(100,100,100))
	p.icon = I
	if(need_toner)
		toner -= 5	//photos use a lot of ink!
	if(toner < 0)
		toner = 0
		playsound(src, "sound/machines/buzz-sigh.ogg", 100)
		visible_message(span_notice("A red light on \the [src] flashes, indicating that it is out of toner."))

	return p

/obj/machinery/photocopier/proc/copyass(mob/user)
	var/icon/temp_img
	if(!has_buckled_mobs()) // Are there no mobs src?.buckled_to() to the photocopier?
		return
	var/mob/sitter = src?.buckled_mob_list()[1] // You have to be sitting on the copier/BUCKLED(src) to it and either be a xeno or a human without clothes on that cover your ass.
	if(ishuman(sitter)) // Suit checks are in can_buckle_mobs at the bottom of the file.
		var/mob/living/carbon/human/H = sitter // All human subtypes.
		var/species_to_check = H.get_species()
		if(species_to_check == SPECIES_CUSTOM || species_to_check == SPECIES_XENOCHIMERA) // Are we a custom species, or Xenochimera? If so, what is the base icon sprite for our species?
			species_to_check = H.species.base_species // Grab the base species and use that as the 'species' for the purpose of printing off your asscheeks.
		switch(species_to_check)
			if(SPECIES_HUMAN)
				temp_img = icon('icons/obj/butts_vr.dmi', "human")
			if(SPECIES_TAJARAN)
				temp_img = icon('icons/obj/butts_vr.dmi', "tajaran")
			if(SPECIES_UNATHI)
				temp_img = icon('icons/obj/butts_vr.dmi', "unathi")
			if(SPECIES_SKRELL)
				temp_img = icon('icons/obj/butts_vr.dmi', "skrell")
			if(SPECIES_VOX)
				temp_img = icon('icons/obj/butts_vr.dmi', "vox")
			if(SPECIES_DIONA)
				temp_img = icon('icons/obj/butts_vr.dmi', "diona")
			if(SPECIES_PROMETHEAN)
				temp_img = icon('icons/obj/butts_vr.dmi', "slime")
			if(SPECIES_VULPKANIN)
				temp_img = icon('icons/obj/butts_vr.dmi', "vulp")
			if(SPECIES_PROTEAN)
				temp_img = icon('icons/obj/butts_vr.dmi', "machine")
			if(SPECIES_WEREBEAST)
				temp_img = icon('icons/obj/butts_vr.dmi', "vulp") // Give Werewolves their own thicc'er than a boal of oatmeal ass sprite someday?
			if(SPECIES_XENOHYBRID, SPECIES_XENO, SPECIES_XENO_DRONE, SPECIES_XENO_HUNTER, SPECIES_XENO_QUEEN, SPECIES_XENO_SENTINEL) // Xenos + Xenohybrids have their own asses, thanks to Pybro.
				temp_img = icon('icons/obj/butts_vr.dmi', "xeno")
			if(SPECIES_ZORREN_HIGH)
				temp_img = icon('icons/obj/butts_vr.dmi', "vulp") // placeholder until we get zorren butts.
			if(SPECIES_FENNEC)
				temp_img = icon('icons/obj/butts_vr.dmi', "vulp") // placeholder until we get fennec butts.
			if(SPECIES_AKULA)
				temp_img = icon('icons/obj/butts_vr.dmi', "xeno") // placeholder until we get proper sharkbutt. AKULA BE THICC ASS SHARKS MMMMMMMMMMMMMMKAY?
			// Butts by Meek the stoat!
			if(SPECIES_TESHARI)
				temp_img = icon('icons/obj/butts_vr.dmi', "tesh")
			if(SPECIES_SERGAL)
				temp_img = icon('icons/obj/butts_vr.dmi', "sergal")
			if(SPECIES_NEVREAN)
				temp_img = icon('icons/obj/butts_vr.dmi', "tesh") // kinda close! but should have it's own someday
			if(SPECIES_ALTEVIAN)
				temp_img = icon('icons/obj/butts_vr.dmi', "altevian")
			else // Sanity/Safety check - does their species not show up or not work, or did something fail, but they're DEFINITELY a /human/ subtype? Print the 'default' ass.
				temp_img = icon('icons/obj/butts_vr.dmi', "human")
	else if(istype(sitter,/mob/living/silicon/robot/drone)) // Are we a drone?
		temp_img = icon('icons/obj/butts_vr.dmi', "drone")
	else if(istype(sitter,/mob/living/carbon/alien/diona)) // Are we a nymph, instead of a full-grown Diona?
		temp_img = icon('icons/obj/butts_vr.dmi', "nymph")
	else
		return
	var/obj/item/photo/p = new /obj/item/photo (loc)
	p.desc = "You see [sitter]'s ass on the photo."
	p.pixel_x = rand(-10, 10)
	p.pixel_y = rand(-10, 10)
	p.img = temp_img
	p.drop_sound = 'sound/items/drop/paper.ogg'
	var/icon/small_img = icon(temp_img) // Icon() is needed or else temp_img will be rescaled too >.>
	var/icon/ic = icon('icons/obj/items.dmi',"photo")
	small_img.Scale(8, 8)
	ic.Blend(small_img,ICON_OVERLAY, 10, 13)
	p.icon = ic
	toner -= 10 // PHOTOCOPYING YOUR ASS IS EXPENSIVE (And so you can't just spam it a bunch).
	if(toner < 0)
		toner = 0
		playsound(src, "sound/machines/buzz-sigh.ogg", 100)
		visible_message(span_notice("A red light on \the [src] flashes, indicating that it is out of toner."))
	return p

// Stop

//If need_toner is 0, the copies will still be lightened when low on toner, however it will not be prevented from printing. TODO: Implement print queues for fax machines and get rid of need_toner
/obj/machinery/photocopier/proc/bundlecopy(obj/item/paper_bundle/bundle, need_toner=1)
	var/obj/item/paper_bundle/p = new /obj/item/paper_bundle (src)
	for(var/obj/item/W in bundle.pages)
		if(toner <= 0 && need_toner)
			toner = 0
			playsound(src, "sound/machines/buzz-sigh.ogg", 100)
			visible_message(span_notice("A red light on \the [src] flashes, indicating that it is out of toner."))
			break

		if(istype(W, /obj/item/paper))
			W = copy(W)
		else if(istype(W, /obj/item/photo))
			W = photocopy(W)
		W.forceMove(p)
		rel_add(p, nameof(p.pages), W)

	p.forceMove(src.loc)
	p.update_icon()
	p.icon_state = "paper_words"
	p.name = bundle.name
	p.pixel_y = rand(-8, 8)
	p.pixel_x = rand(-9, 9)
	return p

// Rykka

/obj/machinery/photocopier/can_buckle_check(mob/living/M, forced = FALSE)
	if(!..())
		return FALSE
	for(var/obj/item/clothing/C in contents_of(M))
		if(M.item_is_in_hands(C))
			continue
		if((C.body_parts_covered & LOWER_TORSO) && !istype(C,/obj/item/clothing/under/permit))
			to_chat(M, span_warning("One needs to not be wearing pants to photocopy one's ass..."))
			return FALSE
	return TRUE

// Stop - Rykka

/obj/item/toner
	name = "toner cartridge"
	icon = 'icons/obj/device.dmi'
	icon_state = "tonercartridge"
	var/toner_amount = 30
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

/obj/machinery/photocopier/ownership()
	. = ..()
	. += owns(nameof(copyitem), policy = OWN_CONTAINED)
