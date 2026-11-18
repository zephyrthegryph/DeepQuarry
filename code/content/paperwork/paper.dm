/*
 * Paper
 * also scraps of paper
 */

/obj/item/paper
	desc = "A sheet of paper. Write on it with a pen."
	name = "sheet of paper"
	gender = NEUTER
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "paper"
	item_state = "paper"
	w_class = ITEMSIZE_TINY
	plane = MOB_PLANE
	layer = MOB_LAYER
	pressure_resistance = 1

	var/info		//What's actually written on the paper.
	var/tmp/info_links	//A different version of the paper which includes html links at fields and EOF
	var/stamps = ""		//The (text for the) stamps on the paper.
	var/fields		//Amount of user created fields
	var/free_space = MAX_PAPER_MESSAGE_LEN
	var/list/stamped
	/// The stamps pressed on it, as list(icon_state, pixel_x, pixel_y) entries (the photocopier keeps them as grey marks).
	var/list/stamp_marks
	/// Crumpled into a scrap ball.
	var/crumpled = FALSE
	var/rigged = 0
	COOLDOWN_DECLARE(honk_cooldown)
	var/age = 0
	var/last_modified_ckey
	/// Machine-authenticated clinical evidence embedded by a medical scanner.
	/// This is deliberately separate from visible paper text so fax receivers can
	/// validate a genuine scan without trusting player-editable markup.
	var/list/medical_scan_evidence
	/// The registered evidence id this sheet carries and retains while it exists
	/// (a scan printout, a signed form). Released when the paper is destroyed.
	var/carried_evidence_id
	/// The contract paperwork state of a paper (was the contract_document
	/// component; code/modules/contracts/medical_trial_side_contracts.dm). Owned by the paper.
	/// Pinned (state_codecs below): a contract paper stays materialised while it carries its contract.
	var/datum/contract_document/contract_document
	/// Machine-readable freight routing attached by a crate ledger. Visible text
	/// remains ordinary editable paper; this signed payload is invalidated if the
	/// paper or sealed cargo changes.
	var/list/shipping_ledger_data

	///Occult check. Used for do_after
	var/occult = FALSE
	/// Alt-click folds it into a paper plane.
	var/plane_foldable = TRUE

	var/was_maploaded = FALSE // This tracks if the paper was created on mapload.

	var/const/deffont = "Verdana"
	var/const/signfont = "Times New Roman"
	var/const/crayonfont = "Comic Sans MS"
	// TGUI: "read" or "write" view. attack_self/show_content sets
	// to "read"; attackby pen sets to "write".
	var/tgui_view = "read"
	// TGUI: TRUE = caller is allowed to read clear text (humans,
	// silicons, observers, universal_understand). FALSE = stars(info).
	var/tmp/can_read_view = TRUE
	resistance_flags = FLAMMABLE

CAPABILITIES(/obj/item/paper)
	configure(movable_motion(throw_range = 1, throw_speed = 1))
	setup(PROC_REF(encode_text), mapload = TRUE)
	configure(item_worn(slots = SLOT_HEAD, covers = HEAD))
	configure(item_thrown(force = 0))
	configure(item_combat(attack_verbs = list("bapped")))
	configure(item_sounds(drop = SFX_ITEMS_DROP_PAPER, pickup = SFX_ITEMS_PICKUP_PAPER))
	owns_one(nameof(contract_document), /datum/contract_document)
	interface("Paper")
	ui_shape(title = schema_text(), view = enum(list("read", "write")), segments = list_of(row(type = enum(list("text", "field")), text = schema_text(), id = nullable(int()))), stamps = schema_text(), garbled = bool())
	without("ui_open")
	op("write_field", ui_act("write_field", arg("id", schema_text(4096))), then(PROC_REF(ui_act_write_field)))
	op("write_end", ui_act("write_end"), then(PROC_REF(ui_act_write_end)))
	// the old object verb: any paper can mark out a small new area where it is buildable (blueprints.dm)
	op("create_area", menu(), label("Create Area"), needs(carried(), req_conscious(), req_is(nameof(created_area), FALSE, because = MSG(paper/area_made))), then(PROC_REF(create_area_effect)))
	op("paper_crumple", in_hand(), stance(I_HURT), priority(OP_PRIORITY_DEFAULT - 3), label("Crumple"), then(PROC_REF(paper_crumple_op)))
	op("paper_read", in_hand(), priority(OP_PRIORITY_DEFAULT - 4), label("Read"), then(PROC_REF(paper_read_op)))
	op("paper_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_item)))
	op("paper_fold_plane", hand(), ungated(), gesture(GESTURE_ALT), priority(OP_PRIORITY_DEFAULT - 1), label("Fold into a plane"), then(PROC_REF(interaction_fold_plane)))
	op("paper_silicon_read", remote(), priority(OP_PRIORITY_DEFAULT - 1), label("Read"), then(PROC_REF(paper_silicon_read)))
	op("wipe_lipstick", at_target(/mob/living/carbon/human), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), label("Wipe off lipstick"), when(req(PROC_REF(wipes_other_mouth))),
		needs(req_adjacent()), begins(MSG(paper/wiping)), wait(1 SECOND), then(PROC_REF(wipe_lipstick_done)))
	op("paper_rename", menu(), label("Rename paper"), needs(carried()), then(PROC_REF(paper_rename_op)))
	param(nameof(info), pos = 1)
	param(nameof(name), pos = 2)
	rolls(nameof(pixel_x), range_of(-9, 9))
	rolls(nameof(pixel_y), range_of(-8, 8))

/// info_links is derived from info (it embeds this paper's ref), so rebuild it.
/obj/item/paper/state_post_apply(list/blob, flags)
	..()
	updateinfolinks()

/obj/item/paper/card
	name = "blank card"
	desc = "A gift card with space to write on the cover."
	icon_state = "greetingcard"

CAPABILITIES(/obj/item/paper/card)
	configure(item_worn(slots = TRAIT_NONE))

/obj/item/paper/card
	plane_foldable = FALSE //No fun allowed

/// A card draws neither a written nor a blank sheet: its cover is its mapped state.
/obj/item/paper/card/look_parts(datum/look/look)
	return

/obj/item/paper/card/smile
	name = "happy card"
	desc = "A gift card with a smiley face on the cover."
	icon_state = "greetingcard_smile"

/obj/item/paper/card/cat
	name = "cat card"
	desc = "A gift card with a cat on the cover."
	icon_state = "greetingcard_cat"

/obj/item/paper/card/flower
	name = "flower card"
	desc = "A gift card with a flower on the cover."
	icon_state = "greetingcard_flower"

/obj/item/paper/card/heart
	name = "heart card"
	desc = "A gift card with a heart on the cover."
	icon_state = "greetingcard_heart"

/obj/item/paper/alien
	name = "alien tablet"
	desc = "It looks highly advanced"
	icon = 'icons/obj/abductor.dmi'
	icon_state = "alienpaper"

