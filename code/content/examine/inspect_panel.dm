/**
 * The Inspect panel: examining something fills the "Inspect" tab of the stat panel (the right side panel) and switches
 * to it, instead of printing the examine text to chat. A player who prefers chat sets the "examine in chat"
 * preference (/datum/preference/toggle/examine_in_chat); nothing is lost either way.
 *
 * One panel per client (the client owns it). The data goes to the stat panel as an "update_inspect" message
 * (tgui-panel/statpanel); its buttons come back as "Inspect-Act" messages (/client/on_stat_panel_message). The target's
 * examine() text is the description; types with structure add it through inspect_sections() (a human's worn
 * items and body status) and the portrait. The last few targets stay as tabs; a worn item in the list inspects
 * that item.
 */
/// How many targets stay as tabs.
#define INSPECT_PANEL_RECENT_MAX 5
/// The way the portrait faces.
#define INSPECT_PORTRAIT_DIR NORTH

/datum/inspect_panel
	/// The client using the panel: a one-sided back view (the client owns the panel).
	var/client/owner
	/// What the panel shows: a relation view.
	var/atom/target
	/// The target's portrait as a base64 PNG (composited off-thread when it is examined), or null while it renders.
	var/portrait
	/// Bumped for every portrait request; only the newest request's result is applied.
	var/portrait_generation = 0
	/// Portrait renders still in flight (owned /datum/inspect_portrait_job).
	var/list/portrait_jobs
	/// The examine text lines, as safe html (what examine() said when the target was last examined).
	var/list/description
	/// Extra labelled sections, each list(title, text): mechanics, fluff, antag, interaction notes.
	var/list/notes
	/// Handles of the last targets examined, newest first (handles, so a deleted target just drops out).
	var/list/recent
	/// Is the target's full flavor text open?
	var/show_flavor = FALSE

/datum/inspect_panel/New(client/owner)
	rel_set(src, nameof(owner), owner)

/client/var/tmp/datum/inspect_panel/inspect_panel

CAPABILITIES(/datum/inspect_panel)
	ref_one(nameof(target))
	owns_many(nameof(portrait_jobs))
	ref_one(nameof(owner))

/// The client using the panel.
/datum/inspect_panel/proc/owner() as /client
	return owner

/datum/inspect_panel/proc/target()
	return QDELETED(target) ? null : target

/// `new_target`, its text and its portrait, now shown (and put first in the tabs), and the stat panel switched to the Inspect tab.
/datum/inspect_panel/proc/show(mob/user, atom/new_target, list/new_description, list/new_notes)
	if(new_target != target())
		set_show_flavor(FALSE)
		set_portrait(null)
	rel_set(src, nameof(/datum/inspect_panel::target), new_target)
	set_description(new_description)
	set_notes(new_notes)
	request_portrait(new_target, INSPECT_PORTRAIT_DIR)
	var/list/handles = list(handle_of(new_target))
	for(var/handle in recent)
		if(handle != handles[1] && handle_get(handle))
			handles += handle
	set_recent(handles.Copy(1, min(length(handles), INSPECT_PANEL_RECENT_MAX) + 1))
	log_input("Input: [key_name(user)] inspected [new_target] ([new_target.type]) in the Inspect tab.")
	push(TRUE)

/// Sends the panel's data to the client's stat panel; `switch_tab` also selects the Inspect tab there.
/datum/inspect_panel/proc/push(switch_tab = FALSE)
	var/client/player = owner()
	if(!player?.stat_panel?.is_ready())
		log_input("Input: Inspect tab data for [player ? key_name(player) : "nobody"] not sent (stat panel not ready).")
		return
	player.stat_panel.send_message("update_inspect", list("data" = payload(player.mob), "switch" = switch_tab ? TRUE : FALSE))

/// The stat panel's message for this panel (a button in the Inspect tab): `action` and its arguments.
/datum/inspect_panel/proc/act(action, list/params)
	var/mob/user = owner()?.mob
	if(!user || !target())
		return FALSE
	switch(action)
		if("inspect")
			return act_inspect(user, params["ref"])
		if("select")
			return act_select(user, params["ref"])
		if("flavor")
			set_show_flavor(!show_flavor)
			push()
			return TRUE
		if("ooc")
			return act_ooc(user)
		if("primary")
			return istext(params["id"]) && run_chosen_op(user, target(), params["id"])
	log_input("Input: [key_name(user)] sent unknown Inspect tab action '[action]'.")
	return FALSE

