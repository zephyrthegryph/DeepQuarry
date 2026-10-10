/obj/structure/noticeboard
	name = "notice board"
	desc = "A board for pinning important notices upon."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "nboard00"
	layer = ABOVE_WINDOW_LAYER
	density = FALSE
	anchored = TRUE
	flags = WALL_ITEM
	var/list/notices
	var/base_icon_state = "nboard0"
	var/const/max_notices = 5

CAPABILITIES(/obj/structure/noticeboard)
	owns_many(nameof(notices))
	interface("NoticeBoard")
	without("ui_open")
	op("read", ui_act("read", arg("ref", schema_ref(/obj/item/paper))), then(PROC_REF(ui_act_read)))
	op("look", ui_act("look", arg("ref", schema_ref(/obj/item/photo))), then(PROC_REF(ui_act_look)))
	op("remove", ui_act("remove", arg("ref", schema_ref(/obj/item))), then(PROC_REF(ui_act_remove)))
	op("write", ui_act("write", arg("ref", schema_ref(/obj/item))), then(PROC_REF(ui_act_write)))
	op("hand", hand(), ungated(), label("Use"), then(PROC_REF(interaction_hand)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	op("noticeboard_silicon_examine", remote(), label("Examine"), then(PROC_REF(noticeboard_silicon_examine)))
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(noticeboard_blast_dismantle))))

// ALLOW(init/INSTANCE_STATE): takes the notices the map placed on its tile
/obj/structure/noticeboard/Initialize(mapload)
	. = ..()

	// Grab any mapped notices.
	rel_take_all(src, nameof(notices))
	for(var/obj/item/paper/note in get_turf(src))
		move_into(src, nameof(src.notices), note)
		if(LAZYLEN(notices) >= max_notices)
			break
	// notices in contents
	for(var/obj/item/paper/note in contents)
		rel_add(src, nameof(notices), note)
		if(LAZYLEN(notices) >= max_notices)
			break


/obj/structure/noticeboard/proc/add_paper(atom/movable/paper, skip_icon_update)
	if(istype(paper))
		paper.forceMove(src)
		own_move(paper, src, nameof(notices)) // it may come from another holder (a bundle, a clipboard)

/obj/structure/noticeboard/proc/remove_paper(atom/movable/paper, skip_icon_update)
	if(istype(paper) && paper.loc == src)
		paper.dropInto(loc)
		own_take_member(src, nameof(notices), paper)
		SSpersistence.forget_value(paper, /datum/persistent/paper)

/obj/structure/noticeboard/proc/dismantle()
	for(var/thing in notices)
		remove_paper(thing, skip_icon_update = TRUE)
	replace_with(src, /obj/item/stack/material/wood)



/// Any blast knocks the board down into its parts.
/obj/structure/noticeboard/proc/noticeboard_blast_dismantle(datum/act/hit/explosion/A)
	dismantle()
	return OP_OK

/obj/structure/noticeboard/proc/appearance_count()
	return LAZYLEN(notices)

/// The look (the draw sweep: from its template).
/obj/structure/noticeboard/draw(datum/look/look)
	..()
	look.state("[base_icon_state][appearance_count()]")

/// Old attackby.
/obj/structure/noticeboard/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/paper) || istype(I, /obj/item/photo))
		if(jobban_isbanned(user, JOB_GRAFFITI))
			to_chat(user, span_warning("You are banned from leaving persistent information across rounds."))
		else
			if(LAZYLEN(notices) < max_notices && user.unEquip(I, src))
				add_fingerprint(user)
				add_paper(I)
				to_chat(user, span_notice("You pin [I] to [src]."))
				SSpersistence.track_value(I, /datum/persistent/paper)
			else
				to_chat(user, span_warning("You hesitate, certain [I] will not be seen among the many others already attached to \the [src]."))
		return OP_PASS
	return OP_DECLINE

/obj/structure/noticeboard/screwdriver_act(mob/user, obj/item/tool)
	open_request(src, /datum/prompt/choice/noticeboard_offset, PROC_REF(noticeboard_offset_chosen), answerer = user, subject = tool)
	return ITEM_INTERACT_BLOCKING