/obj/item/paper/alien/look_parts(datum/look/look)
	look.state(info ? "alienpaper_words" : "alienpaper")

/obj/item/paper/alien/burnpaper()
	return

/obj/item/paper/alien
	plane_foldable = FALSE // No airplanes for me.


/// A paper encodes the text it was written with, titles its description and builds its info links.
/obj/item/paper/proc/encode_text(mapload)
	if(mapload) // Jank, but we do this to prevent maploaded papers from somehow stacking across rounds if re-added to the board by a player.
		was_maploaded = TRUE


	if(name != "paper")
		desc = "This is a paper titled '" + name + "'."

	if(info != initial(info))
		set_info(html_encode(info))
		set_info(replacetext(info, "\n", "<BR>"))
		set_info(parsepencode(info))

	update_space(info)
	updateinfolinks()


/// The sheet: blank or written (or a scrap once crumpled), with the stamps on it. The words are the tracked `info` var every printer and form writes
/// through set_info().
/obj/item/paper/draw(datum/look/look)
	..()
	look_parts(look)
	for(var/list/mark in stamp_marks)
		look.overlay(stamp_image(mark))

/// The sheet's state; a type with another cover (a card, a scrap, a ticket) overrides this.
/obj/item/paper/proc/look_parts(datum/look/look)
	if(initial(icon_state) == "paper_talisman")
		return
	look.state(crumpled ? "scrap" : (info ? "paper_words" : "paper"))

/// Presses one more stamp mark on the sheet.
/obj/item/paper/proc/add_stamp_mark(state, x, y)
	set_stamp_marks((stamp_marks || list()) + list(list(state, x, y)))

/// The overlay of one stamp mark.
/obj/item/paper/proc/stamp_image(list/mark)
	return look_overlay_image('icons/obj/bureaucracy.dmi', mark[1], pixel_x = mark[2], pixel_y = mark[3])

/obj/item/paper/proc/update_space(new_text)
	if(!new_text)
		return

	free_space -= length(strip_html_properly(new_text))

/obj/item/paper/examine(mob/user)
	. = ..()
	if(in_range(user, src) || isobserver(user))
		show_content(user)
	else
		. += span_notice("You have to go closer if you want to read it.")

// TGUI migration. show_content opens Paper.tsx in "read"
// view; attackby pen sets the view to "write" before opening so the
// info_links HTML (with editable field hrefs) is rendered. The Topic
// handler is unchanged — byond:// hrefs embedded in info_links still
// route back to it from inside the TGUI window's HTML container.
/obj/item/paper/proc/show_content(mob/user, forceshow=0)
	set_can_read_view((forceshow || ui_viewer_fact(user, "paper_readable") || mob_rules_of(user).universal_understand))
	set_tgui_view("read")
	tgui_interact(user)