/// A worn item of the target was clicked: inspect it. Only what the panel itself lists qualifies.
/datum/inspect_panel/proc/act_inspect(mob/user, ref)
	var/atom/item = istext(ref) ? handle_get(ref) : null
	if(!istype(item) || QDELETED(item))
		return FALSE
	var/listed = FALSE
	for(var/list/row as anything in target().inspect_sections(user)["worn"])
		if(row["ref"] == handle_of(item))
			listed = TRUE
			break
	if(!listed)
		return FALSE
	user.examinate(item)
	return TRUE

/// A tab was clicked: examine that target again.
/datum/inspect_panel/proc/act_select(mob/user, ref)
	var/atom/picked = istext(ref) ? handle_get(ref) : null
	if(!istype(picked) || QDELETED(picked) || !(handle_of(picked) in recent))
		return FALSE
	user.examinate(picked)
	return TRUE

/datum/inspect_panel/proc/act_ooc(mob/user)
	var/atom/shown = target()
	if(!isliving(shown))
		return FALSE
	var/mob/living/subject = shown
	subject.do_examine_ooc(user)
	return TRUE

/// The panel's data for the stat panel.
/datum/inspect_panel/proc/payload(mob/user)
	var/atom/shown = target()
	if(!shown)
		return null
	var/list/tabs = list()
	for(var/handle in recent)
		var/atom/tab_target = handle_get(handle)
		if(tab_target && !QDELETED(tab_target))
			tabs += list(list("ref" = handle, "name" = capitalize(tab_target.name), "active" = tab_target == shown))
	var/list/extra = list("tabs" = tabs, "portrait" = portrait, "show_flavor" = show_flavor)
	return inspect_panel_data(user, shown, description, notes) + extra

/// What the panel shows for `target` as seen by `user`: name, kind/role/distance for the subtitle, the description
/// lines and notes it was given, the structured sections the target declares (worn, body), flavor, OOC and the
/// first op the user can do. Split out so tests can read it.
/proc/inspect_panel_data(mob/user, atom/target, list/description, list/notes)
	var/list/data = list(
		"target" = capitalize(target.name),
		"kind" = target.inspect_kind(user),
		"role" = target.inspect_role(),
		"distance" = interaction_menu_distance(user, target),
		"description" = description || list(),
		"notes" = notes || list(),
		"worn" = list(),
		"body" = list(),
		"flavor" = null,
		"has_ooc" = FALSE,
		"primary" = null,
	)
	var/list/sections = target.inspect_sections(user)
	for(var/section in sections)
		data[section] = sections[section]
	if(ismob(target))
		var/mob/subject = target
		if(subject.bio.flavor_text)
			data["flavor"] = dq_render_flavor(replacetext(subject.bio.flavor_text, "\n", "<br>"))
	if(isliving(target))
		var/mob/living/subject = target
		data["has_ooc"] = subject.identity().ooc_notes ? TRUE : FALSE
	for(var/list/row as anything in interaction_menu_data(user, target)["available"])
		data["primary"] = list("id" = row["id"], "name" = row["name"])
		break
	return data

/// Asks for the portrait of `shown` facing `facing`. The picture is composited by rust-g on a worker thread (the server never
/// flattens), so the panel keeps its current picture (cleared when the target changed) until the new one lands.
/datum/inspect_panel/proc/request_portrait(atom/shown, facing)
	var/generation = portrait_generation + 1
	set_portrait_generation(generation)
	if(!shown)
		set_portrait(null)
		return
	var/started = world.timeofday
	var/list/sprite = inspect_portrait_sprite(shown, facing)
	if(!sprite)
		// Nothing the compositor can express exactly: the target's own icon, no worn overlays. Never a flatten.
		set_portrait(inspect_portrait_plain(shown, facing))
		log_input("Input: inspect portrait of [shown] ([shown.type]) used the plain icon (unsupported appearance).")
		return
	var/list/started_job = dq_preview_start_job(sprite, "inspect")
	var/job_id = started_job[1]
	var/sheet_name = started_job[2]
	var/datum/inspect_portrait_job/job = new
	job.job_id = job_id
	job.sheet_name = sheet_name
	job.generation = generation
	job.queued_in = world.timeofday - started
	job.described = "[shown] ([shown.type])"
	COOLDOWN_START(job, timeout_at, 10 SECONDS)
	rel_set(job, nameof(job.panel), src)
	rel_add(src, nameof(/datum/inspect_panel::portrait_jobs), job)
	job.set_polling(TRUE)

