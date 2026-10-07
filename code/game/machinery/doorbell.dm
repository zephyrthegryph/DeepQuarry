////////////////////DOORBELL CHIME///////////////////////////////////////
/obj/machinery/doorbell_chime
	maintenance_flags = MACHINE_MAINT_PANEL
	name = "doorbell chime"
	desc = "Small wall-mounted chime triggered by a doorbell"
	icon = 'icons/obj/machines/doorbell_vr.dmi'
	icon_state = "dbchime-standby"
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	active_power_usage = 200
	anchored = TRUE
	flags = WALL_ITEM
	var/id_tag = null
	var/chime_sound = SFX_MACHINES_DOORBELL

/obj/machinery/doorbell_chime/proc/chime()
	if(!operable())
		return
	use_power(active_power_usage)
	playsound(src, chime_sound, 75)
	icon_state = "dbchime-active"
	set_light(2, 0.5, "#33FF33")
	visible_message("\The [src]'s light flashes.")
	after(src, 3 SECONDS, PROC_REF(chime_end))

/obj/machinery/doorbell_chime/proc/chime_end()
	set_light(0)

/// The look (the draw sweep: from its template and its layers).
/obj/machinery/doorbell_chime/draw(datum/look/look)
	..()
	look.state("dbchime-[id_tag ? "standby" : "red"]")
	if(panel_open == 1)
		look.overlay("dbchime-open")