/datum/prompt/choice/noticeboard_offset
	title = "Noticeboard Offset"
	question = "Which direction do you wish to place the noticeboard?"
	choices = list("North", "South", "East", "West", "No Offset")
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/noticeboard_offset/recheck_extra()
	. = ..()
	if(.)
		return
	var/obj/structure/noticeboard/board = owner
	var/obj/item/tool = subject
	if(!istype(board) || QDELETED(board) || QDELETED(answerer) || !istype(tool) || QDELETED(tool))
		return "The board, user or tool is no longer available."
	if(!isnull(value) && (!value || !board.Adjacent(answerer) || tool.loc != answerer || answerer.incapacitated()))
		return "The noticeboard cannot be adjusted now."

/obj/structure/noticeboard/proc/noticeboard_offset_chosen(datum/act/request/A)
	var/mob/user = A.request.answerer
	var/obj/item/tool = A.request.subject
	if(!A.answer)
		if(!QDELETED(user) && !QDELETED(tool) && !isnull(A.request.value))
			SStgui.update_uis(src)
		return
	apply_noticeboard_offset(A.answer.value, tool)
	SStgui.update_uis(src)

/obj/structure/noticeboard/proc/apply_noticeboard_offset(choice, obj/item/tool)
	playsound(loc, tool.usesound, 50, TRUE)
	switch(choice)
		if("North")
			pixel_x = 0
			pixel_y = 32
		if("South")
			pixel_x = 0
			pixel_y = -32
		if("East")
			pixel_x = 32
			pixel_y = 0
		if("West")
			pixel_x = -32
			pixel_y = 0
		if("No Offset")
			pixel_x = 0
			pixel_y = 0
	return ITEM_INTERACT_SUCCESS