/// An in-flight portrait render, owned by the panel that asked for it.
/datum/inspect_portrait_job
	/// The panel it is for (a relation view)
	var/datum/inspect_panel/panel
	var/job_id
	var/sheet_name
	var/generation
	/// Deciseconds the server spent describing the appearance (the only cost it pays), for the trace.
	var/queued_in
	var/described
	COOLDOWN_DECLARE(timeout_at)
	var/polling = FALSE

CAPABILITIES(/datum/inspect_portrait_job)
	every(0.25 SECONDS, then(PROC_REF(poll_step)), when = nameof(polling))
	ref_one(nameof(panel))

/datum/inspect_portrait_job/New()
	..()
	lifecycle_decls_init(src) // a non-atom has no materialize

/// One poll of the render: applies the picture when it landed, drops it when stale, gives up on the timeout.
/datum/inspect_portrait_job/proc/poll_step(datum/act/timer/tick)
	var/output = rustg_iconforge_check(job_id)
	var/timed_out = ELAPSED(src, timeout_at, CLOCK_WORLD) > 0
	if(output == RUSTG_JOB_NO_RESULTS_YET && !timed_out)
		return
	set_polling(FALSE)
	var/png_path = output == RUSTG_JOB_NO_RESULTS_YET ? null : dq_preview_job_png(sheet_name, output)
	var/datum/inspect_panel/owner_panel = panel
	if(owner_panel && png_path && generation == owner_panel.portrait_generation)
		owner_panel.set_portrait(icon2base64(icon(file(png_path))))
		owner_panel.push()
		log_input("Input: inspect portrait of [described] composited off-thread (server cost [queued_in] ds to describe).")
	else if(owner_panel && generation == owner_panel.portrait_generation)
		log_input("Input: inspect portrait of [described] failed or timed out ([output]).")
	if(png_path)
		fdel(png_path)
	if(owner_panel)
		own_remove(owner_panel, nameof(/datum/inspect_panel::portrait_jobs), src)

/// The compositor description of `shown` facing `facing`, worn clothing and overlays included (the same tree getFlatIcon walks,
/// described rather than drawn), or null when it can't be expressed exactly. (examine_icon() is not used: its force_south
/// flatten drops a human's worn overlays.)
/proc/inspect_portrait_sprite(atom/shown, facing)
	var/datum/dq_preview_flattener/flattener = new
	var/list/flat = flattener.flatten(shown, facing)
	if(!flat || flattener.unsupported)
		return null
	return flat[1]

/// The target's own icon facing `facing`, without overlays, as a base64 PNG, or null.
/proc/inspect_portrait_plain(atom/shown, facing)
	if(!shown?.icon)
		return null
	var/icon/picture = icon(shown.icon, shown.icon_state, facing)
	if(!isicon(picture))
		return null
	return icon2base64(picture)

/// Examine html made safe for the panel: icon images and links are dropped (they only work in chat). Returns
/// list(panel lines, lines that held a link), so a caller can still print the link lines to chat.
/proc/inspect_split_lines(list/lines)
	var/static/regex/link_open = regex("<a \[^>]*>", "ig")
	var/static/regex/link_close = regex("</a>", "ig")
	var/static/regex/picture = regex("<img\[^>]*>", "ig")
	var/list/panel_lines = list()
	var/list/chat_lines = list()
	for(var/line in lines)
		if(!istext(line) || !length(line))
			continue
		if(findtext(line, "<a "))
			chat_lines += line
		var/clean = picture.Replace(line, "")
		clean = link_open.Replace(clean, "<span>")
		clean = link_close.Replace(clean, "</span>")
		panel_lines += clean
	return list(panel_lines, chat_lines)