CAPABILITIES(/obj/machinery/doorbell_chime)
	op("use_multitool", tool(TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(multitool_used)))
	op("fingerprint", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Touch"), then(TYPE_PROC_REF(/atom, op_fingerprint)))
	op("part_replacement", item(/obj/item/storage/part_replacer), priority(OP_PRIORITY_DEFAULT - 1), label("Replace parts"), then(TYPE_PROC_REF(/obj/machinery, op_part_replacement)))

/obj/machinery/doorbell_chime/proc/multitool_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(!panel_open)
		return OP_OK
	var/obj/item/multitool/multitool = tool
	if(multitool.connectable() && istype(multitool.connectable(), /obj/machinery/button/doorbell))
		var/obj/machinery/button/doorbell/button = multitool.connectable()
		keyed_set_id(src, nameof(id_tag), button.id) // joins the button's keyed chimes
		to_chat(user, span_notice("You upload the data from \the [tool]'s buffer."))
	return OP_OK

////////////////////DOORBELL CHIME CONSTRUCTION///////////////////////////////////////
// We want these to be constructable so more chimes can be added in departments.
/datum/frame/frame_types/doorbell_chime
	name = "Doorbell Chime"
	frame_class = "alarm"  // It isn't an alarm, but thats the construction flow we want.
	frame_size = 3
	frame_style = "wall"
	circuit = /obj/item/circuitboard/doorbell_chime
	icon_override = 'icons/obj/machines/doorbell_vr.dmi'
	x_offset = 32
	y_offset = 32

// Annoyingly we need to provide a circuit board even if never seen by players.
// Makes some sense, its how the frame code knows what to actually build. Alternative
// is to make building it a single-step process which is too quick I say.
// This links up the frame_type to the acutal machine to build. Never seen by players.
/obj/item/circuitboard/doorbell_chime
	build_path = /obj/machinery/doorbell_chime
	board_type = new /datum/frame/frame_types/doorbell_chime
	req_components = list()

////////////////////DOORBELL SWITCH///////////////////////////////////////

/obj/machinery/button/doorbell
	maintenance_flags = MACHINE_MAINT_PANEL
	name = "doorbell switch"
	desc = "A doorbell, press to chime."
	icon = 'icons/obj/machines/doorbell_vr.dmi'
	icon_state = "doorbell-standby"
	use_power = USE_POWER_OFF
	flags = WALL_ITEM

CAPABILITIES(/obj/machinery/button/doorbell)
	op("doorbell_press", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Press"), then(PROC_REF(interaction_press_impl)))
	op("doorbell_rename", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Touch"),
		asks(/datum/prompt/text/doorbell_label, fields = list("question" = computed(PROC_REF(rename_question)), "title" = computed(PROC_REF(rename_title)), "default" = computed(PROC_REF(rename_default)), "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "encode" = FALSE, "timeout" = 0), when = PROC_REF(rename_possible)), then(PROC_REF(rename_fingerprint)), then(PROC_REF(doorbell_named)))
	param(nameof(dir), pos = 1)
	param(nameof(building), pos = 2)
	op("use_multitool", tool(TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(multitool_used)))
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(wrench_used)))

/// A doorbell built on a wall (its constructor param).
/obj/machinery/button/doorbell/var/building = FALSE

// ALLOW(init/INSTANCE_STATE): a built doorbell sits on its wall, and every doorbell takes an id
/obj/machinery/button/doorbell/Initialize(mapload)
	. = ..()
	if(building)
		pixel_x = (dir & 3)? 0 : (dir == 4 ? -32 : 32)
		pixel_y = (dir & 3)? (dir ==1 ? -27 : 27) : 0
	if (!id)
		assign_uid()
		set_id(num2text(uid))

/// The look (the draw sweep: from its template).
/obj/machinery/button/doorbell/draw(datum/look/look)
	..()
	look.state("doorbell-[operable() ? "standby" : "off"]")


/// Chimes whose id_tag matches our id (keyed).
/obj/machinery/button/doorbell/var/list/obj/machinery/doorbell_chime/chimes
/obj/machinery/button/doorbell/relations()
	. = ..()
	. += rel_many(nameof(chimes), keyed = nameof(id), keyed_target = /obj/machinery/doorbell_chime)
/obj/machinery/doorbell_chime/relations()
	. = ..()
	. += rel_key(nameof(id_tag))

/obj/machinery/button/doorbell/proc/interaction_press_impl(datum/act/op/A)
	var/mob/user = A.actor
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	use_power(5)
	flick("doorbell-active", src)

	for(var/obj/machinery/doorbell_chime/M as anything in chimes)
		M.chime()
	return TRUE

/obj/machinery/button/doorbell/proc/rename_fingerprint(datum/act/op/A)
	if(istype(A.answer, /datum/prompt/text/doorbell_label))
		return OP_OK
	add_fingerprint(A.actor)
	return OP_OK

/obj/machinery/button/doorbell/proc/rename_possible(datum/act/op/A)
	return panel_open && istype(A.held, /obj/item/pen)

/obj/machinery/button/doorbell/proc/rename_question(datum/act/op/A)
	return "Enter the name for \the [src]."

/obj/machinery/button/doorbell/proc/rename_default(datum/act/op/A)
	return initial(name)

/obj/machinery/button/doorbell/proc/doorbell_named(datum/act/op/A)
	if(!A.answer)
		return OP_OK
	var/t = sanitizeSafe(A.answer.value, MAX_NAME_LEN)
	if(t && panel_open)
		name = t
	return OP_OK

/obj/machinery/button/doorbell/proc/multitool_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(!panel_open)
		return OP_OK
	var/obj/item/multitool/M = tool
	rel_set(M, nameof(M.connectable), src)
	to_chat(user, span_notice("You save the data in \the [M]'s buffer."))
	return OP_OK

/obj/machinery/button/doorbell/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You start to unwrench \the [src]."))
	play_sfx(src, SFX_ITEMS_RATCHET)
	task_timed(user, 15, target = src, receiver = src, on_done = PROC_REF(wrench_act_timed_done), done_args = list(user))
	return OP_OK

/obj/machinery/button/doorbell/proc/wrench_act_timed_done(mob/user)
	if(QDELETED(src))
		return
	to_chat(user, span_notice("You unwrench \the [src]."))
	replace_with(src, /obj/item/frame/doorbell)
	return ITEM_INTERACT_SUCCESS

////////////////////DOORBELL SWITCH CONSTRUCTION///////////////////////////////////////
// Right now they are very simple to construct, just throw them up on the wall

/obj/item/frame/doorbell
	name = "doorbell switch frame"
	desc = "Used for building doorbell switches."
	icon = 'icons/obj/machines/doorbell_vr.dmi'
	icon_state = "doorbell-off"
	refund_amt = 4
	refund_type = /obj/item/stack/material/wood
	build_machine_type = /obj/machinery/button/doorbell

/obj/machinery/button/doorbell/proc/rename_title(datum/act/op/A)
	return name

/// Opening the rename records the touch even when the visitor cancels the question.
/datum/prompt/text/doorbell_label/prepare(datum/act/A)
	..()
	var/obj/machinery/button/doorbell/bell = owner
	if(istype(bell))
		bell.add_fingerprint(answerer)