/obj/structure/noticeboard/wrench_act(mob/user, obj/item/tool)
	use_tool(user, tool, src, delay = 5 SECONDS, volume = 50, start_others = "[user] begins dismantling [src].", receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
	return ITEM_INTERACT_SUCCESS

/obj/structure/noticeboard/proc/wrench_act_tool_done(mob/user)
	act_message(user, src, others = span_danger("%U% has dismantled %T%!"))
	dismantle()
	return ITEM_INTERACT_SUCCESS

/// Old attack_ai: look at the board.
/obj/structure/noticeboard/proc/noticeboard_silicon_examine(datum/act/op/A)
	var/mob/user = A.actor
	examine(user)
	return TRUE

/// Old attack_hand.
/obj/structure/noticeboard/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	examine(user)
	return TRUE

/obj/structure/noticeboard/examine(mob/user)
	tgui_interact(user)
	return ..()

/// /obj/structure/noticeboard's window data.
/obj/structure/noticeboard/ui_data(datum/act/eval/A)
	var/list/data = list()

	var/list/tgui_notices = list()
	for(var/obj/item/I in src.notices)
		tgui_notices.Add(list(list(
			"ispaper" = istype(I, /obj/item/paper),
			"isphoto" = istype(I, /obj/item/photo),
			"name" = I.name,
			"ref" = "\ref[I]",
		)))
	data["notices"] = tgui_notices
	return data

/obj/structure/noticeboard/proc/ui_act_read(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(isnull(ref))
		return FALSE
	var/obj/item/paper/P = ref
	if(P && P.loc == src)
		P.show_content(user)
	. = TRUE

/obj/structure/noticeboard/proc/ui_act_look(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(isnull(ref))
		return FALSE
	var/obj/item/photo/P = ref
	if(P && P.loc == src)
		P.show(user)
	. = TRUE

/obj/structure/noticeboard/proc/ui_act_remove(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!in_range(src, user))
		return FALSE
	var/obj/item/I = ref
	remove_paper(I)
	if(istype(I))
		user.put_in_hands(I)
	add_fingerprint(user)
	. = TRUE

/obj/structure/noticeboard/proc/ui_act_write(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(isnull(ref))
		return FALSE
	if(!in_range(src, user))
		return FALSE
	var/obj/item/P = ref
	if((P && P.loc == src)) //if the paper's on the board
		var/mob/living/M = user
		if(istype(M))
			var/obj/item/pen/E = M.get_type_in_hands(/obj/item/pen)
			if(E)
				add_fingerprint(M)
				P.attackby(E, user)
			else
				to_chat(M, span_notice("You'll need something to write with!"))
				. = TRUE

/obj/structure/noticeboard/anomaly
	notices = 5
	icon_state = "nboard05"

/obj/structure/noticeboard/anomaly/Initialize(mapload)
	. = ..()
	var/obj/item/paper/P = new()
	P.name = "Memo RE: proper analysis procedure"
	P.set_info("<br>We keep test dummies in pens here for a reason, so standard procedure should be to activate newfound alien artifacts and place the two in close proximity. Promising items I might even approve monkey testing on.")
	P.stamped = list(/obj/item/stamp/rd)
	P.add_stamp_mark("paper_stamped_rd", 0, 0)
	P.forceMove(src)

	P = new()
	P.name = "Memo RE: materials gathering"
	P.set_info("Corasang,<br>the hands-on approach to gathering our samples may very well be slow at times, but it's safer than allowing the blundering miners to roll willy-nilly over our dig sites in their mechs, destroying everything in the process. And don't forget the escavation tools on your way out there!<br>- R.W")
	P.stamped = list(/obj/item/stamp/rd)
	P.add_stamp_mark("paper_stamped_rd", 0, 0)
	P.forceMove(src)

	P = new()
	P.name = "Memo RE: ethical quandaries"
	P.set_info("Darion-<br><br>I don't care what his rank is, our business is that of science and knowledge - questions of moral application do not come into this. Sure, so there are those who would employ the energy-wave particles my modified device has managed to abscond for their own personal gain, but I can hardly see the practical benefits of some of these artifacts our benefactors left behind. Ward--")
	P.stamped = list(/obj/item/stamp/rd)
	P.add_stamp_mark("paper_stamped_rd", 0, 0)
	P.forceMove(src)

	P = new()
	P.name = "READ ME! Before you people destroy any more samples"
	P.set_info("how many times do i have to tell you people, these xeno-arch samples are del-i-cate, and should be handled so! careful application of a focussed, concentrated heat or some corrosive liquids should clear away the extraneous carbon matter, while application of an energy beam will most decidedly destroy it entirely - like someone did to the chemical dispenser! W, <b>the one who signs your paychecks</b>")
	P.stamped = list(/obj/item/stamp/rd)
	P.add_stamp_mark("paper_stamped_rd", 0, 0)
	P.forceMove(src)

	P = new()
	P.name = "Reminder regarding the anomalous material suits"
	P.set_info("Do you people think the anomaly suits are cheap to come by? I'm about a hair trigger away from instituting a log book for the damn things. Only wear them if you're going out for a dig, and for god's sake don't go tramping around in them unless you're field testing something, R")
	P.stamped = list(/obj/item/stamp/rd)
	P.add_stamp_mark("paper_stamped_rd", 0, 0)
	P.forceMove(src)

// Rework this whole thing, it was bad.
/obj/structure/noticeboard/anomaly
	name = "xenoarchaeology notice board"

/obj/structure/noticeboard/medical
	name = "medical notice board"
	icon_state = "nboard02"

/obj/structure/noticeboard/medical/Initialize(mapload)
	var/obj/item/paper/P = new()
	P.name = "Staff Notice: Patient rooms"
	P.set_info("<br>No matter how many times I've said this, it doesn't seem to stick, so I'm leaving this reminder: Screwing patients in the patient rooms is a serious breach of professionality and your code of ethics. Take it to the dorms.")
	P.stamped = list(/obj/item/stamp/cmo)
	P.add_stamp_mark("paper_stamped_cmo", 0, 0)
	P.forceMove(src)

	P = new()
	P.name = "Staff Notice: Breakroom & Storage"
	P.set_info("<br>Enjoy the view from the new breakroom. You've also got a storage room full of leftover supplies from the shift before yours.")
	P.stamped = list(/obj/item/stamp/cmo)
	P.add_stamp_mark("paper_stamped_cmo", 0, 0)
	P.forceMove(src)
	. = ..()

/obj/structure/noticeboard/toxins
	name = "toxins lab notice board"
	icon_state = "nboard01"

/obj/structure/noticeboard/toxins/Initialize(mapload)
	var/obj/item/paper/P = new()
	P.name = "Staff Notice: Toxins Mixing"
	P.set_info("<br>Toxins Mixing is currently shut down for the time being, due to damage requiring parts from off station to fix. Please do not use at this time, or risk setting the entire outpost on fire.")
	P.stamped = list(/obj/item/stamp/rd)
	P.add_stamp_mark("paper_stamped_rd", 0, 0)
	P.forceMove(src)
	. = ..()

/obj/structure/noticeboard/nanite
	name = "nanite lab notice board"
	icon_state = "nboard01"

/obj/structure/noticeboard/nanite/Initialize(mapload)
	var/obj/item/paper/P = new()
	P.name = "Staff Notice: Nanite Laboratory"
	P.set_info("<br>The Nanite Laboratory is nearly complete. We're simply awaiting specialized machinery and equipment from central. The lab is currently shut down. Please do not use at this time.")
	P.stamped = list(/obj/item/stamp/rd)
	P.add_stamp_mark("paper_stamped_rd", 0, 0)
	P.forceMove(src)
	. = ..()

/obj/structure/noticeboard/blueshield
	name = "blueshield notice board"
	icon_state = "nboard01"

/obj/structure/noticeboard/blueshield/Initialize(mapload)
	var/obj/item/paper/P = new()
	P.name = "Staff Notice: Blueshield Special Reserve"
	P.set_info("<br>This secure storage unit is intended to be used for special equipment specifically for the use of Blueshield Agents in the event of a Code Red threat to Heads of Staff. Heads of Staff found 'commandeering' this equipment can expect to be severely reprimanded.<br><br>(Underneath, there is a messy handwritten addition.)<br><i>Sorry, we haven't had time or spare funds to issue anything yet. You know how frontier budgets are! Sit tight, champ. -Z.V.</i>")
	P.stamped = list(/obj/item/stamp/centcomm)
	P.add_stamp_mark("paper_stamped_cent", 0, 0)
	P.forceMove(src)
	. = ..()

/obj/structure/noticeboard/library
	icon_state = "nboard02"

/obj/structure/noticeboard/library/Initialize(mapload)
	var/obj/item/paper/P = new()
	P.name = "Library Warning: coffee stains"
	P.set_info("<br>I seem to tell you guys this daily, but please, stop bringing coffee to carpeted areas. It's hard enough to get the stains off wood,let alone carpet.")
	P.forceMove(src)

	P = new()
	P.name = "Library Warning: loud noises"
	P.set_info("Ssshh!<br>People are trying to read in the library, stop bringing the jukebox over there!")
	P.forceMove(src)
	. = ..()

/obj/structure/noticeboard/exploration
	icon_state = "nboard03"

/obj/structure/noticeboard/exploration/Initialize(mapload)
	var/obj/item/paper/P = new()
	P.name = "Memo: Prototype ship"
	P.set_info("<br> With the lost of our last Research installation and the damage sustained to the old exploration shuttle,We've decided to finally approve the construction of the Prototype Star-Runner class Exploration Vessel. Keep in mind it's a prototype, so try not to scratch it's paint. We don't have a second.")
	P.stamped = list(/obj/item/stamp/centcomm)
	P.add_stamp_mark("paper_stamped_cent", 0, 0)
	P.forceMove(src)

	P = new()
	P.name = "Memo RE: Expedition Requirements"
	P.set_info("Jones,<br>For the last time, Expeditions regulations require atleast three crew members, including the Pathfinder and/or Research Director. The next time you activate your bluespace drive with less then that, and you're fired from the department.I won't have this conversation again. <br>- R.F")
	P.stamped = list(/obj/item/stamp/rd)
	P.add_stamp_mark("paper_stamped_rd", 0, 0)
	P.forceMove(src)

	P = new()
	P.name = "Memo RE: Pilot duties"
	P.set_info("Pilots, As you're fully aware, we're on the edge of civilized space out here. <br> Leaving the shuttle area is dangerious. This is why the Prototype is equipped with a proper camera system to keep an eye on the explorers. If you get yourselves killed, and an explorer has to crash land the ship back here, the company is NOT going to be happy.<br>- R.F")
	P.stamped = list(/obj/item/stamp/rd)
	P.add_stamp_mark("paper_stamped_rd", 0, 0)
	P.forceMove(src)
	. = ..()

/obj/structure/noticeboard/airlock
	icon_state = "nboard01"

/obj/structure/noticeboard/airlock/Initialize(mapload)
	var/obj/item/paper/P = new()
	P.name = "Staff Notice: Airlock Proceedure"
	P.set_info("<br>Due to the large amount of new staff unfamiliar with our proceedures we've left you some instructions. <br> To exit through an airlock, simply hit the button to open the interior, and then cycle to exterior once inside. To re-enter the station, enter the airlock, Close the exterior hatch, and look for the customized thermal regulators installed on the wall. <br>This should heat up the air in the airlock, allowing you to open the interior door with no issues.")
	P.stamped = list(/obj/item/stamp/captain)
	P.add_stamp_mark("paper_stamp-cap", 0, 0)
	P.forceMove(src)
	. = ..()