/// Whether this mob gets examines in the panel (a client that has not asked for chat) rather than as chat text.
/mob/proc/examine_to_panel()
	if(!client)
		return FALSE
	return !client.prefs?.read_preference(/datum/preference/toggle/examine_in_chat)

/// Opens (or updates) this mob's Inspect panel on `A`. Links the panel cannot carry are printed to chat.
/mob/proc/examine_in_panel(atom/A)
	var/client/player = client
	if(!player || !A)
		return
	if(!player.inspect_panel)
		rel_set(player, nameof(/client::inspect_panel), new /datum/inspect_panel(player))
	var/list/lines = A.inspect_describe(src)
	if(!length(lines))
		lines = list("You were unable to examine that. Tell a developer!")
	var/list/split = inspect_split_lines(lines)
	var/list/chat_lines = split[2] + A.inspect_chat_lines(src)
	player.inspect_panel.show(src, A, split[1], inspect_notes(A, src))
	to_chat(src, span_infoplain("You examine [A]."))
	if(length(chat_lines))
		to_chat(src, span_infoplain(jointext(chat_lines, "<br>")))

/// The mechanics, fluff, antag and interaction notes of `A` as list(title, text) rows (what verbose chat put in dropdowns).
/proc/inspect_notes(atom/A, mob/viewer)
	var/list/rows = list()
	var/mechanics = A.get_mechanics_info()
	if(mechanics)
		rows += list(list("Information", "[mechanics]"))
	var/fluff = A.get_description_fluff()
	if(fluff)
		rows += list(list("Flavor", "[fluff]"))
	var/antag = viewer.antag_check() ? A.get_description_antag() : null
	if(antag)
		rows += list(list("Antag information", "[antag]"))
	var/list/interaction = A.get_description_interaction(viewer)
	if(LAZYLEN(interaction))
		rows += list(list("Interaction", jointext(interaction, "<br>")))
	return rows

/// The first half of the subtitle: what sort of thing this is.
/atom/proc/inspect_kind(mob/user)
	return interaction_menu_role(src)

/// The second half: the role a mob holds, else null.
/atom/proc/inspect_role()
	return null

/mob/inspect_role()
	return mind?.assigned_role

/// The examine lines the panel shows as its description (examine()'s own).
/atom/proc/inspect_describe(mob/user)
	return examine(user)

/// Lines to print to chat even when the panel is on (for example record links a panel cannot carry).
/atom/proc/inspect_chat_lines(mob/user)
	return list()

/// Structured sections for the panel: "worn" rows list(slot, name, ref) and "body" chips list(label, state, tone).
/atom/proc/inspect_sections(mob/user)
	return list()

/mob/living/carbon/human/inspect_kind(mob/user)
	var/list/coverage = examine_coverage()
	if((coverage[1] & EXAMINE_SKIPJUMPSUIT) && (coverage[2] & EXAMINE_SKIPFACE))
		return "Human"
	return bio.custom_species || species.name

/mob/living/carbon/human/inspect_describe(mob/user)
	if(alpha <= EFFECTIVE_INVIS)
		return ..()
	var/list/coverage = examine_coverage()
	var/list/hidden = examine_hidden_limbs(coverage[2])
	. = list()
	. += examine_status_lines(user, hidden)
	. += examine_diagnosis_lines()
	var/current_pose = STATE_GET(src, posing, pose)
	if(current_pose)
		. += "[p_They()] [current_pose]"

/mob/living/carbon/human/inspect_chat_lines(mob/user)
	if(alpha <= EFFECTIVE_INVIS)
		return list()
	return examine_record_lines(user)

/mob/living/carbon/human/inspect_sections(mob/user)
	if(alpha <= EFFECTIVE_INVIS)
		return list()
	var/list/coverage = examine_coverage()
	return list("worn" = inspect_worn_rows(coverage[1]), "body" = inspect_body_chips(coverage[2]))