/obj/item/paper/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["title"] = name
	data["view"] = tgui_view
	var/list/merged_1 = ui_data_obj_item_paper(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/paper's window data.
/obj/item/paper/proc/ui_data_obj_item_paper(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["segments"] = get_segments()
	data["stamps"] = stamps || ""
	data["garbled"] = !can_read_view
	return data

// Parse `info` into an ordered list of text/field segments. Field segments
// preserve their 1-based id (matching the legacy field count and the
// id used by addtofield/Topic write=N).
/obj/item/paper/proc/get_segments()
	var/list/segs = list()
	if(!info)
		return segs
	var/marker = "<span class=\"paper_field\">"
	var/marker_len = length(marker)
	var/close = "</span>"
	var/close_len = length(close)
	var/cursor = 1
	var/field_number = 0
	var/total = length(info)
	while(cursor <= total)
		var/istart = findtext(info, marker, cursor)
		if(!istart)
			segs += list(list("type" = "text", "text" = copytext(info, cursor), "id" = null))
			break
		if(istart > cursor)
			segs += list(list("type" = "text", "text" = copytext(info, cursor, istart), "id" = null))
		var/iend = findtext(info, close, istart)
		if(!iend)
			// Malformed; treat the rest as text.
			segs += list(list("type" = "text", "text" = copytext(info, cursor), "id" = null))
			break
		field_number++
		var/content_start = istart + marker_len
		var/field_text = copytext(info, content_start, iend)
		segs += list(list("type" = "field", "id" = field_number, "text" = field_text))
		cursor = iend + close_len
	return segs

/obj/item/paper/proc/ui_act_write_field(datum/act/op/A, id)
	var/mob/user = A.actor
	do_write_action("[id]", user)
	return TRUE

/obj/item/paper/proc/ui_act_write_end(datum/act/op/A)
	var/mob/user = A.actor
	do_write_action("end", user)
	return TRUE

// Shared write-prompt + pencode-parse + commit. Same checks the legacy
// Topic write branch had — pen-in-hand, RIG fallback, range/loc, fields
// cap — and the same writes via addtofield or info-append.
/obj/item/paper/proc/do_write_action(id, mob/user)
	return paper_write_stage(id, user)

/obj/item/paper/proc/paper_write_stage(id, mob/user, paper_answer, paper_answer_ready = FALSE)
	if(!user || user.stat || user.restrained())
		return
	if(free_space <= 0)
		to_chat(user, span_info("There isn't enough space left on \the [src] to write anything."))
		return
	if(!paper_answer_ready)
		open_request(src, /datum/prompt/text/paper_write_review, PROC_REF(paper_write_answered), answerer = user, paper_operator = user, paper_field_id = id, question = "Enter what you want to write:", title = "Write", max_len = MAX_PAPER_MESSAGE_LEN, multiline = TRUE)
		return
	var/t = paper_answer
	if(isnull(t))
		return
	if(!t)
		return
	var/obj/item/i = user.get_active_hand()
	var/iscrayon = 0
	if(!istype(i, /obj/item/pen))
		tgui_alert_async(user, "You aren't holding a pen anymore! If you want to keep your work, grab one.", "No Pen!")
		i = user.get_active_hand()
	if(!istype(i, /obj/item/pen))
		var/mob/living/M = user
		if(istype(M) && M.get_equipped_item(SLOT_ID_BACK) && istype(M.get_equipped_item(SLOT_ID_BACK), /obj/item/rig))
			var/obj/item/rig/r = M.get_equipped_item(SLOT_ID_BACK)
			var/obj/item/rig_module/device/pen/m = locate_in_list(r.installed_modules, /obj/item/rig_module/device/pen)
			if(!r.offline && m)
				i = m.device
			else
				return
		else
			return
	if(istype(i, /obj/item/pen/crayon))
		iscrayon = 1
	if(istype(loc, /obj/item/clipboard) || istype(loc, /obj/structure/noticeboard) || istype(loc, /obj/item/folder))
		if(loc.loc != user && !in_range(loc, user))
			return
	else if(loc != user && !Adjacent(user))
		return
	var/last_fields_value = fields
	var/contains_signature = findtext(t, "\[sign\]")
	t = replacetext(t, "\n", "<BR>")
	t = parsepencode(t, i, user, iscrayon)
	was_maploaded = FALSE
	if(fields > 50)
		to_chat(user, span_warning("Too many fields. Sorry, you can't do this."))
		fields = last_fields_value
		return
	if(id != "end")
		addtofield(text2num(id), t)
		on_field_written(user, text2num(id), i)
	else
		set_info(info + (t))
		updateinfolinks()
	last_modified_ckey = user.ckey
	update_space(t)
	if(contains_signature)
		on_signature(user, get_signature(i, user))
	play_sfx(src, SFX_BUREAUCRACY_PEN, 0.5)

/obj/item/paper/proc/on_signature(mob/living/user, signature)
	return

/obj/item/paper/proc/on_field_written(mob/living/user, field_id, obj/item/pen/writing_implement)
	return

/// The Rename paper menu entry.
/obj/item/paper/proc/paper_rename_op(datum/act/op/A)
	paper_verb_rename(A.actor)
	return OP_OK

/// Old Rename paper verb.
/obj/item/paper/proc/paper_verb_rename(mob/user, obj/item/held)
	return paper_rename_stage(user, held)

/obj/item/paper/proc/paper_rename_stage(mob/user, obj/item/held, paper_answer, paper_answer_ready = FALSE)
	if(CLUMSY_FAIL_CHANCE(user))
		to_chat(user, span_warning("You cut yourself on the paper."))
		return
	if(!paper_answer_ready)
		open_request(src, /datum/prompt/text/paper_rename_review, PROC_REF(paper_rename_answered), answerer = user, paper_operator = user, paper_held = held, question = "What would you like to label the paper?", title = "Paper Labelling", max_len = MAX_NAME_LEN, encode = FALSE, name_text = TRUE)
		return
	var/_answer_k309 = paper_answer
	if(isnull(_answer_k309))
		return
	var/n_name = sanitizeSafe(_answer_k309, MAX_NAME_LEN)

	// We check loc one level up, so we can rename in clipboards and such. See also: /obj/item/photo/photo_verb_rename()
	if((loc == user || loc.loc && loc.loc == user) && user.stat == CONSCIOUS && n_name)
		name = n_name
		if(n_name != "paper")
			desc = "This is a paper titled '" + name + "'."

		add_fingerprint(user)
	return

/// Old attack_self, as an op: read it, or crumple it in combat mode.
/obj/item/paper/proc/paper_crumple_op(datum/act/op/A)
	paper_use(A.actor, I_HURT)
	return OP_OK

/obj/item/paper/proc/paper_read_op(datum/act/op/A)
	paper_use(A.actor, I_HELP)
	return OP_OK

/// Old attack_self: read it, or crumple it when `stance` is harm.
/obj/item/paper/proc/paper_use(mob/living/user, stance)
	if(occult)
		return
	if(stance == I_HURT)
		if(crumpled)
			user.show_message(span_warning("\The [src] is already crumpled."))
			return
		//crumple dat paper
		set_info(stars(info,85))
		act_message(user, src, others = "%U% crumples %T% into a ball!")
		play_sfx(src, SFX_BUREAUCRACY_PAPERCRUMPLE)
		set_crumpled(TRUE)
		return
	user.examinate(src)
	if(rigged && (GLOB.Holiday == "April Fool's Day"))
		if(COOLDOWN_FINISHED(src, honk_cooldown))
			COOLDOWN_START(src, honk_cooldown, 2 SECONDS)
			play_sfx(src, SFX_ITEMS_BIKEHORN)
	return

// AI/cyborg viewer routes through the same TGUI paper window.
/// Old attack_ai: read the paper; close enough (via the AI's camera) to read it properly.
/obj/item/paper/proc/paper_silicon_read(datum/act/op/A)
	var/mob/living/silicon/ai/user = A.actor
	var/dist
	if(istype(user) && user.camera)
		dist = get_dist(src, user.camera)
	else
		dist = get_dist(src, user)
	set_can_read_view((dist < 2))
	set_tgui_view("read")
	tgui_interact(user)
	return OP_OK

MSG_DEF(paper/wiping, span_notice("You begin to wipe off %T%'s lipstick."), span_warning("%U% begins to wipe %T%'s lipstick off with %I%."))

/// The wipe aims at the mouth, and at somebody else (what is aimed at is fixed while the click is decided).
/obj/item/paper/proc/wipes_other_mouth(datum/act/op/A)
	return (A.target != A.actor && read_once(hud_of(A.actor)?.zone_sel?.selecting) == O_MOUTH) ? null : /datum/msg/req_failed

/obj/item/paper/proc/wipe_lipstick_done(datum/act/op/A)
	var/mob/living/carbon/human/H = A.target
	act_message(A.actor, H, MSG_SELF(span_notice("You wipe off %T%'s lipstick.")), MSG_OTHERS(span_notice("%U% wipes %T%'s lipstick off with \the [src].")))
	H.looks.set_lip_style(null)
	return OP_OK

/obj/item/paper/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(hud_of(user)?.zone_sel?.selecting == O_EYES)
		act_message(user, M, MSG_SELF(span_notice(" %U% holds up a paper and shows it to %T%. ")), MSG_OTHERS(span_notice("You show the paper to %T%. ")))
		M.examinate(src)
		return ITEM_INTERACT_SUCCESS

	else if(hud_of(user)?.zone_sel?.selecting == O_MOUTH) // lipstick wiping
		if(ishuman(M))
			var/mob/living/carbon/human/H = M
			if(H == user)
				to_chat(user, span_notice("You wipe off the lipstick with [src]."))
				H.looks.set_lip_style(null)

/obj/item/paper/proc/set_content(text,title)
	if(title)
		name = title
	set_info(html_encode(text))
	set_info(parsepencode(text))
	update_space(info)
	updateinfolinks()

/obj/item/paper/proc/addtofield(id, text, links = 0)
	var/locid = 0
	var/laststart = 1
	var/textindex = 1
	while(1) // I know this can cause infinite loops and fuck up the whole server, but the if(istart==0) should be safe as fuck
		var/istart = 0
		if(links)
			istart = findtext(info_links, "<span class=\"paper_field\">", laststart)
		else
			istart = findtext(info, "<span class=\"paper_field\">", laststart)

		if(istart==0)
			return // No field found with matching id

		laststart = istart+1
		locid++
		if(locid == id)
			var/iend = 1
			if(links)
				iend = findtext(info_links, "</span>", istart)
			else
				iend = findtext(info, "</span>", istart)

			textindex = iend
			break

	if(links)
		var/before = copytext(info_links, 1, textindex)
		var/after = copytext(info_links, textindex)
		info_links = before + text + after
	else
		var/before = copytext(info, 1, textindex)
		var/after = copytext(info, textindex)
		set_info(before + text + after)
		updateinfolinks()

/obj/item/paper/proc/updateinfolinks()
	info_links = info
	var/i = 0
	for(i=1,i<=fields,i++)
		addtofield(i, "<font face=\"[deffont]\"><A href='byond://?src=[REF(src)];write=[i]'>write</A></font>", 1)
	info_links = info_links + "<font face=\"[deffont]\"><A href='byond://?src=[REF(src)];write=end'>write</A></font>"


/obj/item/paper/proc/clearpaper()
	set_info(null)
	set_stamps(null)
	free_space = MAX_PAPER_MESSAGE_LEN
	stamped = list()
	set_stamp_marks(null)
	updateinfolinks()

/obj/item/paper/proc/get_signature(obj/item/pen/P, mob/user as mob)
	return pen_signature(P, user)

/obj/item/paper/proc/parsepencode(t, obj/item/pen/P, mob/user as mob, iscrayon = 0)
	t = pencode_to_html(t, P, user, iscrayon)

//	t = replacetext(t, "#", "") // Junk converted to nothing!

//Count the fields
	var/laststart = 1
	while(1)
		var/i = findtext(t, "<span class=\"paper_field\">", laststart)	//</span>
		if(i==0)
			break
		laststart = i+1
		fields++

	return t

/obj/item/paper/proc/burnpaper(obj/item/flame/P, mob/user)
	var/class = "warning"

	if(P.lit && !user.restrained())
		if(istype(P, /obj/item/flame/lighter/zippo))
			class = "rose"

		act_message(user, src, MSG_SELF("<span class='[class]'>You hold %I% up to %T%, burning it slowly.</span>"), \
			MSG_OTHERS("<span class='[class]'>%U% holds %I% up to %T%, it looks like %THEYRE% trying to burn it!</span>"), \
			item = P)
		play_sfx(src, SFX_BUREAUCRACY_PAPERBURN)

		after(src, 2 SECONDS, PROC_REF(burn_through), with = list(user, P, class))


/obj/item/paper/get_worn_icon_state(slot_name)
	if(slot_name == slot_head_str)
		return "paper" //Gross, but required for now.
	return ..()

/// Old attackby.
/obj/item/paper/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/P = A.held
	var/clown = 0
	if(user.mind && ((user.mind.role_alt_title == JOB_CLOWN) || (user.mind.role_alt_title == JOB_ALT_JESTER) || (user.mind.role_alt_title == JOB_ALT_FOOL))) // Let clows/fools/jesters use clown stamps
		clown = 1

	if(istype(P, /obj/item/tape_roll))
		var/obj/item/tape_roll/tape = P
		tape.stick(src, user)
		return OP_PASS

	if(istype(P, /obj/item/clipboard))
		var/obj/item/clipboard/CB = P
		if(src.loc == user)
			user.drop_from_inventory(src)
		src.forceMove(CB)
		rel_set(CB, nameof(CB.toppaper), src)
		to_chat(user, span_notice("You clip the [src] onto \the [CB]."))

	if(istype(P, /obj/item/folder))
		if(src.loc == user)
			user.drop_from_inventory(src)
		src.forceMove(P)
		to_chat(user, span_notice("You tuck the [src] into \the [P]."))

	if(istype(P, /obj/item/paper) || istype(P, /obj/item/photo))
		if (istype(P, /obj/item/paper/carbon))
			var/obj/item/paper/carbon/C = P
			if (!C.iscopy && !C.copied)
				to_chat(user, span_notice("Take off the carbon copy first."))
				add_fingerprint(user)
				return OP_PASS
		var/obj/item/paper_bundle/B = new(src.loc)
		if (name != initial(name))
			B.name = name
		else if (P.name != initial(P.name))
			B.name = P.name
		user.drop_from_inventory(P)
		if(ishuman(user))
			var/mob/living/carbon/human/h_user = user
			if (h_user.get_equipped_item(SLOT_ID_HAND_R) == src)
				h_user.drop_from_inventory(src)
				h_user.put_in_r_hand(B)
			else if (h_user.get_equipped_item(SLOT_ID_HAND_L) == src)
				h_user.drop_from_inventory(src)
				h_user.put_in_l_hand(B)
			else if (h_user.get_equipped_item(SLOT_ID_POCKET_L) == src)
				h_user.drop_from_inventory(src)
				if(!h_user.equip_to_slot_if_possible(B, SLOT_ID_POCKET_L))
					h_user.drop_from_inventory(B)
			else if (h_user.get_equipped_item(SLOT_ID_POCKET_R) == src)
				h_user.drop_from_inventory(src)
				if(!h_user.equip_to_slot_if_possible(B, SLOT_ID_POCKET_R))
					h_user.drop_from_inventory(B)
			else if (h_user.get_equipped_item(SLOT_ID_HEAD) == src)
				h_user.drop_from_inventory(src)
				h_user.put_in_hands(B)
			else if (!istype(src.loc, /turf))
				src.forceMove(get_turf(h_user))
				if(h_user.client)	client_screen_remove(h_user.client, src)
				h_user.put_in_hands(B)
		to_chat(user, span_notice("You clip the [P.name] to [(src.name == "paper") ? "the paper" : src.name]."))
		src.forceMove(B)
		P.forceMove(B)

		rel_add(B, nameof(B.pages), src)
		rel_add(B, nameof(B.pages), P)

	else if(istype(P, /obj/item/pen))
		if(crumpled)
			to_chat(user, span_warning("\The [src] is too crumpled to write on."))
			return OP_PASS

		var/obj/item/pen/robopen/RP = P
		if(istype(RP) && RP.mode == 2)
			RP.RenamePaper(user, src)
		else
			// pen interact opens Paper.tsx in "write" view; the
			// info_links HTML rendered there still carries the field hrefs
			// that route back to Topic for the actual write action.
			set_can_read_view(TRUE)
			set_tgui_view("write")
			tgui_interact(user)
		return OP_PASS

	else if(istype(P, /obj/item/stamp) || istype(P, /obj/item/clothing/accessory/ring/seal))
		set_stamps(stamps + ((stamps=="" ? "<HR>" : "<BR>") + span_italics(stamp_mark_text(P, "paper"))))
		if((!in_range(src, user) && loc != user && !( istype(loc, /obj/item/clipboard) ) && loc.loc != user && user.get_active_hand() != P))
			return OP_PASS
		var/x, y
		if(istype(P, /obj/item/stamp/captain) || istype(P, /obj/item/stamp/centcomm))
			x = rand(-2, 0)
			y = rand(-1, 2)
		else
			x = rand(-2, 2)
			y = rand(-3, 2)

		if(!clown && !stamp_usable_by(P, user))
			to_chat(user, span_notice("You are totally unable to use the stamp. HONK!"))
			return OP_PASS

		if(!stamped)
			stamped = new
		stamped += P.type
		add_stamp_mark("paper_[P.icon_state]", x, y)

		play_sfx(src, SFX_BUREAUCRACY_STAMP)
		to_chat(user, span_notice("You stamp the paper with your rubber stamp."))

	else if(istype(P, /obj/item/flame))
		burnpaper(P, user)

	add_fingerprint(user)
	return OP_PASS

/*
 * Premade paper
 */
/obj/item/paper/Court
	name = "Judgement"
	info = "For crimes against the station, the offender is sentenced to:<BR>\n<BR>\n"

/obj/item/paper/courtroom
	name = "A Crash Course in Legal SOP on SS13"
	info = span_bold("Roles:") + "<BR>\nThe " + JOB_DETECTIVE + " is basically the investigator and prosecutor.<BR>\nThe Staff Assistant can perform these functions with written authority from the " + JOB_DETECTIVE + ".<BR>\nThe " + JOB_SITE_MANAGER + "/HoP/" + JOB_WARDEN + " is ct as the judicial authority.<BR>\nThe " + JOB_SECURITY_OFFICER + "s are responsible for executing warrants, security during trial, and prisoner transport.<BR>\n<BR>\n<B>Investigative Phase:</B><BR>\nAfter the crime has been committed the " + JOB_DETECTIVE + "'s job is to gather evidence and try to ascertain not only who did it but what happened. He must take special care to catalogue everything and don't leave anything out. Write out all the evidence on paper. Make sure you take an appropriate number of fingerprints. IF he must ask someone questions he has permission to confront them. If the person refuses he can ask a judicial authority to write a subpoena for questioning. If again he fails to respond then that person is to be jailed as insubordinate and obstructing justice. Said person will be released after he cooperates.<BR>\n<BR>\nONCE the FT has a clear idea as to who the criminal is he is to write an arrest warrant on the piece of paper. IT MUST LIST THE CHARGES. The FT is to then go to the judicial authority and explain a small version of his case. If the case is moderately acceptable the authority should sign it. Security must then execute said warrant.<BR>\n<BR>\n<B>Pre-Pre-Trial Phase:</B><BR>\nNow a legal representative must be presented to the defendant if said defendant requests one. That person and the defendant are then to be given time to meet (in the jail IS ACCEPTABLE). The defendant and his lawyer are then to be given a copy of all the evidence that will be presented at trial (rewriting it all on paper is fine). THIS IS CALLED THE DISCOVERY PACK. With a few exceptions, THIS IS THE ONLY EVIDENCE BOTH SIDES MAY USE AT TRIAL. IF the prosecution will be seeking the death penalty it MUST be stated at this time. ALSO if the defense will be seeking not guilty by mental defect it must state this at this time to allow ample time for examination.<BR>\nNow at this time each side is to compile a list of witnesses. By default, the defendant is on both lists regardless of anything else. Also the defense and prosecution can compile more evidence beforehand BUT in order for it to be used the evidence MUST also be given to the other side.\nThe defense has time to compile motions against some evidence here.<BR>\n<B>Possible Motions:</B><BR>\n1. <U>Invalidate Evidence-</U> Something with the evidence is wrong and the evidence is to be thrown out. This includes irrelevance or corrupt security.<BR>\n2. <U>Free Movement-</U> Basically the defendant is to be kept uncuffed before and during the trial.<BR>\n3. <U>Subpoena Witness-</U> If the defense presents god reasons for needing a witness but said person fails to cooperate then a subpoena is issued.<BR>\n4. <U>Drop the Charges-</U> Not enough evidence is there for a trial so the charges are to be dropped. The FT CAN RETRY but the judicial authority must carefully reexamine the new evidence.<BR>\n5. <U>Declare Incompetent-</U> Basically the defendant is insane. Once this is granted a medical official is to examine the patient. If he is indeed insane he is to be placed under care of the medical staff until he is deemed competent to stand trial.<BR>\n<BR>\nALL SIDES MOVE TO A COURTROOM<BR>\n<B>Pre-Trial Hearings:</B><BR>\nA judicial authority and the 2 sides are to meet in the trial room. NO ONE ELSE BESIDES A SECURITY DETAIL IS TO BE PRESENT. The defense submits a plea. If the plea is guilty then proceed directly to sentencing phase. Now the sides each present their motions to the judicial authority. He rules on them. Each side can debate each motion. Then the judicial authority gets a list of crew members. He first gets a chance to look at them all and pick out acceptable and available jurors. Those jurors are then called over. Each side can ask a few questions and dismiss jurors they find too biased. HOWEVER before dismissal the judicial authority MUST agree to the reasoning.<BR>\n<BR>\n<B>The Trial:</B><BR>\nThe trial has three phases.<BR>\n1. <B>Opening Arguments</B>- Each side can give a short speech. They may not present ANY evidence.<BR>\n2. <B>Witness Calling/Evidence Presentation</B>- The prosecution goes first and is able to call the witnesses on his approved list in any order. He can recall them if necessary. During the questioning the lawyer may use the evidence in the questions to help prove a point. After every witness the other side has a chance to cross-examine. After both sides are done questioning a witness the prosecution can present another or recall one (even the EXACT same one again!). After prosecution is done the defense can call witnesses. After the initial cases are presented both sides are free to call witnesses on either list.<BR>\nFINALLY once both sides are done calling witnesses we move onto the next phase.<BR>\n3. <B>Closing Arguments</B>- Same as opening.<BR>\nThe jury then deliberates IN PRIVATE. THEY MUST ALL AGREE on a verdict. REMEMBER: They mix between some charges being guilty and others not guilty (IE if you supposedly killed someone with a gun and you unfortunately picked up a gun without authorization then you CAN be found not guilty of murder BUT guilty of possession of illegal weaponry.). Once they have agreed they present their verdict. If unable to reach a verdict and feel they will never they call a deadlocked jury and we restart at Pre-Trial phase with an entirely new set of jurors.<BR>\n<BR>\n<B>Sentencing Phase:</B><BR>\nIf the death penalty was sought (you MUST have gone through a trial for death penalty) then skip to the second part. <BR>\nI. Each side can present more evidence/witnesses in any order. There is NO ban on emotional aspects or anything. The prosecution is to submit a suggested penalty. After all the sides are done then the judicial authority is to give a sentence.<BR>\nII. The jury stays and does the same thing as I. Their sole job is to determine if the death penalty is applicable. If NOT then the judge selects a sentence.<BR>\n<BR>\nTADA you're done. Security then executes the sentence and adds the applicable convictions to the person's record.<BR>\n"

/obj/item/paper/djstation
	name = "DJ Listening Outpost"
	info = span_bold("Welcome new owner!") + "<BR><BR>You have purchased the latest in listening equipment. The telecommunication setup we created is the best in listening to common and private radio fequencies. Here is a step by step guide to start listening in on those saucy radio channels:<br><ol><li>Equip yourself with a multi-tool</li><li>Use the multitool on each machine, that is the broadcaster, receiver and the relay.</li><li>Turn all the machines on, it has already been configured for you to listen on.</li></ol> Simple as that. Now to listen to the private channels, you'll have to configure the intercoms, located on the front desk. Here is a list of frequencies for you to listen on.<br><ul><li>145.7 - Common Channel</li><li>144.7 - Private AI Channel</li><li>135.9 - Security Channel</li><li>135.7 - Engineering Channel</li><li>135.5 - Medical Channel</li><li>135.3 - Command Channel</li><li>135.1 - Science Channel</li><li>134.9 - Mining Channel</li><li>134.7 - Cargo Channel</li>"

/obj/item/paper/crumpled
	name = "paper scrap"
	icon_state = "scrap"
	crumpled = TRUE

/// A scrap keeps its mapped state.
/obj/item/paper/crumpled/look_parts(datum/look/look)
	return

/obj/item/paper/crumpled/bloody
	icon_state = "scrap_bloodied"


/obj/item/paper/manifest
	name = "supply manifest"
	var/is_copy = 1

CAPABILITIES(/obj/item/paper/manifest)
	configure(obj_rules(sellable_type = /datum/sellable/manifest))


//Used in  maps/overmap/space_pois/dj_31x28
//Used in maps\overmap\space_pois\oldstation_80x45.dmm
/obj/item/paper/cryo_awaken
	info = span_bold("**WARNING**") + "<BR><BR>Catastrophic damage sustained to station. Powernet exhausted to reawaken crew.<BR><BR>Immediate Objectives<br><br>1: Activate emergency power generator<br>2: Lift station lockdown on the bridge<br><br>Please locate the 'Damage Report' on the bridge for a detailed situation report."
	name = "Cryo Awakening Alert"

/obj/item/paper/singularity
	info = span_bold("*Singularity Generator*") + "<br><br>Modern power generation typically comes in two forms, a Fusion Generator or a Fission Generator. Fusion provides the best space to power ratio, and is typically seen on military or high security ships and stations, however Fission reactors require the usage of expensive, and rare, materials in its construction.. Fission generators are massive and bulky, and require a large reserve of uranium to power, however they are extremely cheap to operate and oft need little maintenance once operational.<br><br>The Singularity aims to alter this, a functional Singularity is essentially a controlled Black Hole, a Black Hole that generates far more power than Fusion or Fission generators can ever hope to produce. "
	name = "Singularity Generator"

/obj/item/paper/health_analyzer
	info = span_bold("*Health Analyser*") + "<br><br>The portable Health Analyser is essentially a handheld variant of a health analyser. Years of research have concluded with this device which is capable of diagnosing even the most critical, obscure or technical injuries any humanoid entity is suffering in an easy to understand format that even a non-trained health professional can understand.<br><br>The health analyser is expected to go into full production as standard issue medical kit."
	name = "Health Analyser Report"

/obj/item/paper/b01rig
	info = span_bold("*Prototype Hardsuit*") + "<br><br>The B01-RIG Hardsuit is a prototype powered exoskeleton. Based off of a recovered pre-void war era united Earth government powered military exosuit, the RIG Hardsuit is a breakthrough in Hardsuit technology, and is the first post-void war era Hardsuit that can be safely used by an operator.<br><br>The B01 however suffers a myriad of constraints. It is slow and bulky to move around, it lacks any significant armor plating against direct attacks and its internal heads up display is unfinished,  resulting in the user being unable to see long distances.<br><br>The B01 is unlikely to see any form of mass production, but will serve as a base for future Hardsuit developments."
	name = "B01-RIG Hardsuit Report"

//Used in maps\overmap\space_pois\ussp_84x90.dmm
/obj/item/paper/djstation/relay_reports
	info = span_bold("Aug. 28th, 2532") + "<hr><small>Our listening outpost has relayed some alarming reports about TSF activity in the sector. While intercepted communications suggests it's a simple research effort, I can't shake the feeling that those dogged bastards have finally chased us down.<br><br>The Captain assures me that there's nothing to worry about, but I find it hard to take a man who's paranoid of a powered shower door seriously.<br><br><i>- Comms Officer Vostok</i></small>"
	name = "personal log"

/obj/item/paper/djstation/commendation_recommendation
	info = span_bold("Recommended Party") + "Comrade Blyatski<br>" + span_bold("Signing Officer:") + "Mikail Gogochev<hr><small>Captain,<br><br>I recognize the nature of this request my seem strange, but please, hear me out. Comrade Blyatski, though he is but a wee bot, is like iron fist of Commissar Grigor himself! Just the other day he chased that useless bastard Totstoi clean out of brig, you should have seen the way that drunkard whimpered! Like a dog with his tail between his legs.<br><br>Anyways, I digress! If any one is worth of recognition, it is our ever-vigilant and beloved Blyatski, true champion of USSP.<br><br>If you wish to, perhaps, see his vigilance and dedication in person, well! You need only come to inspect armoury.<br><br>Comrade Blyatski awaits your decision."
	name = "recommendation for commendation"

/obj/item/paper/crumpled/cyka
	info = span_bold("I KNOW IT WAS YOU WHO THREW AWAY MY LUCKY UNDERWEAR THIS TIME. I SWEAR, IF I SEE YOUR SKINNY RAT NECK AROUND I AM GOING TO WRING IT UNTIL YOU GO PURPLE!<br><br>NOBODY! NOBODY TOUCHES BORIS' LUCKY UNDERWEAR WITHOUT SUFFERING THE CONSEQUENCES!")
	name = "LISTEN UP CYKA"

/obj/item/paper/crumpled/desist
	info = "<i>This note has been effaced with all manner of crude drawings that are too vile to properly give a description to.</i><br><small>Totstoi,<br><br>I know it's you who's been feeding my cats alcohol, I do not care what your reasons are but you are getting in the way of important research. This is the fifth cat that I've had to replace this month because of your crude sense of humour, and I will be speaking with Chief Borachov if you don't stop.<br><br>- <i>Nikolai Kartov</i>, Deputy Researcher";
	name = "Desist at once!"

/obj/item/paper/djstation/visitor_log
	info = "August 21 - Most Excellent Commissar Grigor<br>August 22 - Nobody<br>August 23 - Nobody<br>August 24 - Nobody<br>August 25 - Why do I even bother?<br>August 26 - Nobody<br>August 27 -"
	name = "visitor log"

/obj/item/paper/djstation/experiment
	info = "We have finally hit upon it, no more shall Katerina look past me in favor of other company! Experiment 432-A shows an incredible rate of cellular regeneration, and I posit that we have finally breaken down the great boundary between life and death--true biological immortality!<br><br>Of course, the aggressive behaviour is an undue side-effect, but it is only cat after all. I am certain a few sedative-laced cat treats will suffice to prep for autopsy."
	name = "Experiment 432-A"

/obj/item/paper/djstation/maint_report
	info = "This is the fifth time this month I've had to replace the cabling to the damn lockdown circuit. It's bad enough the condensor is constantly on the fritz and the damn systems take nearly a week to cycle and reboot, but now I've got the captain breathing down my neck over his stupid shower and Commissar Grigor. Mikail was telling me the man's face went so red when the lights popped that you could see him glowing in the dark.<br><br>If he thought that was bad, well, if I hadn't installed an override in the mess hall we would have been sitting in the dark for the week.<br><br>Rusthven says we should be getting a new shipment of cabling, though I'm not sure we'll ever have enough supplies to keep this place properly operational."
	name = "maintenance report"

/obj/item/paper/djstation/forgive_me_father
	info = "Father Gregor,<br><br>You will have to forgive me, but I am unable to get your order for one of those 'veil shifters' like you asked. I am admittedly unsure what you planned to do with it, the business of the clergy is not mine, but Vostok was quick to put the kaibosh on your order after we lost the last shipment.<br><br>The boys are still reeling from the headaches from last time, and Khoma complains that he sees the blue lights whenever he closes his eyes.<br><br>I am not one to question a man of God but I beg of you, please do not try to order any more of these artifacts. They are cursed, and all manner of demons seem to follow in their wake.<br><br>- <small><i>Andrei Vostovich</i></small>, Supply Technician";
	name = "My apologies, father"

/obj/item/paper/djstation/babyman
	info = "<i>A primitive rendition of a crying egg being stomped on by a boot has been scribbled in the right-hand margin of the paper.</i><br><br>Wahwahwah! True egghead! I do not give two shits about your cats or 'syence,' if you write to Chief I will tell that bitch Katerina about your baby boy crush.<br><br>Also, why you sign name on paper? I am next door, fuckhead, I know baby man note is yours as soon as I see it. You write girly letter like I am your lover, maybe if you spend less time in corner with cat you would be real man? Of course, you would still look like camel shit stuck to Totstoi's boot!"
	name = "dear baby man"

/obj/item/paper/crumpled/love_poem
	info = "<i>This note has been crossed out so many times it's hard to make out its contents.</i><br><small>Katerina,<br><br><s>Your eyes are like diamonds,<br>Forged in the very fire of Cygni-A.<br>My heart yearns for you,<br>For your soft beauty<br>Fuckfucknothat'sbad.<br><br>Your voice is like liquid gold,<br>Smothering me in its delicate contours.<br>Never before had I known,<br>The touch,<br>The touch!<br>The touch of an angel's voice</s><br><br>note to self: stick to science, poetry is not my forte.</small>"
	name = "love poem"

/obj/item/paper/djstation/unknown_report
	info = "Fuck. Fuckfuckfuck. I knew this mission was a mistake, that idiot Thomas got himself killed by some angry Russian security bot in the armoury, and the Lt. ran into the annex like a moron and got himself trapped. Now I'm just sitting on my god damn hands because this shuttle won't bloody move. Stupid USSP piece of shit docking arm must be jammed and I don't have the kit to go out and fix it.<br><br>Who the hell attacks a space station without EVA gear anyways? It's not like you can just bloody well waltz out into space with a hot coffee and shrug it off."
	name = "unknown report"

/obj/item/paper/djstation/confession
	info = "I am worried about Totstoi. It is the fifth time this week he has been sent to the drunk tank, and no matter how many times I come to him he can only seem to find God at the bottom of a glass of Tunguska.<br><br>All this drinking, I hate to think poorly of the USSP but, in placing no cost on such things are we not just as bad as the TSF? Many have even forgotten their true heritage in favour of Galactic Common. Such indulgence, such forgetfulness, it can not be good for the spirits, let alone the soul."
	name = "a confession"

/obj/item/paper/crumpled/button
	info = "That idiot bastard Totstoi found my button. Stupid drunk was trying to put change into the free cigarette machine and dropped it. Lo' and behold, dumbass decides to look under the machine for his precious rubles.<br><br>Thankfully that green-livered swine cares more about drink than anything else, managed to buy him off. Will have to move the switch somewhere else now, but where?"
	name = "worn paper"

//Used in maps\overmap\space_pois\wizardcrash_20x35.dmm
/obj/item/paper/zap_brief
	info = "To the Magnificent Z.A.P.<BR>A small mining base has been created within our territory by wandless scum. Send them a message from the wizard federation they will not forget. I know your kind is rather fragile, but a group of lightly armed miners should not pose any threat to you at all. Just be warned they have a security cyborg for self defence, you might want to tune your spells to that threat. I look forward to hearing of your success.<BR>Grand Magus Abra the Wonderous"
	name = "Mission Briefing"

/obj/item/paper/proc/burn_through(mob/user, obj/item/flame/P, class)
	if(user && P && get_dist(src, user) < 2 && user.get_active_hand() == P && P.lit)
		act_message(user, src, MSG_SELF("<span class='[class]'>You burn right through %T%, turning it to ash. It flutters through the air before settling on the floor in a heap.</span>"), \
			MSG_OTHERS("<span class='[class]'>%U% burns right through %T%, turning it to ash. It flutters through the air before settling on the floor in a heap.</span>"))

		if(user.get_inactive_hand() == src)
			user.drop_from_inventory(src)

		replace_with(src, /obj/effect/decal/cleanable/ash)

	else
		to_chat(user, span_red("You must hold \the [P] steady to burn \the [src]."))

/obj/item/paper/on_destroy(force)
	release_carried_evidence()
	..()

/// Drops this sheet's hold on its carried evidence id.
/obj/item/paper/proc/release_carried_evidence()
	if(carried_evidence_id)
		SScontracts?.release_evidence(carried_evidence_id)
		carried_evidence_id = null

/// Pencode ([b], [sign], [field], ...) to the paper HTML, in P's colour (crayon rules when iscrayon).
/// Shared by paper and the writable capability (code/datums/capabilities/library/writable.dm).
/proc/pencode_to_html(t, obj/item/pen/P, mob/user, iscrayon = FALSE)

	t = replacetext(t, "\[center\]", "<center>")
	t = replacetext(t, "\[/center\]", "</center>")
	t = replacetext(t, "\[br\]", "<BR>")
	t = replacetext(t, "\[b\]", "<B>")
	t = replacetext(t, "\[/b\]", "</B>")
	t = replacetext(t, "\[i\]", "<I>")
	t = replacetext(t, "\[/i\]", "</I>")
	t = replacetext(t, "\[u\]", "<U>")
	t = replacetext(t, "\[/u\]", "</U>")
	t = replacetext(t, "\[time\]", "[stationtime2text()]")
	t = replacetext(t, "\[date\]", "[stationdate2text()]")
	t = replacetext(t, "\[station\]", "[station_name()]")
	t = replacetext(t, "\[large\]", "<font size=\"4\">")
	t = replacetext(t, "\[/large\]", "</font>")
	if(findtext(t, "\[sign\]"))
		t = replacetext(t, "\[sign\]", "<font face=\"[/obj/item/paper::signfont]\"><i>[pen_signature(P, user)]</i></font>")
	t = replacetext(t, "\[field\]", "<span class=\"paper_field\"></span>")

	t = replacetext(t, "\[h1\]", "<H1>")
	t = replacetext(t, "\[/h1\]", "</H1>")
	t = replacetext(t, "\[h2\]", "<H2>")
	t = replacetext(t, "\[/h2\]", "</H2>")
	t = replacetext(t, "\[h3\]", "<H3>")
	t = replacetext(t, "\[/h3\]", "</H3>")
	t = replacetext(t, "\[tab\]", "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;")

	if(!iscrayon)
		t = replacetext(t, "\[*\]", "<li>")
		t = replacetext(t, "\[hr\]", "<HR>")
		t = replacetext(t, "\[small\]", "<font size = \"1\">")
		t = replacetext(t, "\[/small\]", "</font>")
		t = replacetext(t, "\[list\]", "<ul>")
		t = replacetext(t, "\[/list\]", "</ul>")
		t = replacetext(t, "\[table\]", "<table border=1 cellspacing=0 cellpadding=3 style='border: 1px solid black;'>")
		t = replacetext(t, "\[/table\]", "</td></tr></table>")
		t = replacetext(t, "\[grid\]", "<table>")
		t = replacetext(t, "\[/grid\]", "</td></tr></table>")
		t = replacetext(t, "\[row\]", "</td><tr>")
		t = replacetext(t, "\[/row\]", "")
		t = replacetext(t, "\[cell\]", "<td>")
		t = replacetext(t, "\[/cell\]", "")
		t = replacetext(t, "\[logo\]", "<img src=[REF('html/images/ntlogo.png')]>")
		t = replacetext(t, "\[talogo\]", "<img src=[REF('html/images/talonlogo.png')]>")
		t = replacetext(t, "\[sglogo\]", "<img src=[REF('html/images/sglogo.png')]>")
		t = replacetext(t, "\[trlogo\]", "<img src=[REF('html/images/trader.png')]>")
		t = replacetext(t, "\[pclogo\]", "<img src=[REF('html/images/pclogo.png')]>")

		t = "<font face=\"[/obj/item/paper::deffont]\" color=[P ? P.colour : "black"]>[t]</font>"
	else // If it is a crayon, and he still tries to use these, make them empty!
		t = replacetext(t, "\[*\]", "")
		t = replacetext(t, "\[hr\]", "")
		t = replacetext(t, "\[small\]", "")
		t = replacetext(t, "\[/small\]", "")
		t = replacetext(t, "\[list\]", "")
		t = replacetext(t, "\[/list\]", "")
		t = replacetext(t, "\[table\]", "")
		t = replacetext(t, "\[/table\]", "")
		t = replacetext(t, "\[row\]", "")
		t = replacetext(t, "\[cell\]", "")
		t = replacetext(t, "\[/cell\]", "")
		t = replacetext(t, "\[/row\]", "")
		t = replacetext(t, "\[logo\]", "")
		t = replacetext(t, "\[talogo\]", "")
		t = replacetext(t, "\[sglogo\]", "")

		t = "<font face=\"[/obj/item/paper::crayonfont]\" color=[P ? P.colour : "black"]><b>[t]</b></font>"
	return t

/// The signature P writes for user ([sign]).
/proc/pen_signature(obj/item/pen/P, mob/user)
	if(istype(P))
		return P.get_signature(user)
	return (user && user.real_name) ? user.real_name : "Anonymous"

/// The line a stamp or seal ring leaves on what it stamps: its own text, or who stamped it.
/// Shared by paper and the stamp_target capability.
/proc/stamp_mark_text(obj/item/S, noun = "paper")
	var/stamptext
	if(istype(S, /obj/item/stamp))
		var/obj/item/stamp/stamp = S
		stamptext = stamp.stamptext
	else if(istype(S, /obj/item/clothing/accessory/ring/seal))
		var/obj/item/clothing/accessory/ring/seal/seal = S
		stamptext = seal.stamptext
	return stamptext || "This [noun] has been stamped with the [S.name]."

/// Whether user can use stamp S: the clown's stamp only works for clowns, jesters and fools.
/proc/stamp_usable_by(obj/item/S, mob/user)
	if(!istype(S, /obj/item/stamp/clown))
		return TRUE
	var/title = user?.mind?.role_alt_title
	return title == JOB_CLOWN || title == JOB_ALT_JESTER || title == JOB_ALT_FOOL

/obj/item/paper/proc/paper_write_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = paper_write_apply(A)
	SStgui.update_uis(src)

/obj/item/paper/proc/paper_write_apply(datum/act/request/A)
	var/datum/prompt/text/paper_write_review/ask = A.answer
	return paper_write_stage(ask.paper_field_id, ask.paper_operator, ask.value, TRUE)

/datum/prompt/text/paper_write_review
	timeout = 0
	var/mob/paper_operator
	var/paper_operator_expected = FALSE
	var/paper_field_id

CAPABILITIES(/datum/prompt/text/paper_write_review)
	ref_one(nameof(paper_operator), /mob)

/datum/prompt/text/paper_write_review/prepare(datum/act/A)
	. = ..()
	var/mob/captured_paper_operator = paper_operator
	paper_operator_expected = !isnull(captured_paper_operator)
	rel_clear(src, nameof(paper_operator))
	if(captured_paper_operator && !QDELETED(captured_paper_operator))
		rel_set(src, nameof(paper_operator), captured_paper_operator)

/datum/prompt/text/paper_write_review/recheck_extra()
	if((paper_operator_expected && QDELETED(paper_operator)))
		return "gone"

/obj/item/paper/proc/paper_rename_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = paper_rename_apply(A)
	SStgui.update_uis(src)

/obj/item/paper/proc/paper_rename_apply(datum/act/request/A)
	var/datum/prompt/text/paper_rename_review/ask = A.answer
	return paper_rename_stage(ask.paper_operator, ask.paper_held, ask.value, TRUE)

/datum/prompt/text/paper_rename_review
	timeout = 0
	var/mob/paper_operator
	var/paper_operator_expected = FALSE
	var/obj/item/paper_held
	var/paper_held_expected = FALSE

CAPABILITIES(/datum/prompt/text/paper_rename_review)
	ref_one(nameof(paper_operator), /mob)
	ref_one(nameof(paper_held), /obj/item)

/datum/prompt/text/paper_rename_review/prepare(datum/act/A)
	. = ..()
	var/mob/captured_paper_operator = paper_operator
	paper_operator_expected = !isnull(captured_paper_operator)
	rel_clear(src, nameof(paper_operator))
	if(captured_paper_operator && !QDELETED(captured_paper_operator))
		rel_set(src, nameof(paper_operator), captured_paper_operator)
	var/obj/item/captured_paper_held = paper_held
	paper_held_expected = !isnull(captured_paper_held)
	rel_clear(src, nameof(paper_held))
	if(captured_paper_held && !QDELETED(captured_paper_held))
		rel_set(src, nameof(paper_held), captured_paper_held)

/datum/prompt/text/paper_rename_review/recheck_extra()
	if((paper_operator_expected && QDELETED(paper_operator)) || (paper_held_expected && QDELETED(paper_held)))
		return "gone"