/// The worn and held items that examine would list, as list(slot label, item name, item handle).
/mob/living/carbon/human/proc/inspect_worn_rows(skip_gear)
	var/static/list/slots = list(
		list(SLOT_ID_UNIFORM, "uniform", EXAMINE_SKIPJUMPSUIT),
		list(SLOT_ID_SUIT, "suit", 0),
		list(SLOT_ID_SUIT_STORAGE, "suit storage", EXAMINE_SKIPSUITSTORAGE),
		list(SLOT_ID_HEAD, "head", EXAMINE_SKIPHELMET),
		list(SLOT_ID_MASK, "mask", EXAMINE_SKIPMASK),
		list(SLOT_ID_EYES, "eyes", EXAMINE_SKIPEYEWEAR),
		list(SLOT_ID_EAR_L, "left ear", EXAMINE_SKIPEARS),
		list(SLOT_ID_EAR_R, "right ear", EXAMINE_SKIPEARS),
		list(SLOT_ID_GLOVES, "gloves", EXAMINE_SKIPGLOVES),
		list(SLOT_ID_SHOES, "shoes", EXAMINE_SKIPSHOES),
		list(SLOT_ID_BACK, "back", EXAMINE_SKIPBACKPACK),
		list(SLOT_ID_BELT, "belt", EXAMINE_SKIPBELT),
		list(SLOT_ID_ID, "id", 0),
		list(SLOT_ID_HAND_L, "left hand", 0),
		list(SLOT_ID_HAND_R, "right hand", 0),
		list(SLOT_ID_HANDCUFFED, "restraint", 0),
	)
	. = list()
	for(var/list/slot as anything in slots)
		var/obj/item/I = get_equipped_item(slot[1])
		if(!I || (skip_gear & slot[3]) || !rules_of(I).show_examine)
			continue
		. += list(list("slot" = slot[2], "name" = I.name, "ref" = handle_of(I)))

/// Visible limb state as chips: missing, prosthetic, wounded, broken, bleeding, with an implant showing. Tone is
/// "danger", "warning" or "info".
/mob/living/carbon/human/proc/inspect_body_chips(skip_body)
	var/list/hidden = examine_hidden_limbs(skip_body)
	var/looks_synth = looksSynthetic()
	. = list()
	for(var/organ_tag in species.has_limbs)
		var/list/organ_data = species.has_limbs[organ_tag]
		var/obj/item/organ/external/E = organs_by_name[organ_tag]
		if(!E || E.is_stump())
			. += list(list("label" = uppertext("[organ_data["descriptor"]]"), "state" = "MISSING", "tone" = "danger"))
	for(var/obj/item/organ/external/temp in organs)
		if(hidden[temp.organ_tag])
			continue
		var/label = uppertext("[temp.name]")
		if(temp.status & ORGAN_DESTROYED)
			. += list(list("label" = label, "state" = "MISSING", "tone" = "danger"))
			continue
		if(!looks_synth && temp.robotic == ORGAN_ROBOT)
			. += list(list("label" = label, "state" = "PROSTHETIC", "tone" = "info"))
		if(length(temp.get_wounds()) || temp.open)
			. += list(list("label" = label, "state" = "WOUNDED", "tone" = "warning"))
		if(temp.dislocated == 1)
			. += list(list("label" = label, "state" = "DISLOCATED", "tone" = "warning"))
		if(temp.get_trauma() > temp.min_broken_damage || temp.is_fractured() || (temp.status & ORGAN_MUTATED))
			. += list(list("label" = label, "state" = "BROKEN", "tone" = "warning"))
		if(temp.status & ORGAN_DEAD)
			. += list(list("label" = label, "state" = "NECROTIC", "tone" = "danger"))
		if(temp.status & ORGAN_BLEEDING)
			. += list(list("label" = label, "state" = "BLEEDING", "tone" = "danger"))
	for(var/implant in get_visible_implants(0))
		. += list(list("label" = uppertext("[implant]"), "state" = "EMBEDDED", "tone" = "danger"))

#undef INSPECT_PORTRAIT_DIR
#undef INSPECT_PANEL_RECENT_MAX
