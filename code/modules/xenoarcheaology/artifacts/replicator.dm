/obj/machinery/replicator
	name = "alien machine"
	desc = "It's some kind of pod with strange wires and gadgets all over it."
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "borgcharger0(old)"
	density = TRUE

	idle_power_usage = 100
	active_power_usage = 1000
	use_power = USE_POWER_IDLE

	var/spawn_progress_time = 0
	var/max_spawn_time = 50
	EXPIRY_DECLARE(last_process_time)

	var/list/construction
	var/list/tgui_construction
	var/list/spawning_types = list() // ALLOW(instance_list): d: filled in New() with the replicator's output table
	var/list/stored_materials = list() // ALLOW(instance_list): d: consumed with pop() in step with spawning_types

	var/fail_message

/obj/machinery/replicator/Initialize(mapload)
	. = ..()

	var/static/list/viables = list(
	/obj/item/roller,
	/obj/structure/closet/crate,
	/obj/structure/closet/acloset,
	/mob/living/simple_mob/mechanical/viscerator,
	/mob/living/simple_mob/mechanical/hivebot,
	/obj/item/analyzer,
	/obj/item/camera,
	/obj/item/flash,
	/obj/item/flashlight,
	/obj/item/healthanalyzer,
	/obj/item/multitool,
	/obj/item/paicard,
	/obj/item/radio,
	/obj/item/radio/headset,
	/obj/item/radio/beacon,
	/obj/item/autopsy_scanner,
	/obj/item/bikehorn,
	/obj/item/surgical/bonesetter,
	/obj/item/material/knife/butch,
	/obj/item/clothing/suit/caution,
	/obj/item/clothing/head/cone,
	/obj/item/tool/crowbar,
	/obj/item/clipboard,
	/obj/item/cell,
	/obj/item/surgical/circular_saw,
	/obj/item/material/knife/machete/hatchet,
	/obj/item/handcuffs,
	/obj/item/surgical/hemostat,
	/obj/item/material/knife,
	/obj/item/flame/lighter,
	/obj/item/light/bulb,
	/obj/item/light/tube,
	/obj/item/pickaxe,
	/obj/item/shovel,
	/obj/item/weldingtool,
	/obj/item/tool/wirecutters,
	/obj/item/tool/wrench,
	/obj/item/tool/screwdriver,
	/obj/item/grenade/chem_grenade/cleaner,
	/obj/item/grenade/chem_grenade/metalfoam)

// /mob/living/simple_mob/mimic/crate, // // AI TEMPORARY REMOVAL, REPLACE BACK IN LIST WHEN FIXED
	var/quantity = rand(5, 15)
	for(var/i=0, i<quantity, i++)
		var/background = pick("yellow","purple","green","blue","red","orange","white")
		var/static/list/icons = list(
			"round" = "circle",
			"square" = "square",
			"diamond" = "gem",
			"heart" = "heart",
			"dog" = "dog",
			"human" = "user",
		)
		var/icon = pick(icons)
		var/static/list/colors = list(
			"toggle" = "pink",
			"switch" = "yellow",
			"lever" = "red",
			"button" = "black",
			"pad" = "white",
			"hole" = "black",
		)
		var/color = pick(colors)
		var/button_desc = "a [background], [icon] shaped [color]"
		var/type = pick(viables)
		viables.Remove(type)
		LAZYSET(construction, button_desc, type)
		LAZYINITLIST(tgui_construction); tgui_construction.Add(list(list(
			"key" = button_desc,
			"background" = background,
			"icon" = icons[icon],
			"foreground" = colors[color],
		)))

	fail_message = span_notice("[icon2html(src,viewers(src))] a [pick("loud","soft","sinister","eery","triumphant","depressing","cheerful","angry")] \
		[pick("horn","beep","bing","bleep","blat","honk","hrumph","ding")] sounds and a \
		[pick("yellow","purple","green","blue","red","orange","white")] \
		[pick("light","dial","meter","window","protrusion","knob","antenna","swirly thing")] \
		[pick("swirls","flashes","whirrs","goes schwing","blinks","flickers","strobes","lights up")] on the \
		[pick("front","side","top","bottom","rear","inside")] of [src]. A [pick("slot","funnel","chute","tube")] opens up in the \
		[pick("front","side","top","bottom","rear","inside")].")

/obj/machinery/replicator/proc/work_step(datum/act/timer/A)
	// Works while something is queued and it has power; a queue (its UI) or power wakes it.
	if(!spawning_types.len)
		last_process_time = 0
		return PROCESS_KILL
	if(!powered())
		last_process_time = 0
		return work_wait_for_power(src)
	if(!last_process_time)
		EXPIRY_STAMP(src, last_process_time, CLOCK_WORLD)
	if(spawning_types.len && powered())
		spawn_progress_time += world.time - last_process_time
		if(spawn_progress_time > max_spawn_time)
			src.visible_message(span_notice("[icon2html(src,viewers(src))] [src] pings!"))

			var/obj/source_material = pop(stored_materials)
			var/spawn_type = pop(spawning_types)
			var/obj/spawned_obj = new spawn_type(src.loc)
			if(source_material)
				if(length(source_material.name) < MAX_MESSAGE_LEN)
					spawned_obj.name = "[source_material] " +  spawned_obj.name
				if(length(source_material.desc) < MAX_MESSAGE_LEN * 2)
					if(spawned_obj.desc)
						spawned_obj.desc += " It is made of [source_material]."
					else
						spawned_obj.desc = "It is made of [source_material]."
				spent(source_material)

			spawn_progress_time = 0
			max_spawn_time = rand(30,100)

			if(!spawning_types.len || !length(stored_materials))
				set_use_power(USE_POWER_IDLE)
				icon_state = "borgcharger0(old)"

		else if(prob(5))
			src.visible_message(span_notice("[icon2html(src,viewers(src))] [src] [pick("clicks","whizzes","whirrs","whooshes","clanks","clongs","clonks","bangs")]."))

	EXPIRY_STAMP(src, last_process_time, CLOCK_WORLD)

CAPABILITIES(/obj/machinery/replicator)
	started_work(step = PROC_REF(work_step))
	interface("XenoarchReplicator")
	without("ui_open")
	op("construct", ui_act("construct", arg("key", schema_text(4096))), then(PROC_REF(ui_act_construct)))
	op("insert", item(/obj/item), label("Insert"), needs(req(PROC_REF(can_insert_holds), because = PROC_REF(can_insert_refusal))), then(PROC_REF(insert_op)))

/// /obj/machinery/replicator's window data.
/obj/machinery/replicator/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["tgui_construction"] = (tgui_construction || list())
	return data

/obj/machinery/replicator/proc/ui_act_construct(datum/act/op/A, key_arg)
	var/key = key_arg
	if(key in construction)
		if(LAZYLEN(stored_materials) > LAZYLEN(spawning_types))
			if(LAZYLEN(spawning_types))
				visible_message(span_notice("[icon2html(src,viewers(src))] a [pick("light","dial","display","meter","pad")] on [src]'s front [pick("blinks","flashes")] [pick("red","yellow","blue","orange","purple","green","white")]."))
			else
				visible_message(span_notice("[icon2html(src,viewers(src))] [src]'s front compartment slides shut."))
			spawning_types.Add(LAZYACCESS(construction, key))
			spawn_progress_time = 0
			set_use_power(USE_POWER_ACTIVE)
			icon_state = "borgcharger1(old)"
		else
			visible_message(fail_message)

/// Requirement: no armblades, no grabs, nothing the user can't let go of.
/obj/machinery/replicator/proc/can_insert(mob/living/user, atom/target, obj/item/held)
	if(!istype(held) || !held.canremove || !user.canUnEquip(held))
		return "you cannot put [held] into the machine"
	return TRUE

/// The insert op: it passes the actor and the item to interaction_insert(), which the vore and clothing replicators override.
/obj/machinery/replicator/proc/insert_op(datum/act/op/A)
	interaction_insert(A.actor, A.held)
	return OP_OK

/// can_insert() reads TRUE to allow, or a reason text.
/obj/machinery/replicator/proc/can_insert_holds(datum/act/op/A)
	return read_once(can_insert(A.actor, src, A.held) == TRUE)

/obj/machinery/replicator/proc/can_insert_refusal(datum/act/op/A)
	var/why = read_once(can_insert(A.actor, src, A.held))
	return istext(why) ? why : null

/obj/machinery/replicator/proc/interaction_insert(mob/living/user, obj/item/W)
	user.drop_item()
	W.forceMove(src)
	rel_add(src, nameof(stored_materials), W)
	act_message(user, src, others = span_notice(span_bold("%U%") + " inserts %I% into %T%."), item = W)
	return TRUE



//////////////////////////////
//////VORE-MOB REPLICATOR/////
//////////////////////////////
/obj/machinery/replicator/vore
	name = "alien machine"
	desc = "It's some kind of pod with strange wires and gadgets all over it. This one appears to have a humanoid shaped slot as an input. It has depictions of various creatures on the buttons." //Explain to the user that it turns people into mobs.
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "borgcharger0(old)"
	var/quantity = 18 //This needs to be replaced with a GUI that lets you select the item you want.
	var/list/created_mobs
	var/list/tgui_vore_selection
	var/list/viable_mobs = list( // ALLOW(instance_list): d: edited in place per instance (1 writers)
	/mob/living/simple_mob/animal/passive/fox,
	/mob/living/simple_mob/animal/passive/cow,
	/mob/living/simple_mob/animal/passive/chicken,
	/mob/living/simple_mob/animal/passive/opossum,
	/mob/living/simple_mob/animal/passive/mouse,
	/mob/living/simple_mob/animal/passive/mothroach,
	/mob/living/simple_mob/vore/rabbit,
	/mob/living/simple_mob/animal/goat,
	/mob/living/simple_mob/animal/sif/tymisian,
	/mob/living/simple_mob/vore/wolf/direwolf,
	/mob/living/simple_mob/vore/otie/friendly,
	/mob/living/simple_mob/vore/alienanimals/catslug,
	/mob/living/simple_mob/vore/alienanimals/teppi,
	/mob/living/simple_mob/vore/fennec,
	/mob/living/simple_mob/vore/xeno_defanged,
	/mob/living/simple_mob/vore/redpanda/fae,
	/mob/living/simple_mob/vore/aggressive/rat,
	/mob/living/simple_mob/vore/aggressive/panther,
	/mob/living/simple_mob/vore/aggressive/frog
	)
	//Mostly friendly mobs, but occasionally some dangerous ones.
	//So if xenoarch isn't careful and is just shoving items willy-nilly without taking the proper precautions they can end up in a bit of trouble!


// ALLOW(init/INSTANCE_STATE): rolls its control buttons and what each one makes
/obj/machinery/replicator/vore/Initialize(mapload) //This replicator turns people into mobs!
	. = ..() //TODO: Someone can replace the 'alien' interface with something neater sometime. It is simply out of my abilities at the current moment.

	for(var/i=0, i<quantity, i++)
		var/background = pick("yellow","purple","green","blue","red","orange","white")
		var/static/list/icons = list(
			"round" = "circle",
			"square" = "square",
			"diamond" = "gem",
			"heart" = "heart",
			"dog" = "dog",
			"human" = "user",
		)
		var/icon = pick(icons)
		var/static/list/colors = list(
			"toggle" = "pink",
			"switch" = "yellow",
			"lever" = "red",
			"button" = "black",
			"pad" = "white",
			"hole" = "black",
		)
		var/color = pick(colors)
		var/button_desc = "a [background], [icon] shaped [color]"
		var/generated_mob = pick(viable_mobs)
		viable_mobs.Remove(generated_mob)
		LAZYSET(created_mobs, button_desc, generated_mob)
		LAZYINITLIST(tgui_vore_selection); tgui_vore_selection.Add(list(list(
			"key" = button_desc,
			"background" = background,
			"icon" = icons[icon],
			"foreground" = colors[color],
		)))

/obj/machinery/replicator/vore/work_step(datum/act/timer/A)
	// Works while something is queued and it has power; a queue (its UI) or power wakes it.
	if(!spawning_types.len)
		last_process_time = 0
		return PROCESS_KILL
	if(!powered())
		last_process_time = 0
		return work_wait_for_power(src)
	if(!last_process_time)
		EXPIRY_STAMP(src, last_process_time, CLOCK_WORLD)
	if(spawning_types.len && powered())
		spawn_progress_time += world.time - last_process_time
		if(spawn_progress_time > max_spawn_time)
			src.visible_message(span_notice("[icon2html(src,viewers(src))] [src] pings!"))

			var/obj/source_material = pop(stored_materials)
			var/spawn_type = pop(spawning_types)
			var/mob/living/simple_mob/new_mob = new spawn_type(src.loc) //The MOB that's spawned in.

			if(source_material)
				if(length(source_material.name) < MAX_MESSAGE_LEN)
					new_mob.name = "[source_material] " +  new_mob.name
				if(length(source_material.desc) < MAX_MESSAGE_LEN * 2)
					if(new_mob.desc)
						new_mob.desc += " It is made of [source_material]."
					else
						new_mob.desc = "It is made of [source_material]."
			//Did they use an item? If so, we're done here.

			//Did they put a micro in it?
			if(istype(source_material,/obj/item/holder/micro))
				var/obj/item/holder/micro/micro_holder = source_material
				var/mob/mob_to_be_changed = micro_holder.held_mob
				var/mob/living/M = mob_to_be_changed
				//Start of mob code shamelessly ripped from mouseray
				M.tf_into(new_mob)

			//Did they put a person in it?
			else if(isliving(source_material))
				var/mob/living/M = source_material
				//Start of mob code shamelessly ripped from mouseray
				M.tf_into(new_mob)

			spawn_progress_time = 0
			max_spawn_time = rand(30,100)

			if(!spawning_types.len || !length(stored_materials))
				set_use_power(USE_POWER_IDLE)
				icon_state = "borgcharger0(old)"

		else if(prob(5))
			src.visible_message(span_notice("[icon2html(src,viewers(src))] [src] [pick("clicks","whizzes","whirrs","whooshes","clanks","clongs","clonks","bangs")]."))

	EXPIRY_STAMP(src, last_process_time, CLOCK_WORLD)


/// Requirement: also no possessed or vore-blacklisted items.
/obj/machinery/replicator/vore/can_insert(mob/living/user, atom/target, obj/item/held)
	. = ..()
	if(. == TRUE && (held.possessed_voice || is_type_in_list(held, GLOB.item_vore_blacklist)))
		return "you cannot put [held] into the machine"

/obj/machinery/replicator/vore/interaction_insert(mob/living/user, obj/item/W)
	return consent_insert_stage(user, W, list())

/obj/machinery/replicator/vore/proc/consent_insert_stage(mob/living/user, obj/item/W, list/consent_answers)
	if(istype(W, /obj/item/holder/micro)) //Are you putting a micro in it?
		var/obj/item/holder/micro/micro_holder = W
		var/mob/living/inserted_mob = micro_holder.held_mob //Get the actual mob.
		if(!inserted_mob.allow_spontaneous_tf) //Do they allow TF?
			to_chat(user, span_notice("You cannot put \the [W] into the machine. ((The prefs of the micro forbid this action.))"))
			return TRUE
		if(inserted_mob.stat == DEAD) //Hey medical...
			to_chat(user, span_notice("[W] is dead."))
			return TRUE
		if(inserted_mob.tf_mob_holder)
			to_chat(user, span_notice("[W] must be in their original form."))
			return TRUE
		if(inserted_mob.client)
			var/response //Let's see if they are SURE they accept the fact they will be a clothing, plushie, or something else.
			var/_answer_k351 = consent_answers["k351"]
			if(isnull(_answer_k351))
				open_request(src, /datum/prompt/choice/replicator_consent, PROC_REF(consent_insert_answered), answerer = inserted_mob, instigator = user, source_item = W, consent_answers = consent_answers, consent_key = "k351", question = "Are you -sure- you want to be put in this machine?\n(This machine will turn you into one of the various types of mobs in the game.)", title = "WARNING: Are you sure you want to be put in the machine and transformed?", choices = list("No", "Certain"))
				return
			response = _answer_k351
			if(response != "Certain") //If they don't agree, stop.
				to_chat(user, span_notice("[W] stops you from placing them in the machine."))
				return TRUE
			else //If they /do/ agree, give them one last chance.
				var/_answer_k356 = consent_answers["k356"]
				if(isnull(_answer_k356))
					open_request(src, /datum/prompt/choice/replicator_consent, PROC_REF(consent_insert_answered), answerer = inserted_mob, instigator = user, source_item = W, consent_answers = consent_answers, consent_key = "k356", question = "This is the last warning: Are you absolutely certain you want to be transformed into a mob?", title = "WARNING: FINAL CHANCE!", choices = list("No", "Certain"))
					return
				response = _answer_k356
				if(response != "Certain")
					to_chat(user, span_notice("[W] stops you from placing them in the machine."))
					return TRUE
				if(isvoice(inserted_mob) || W.loc == src) //Sanity.
					return TRUE
				log_and_message_admins("has just placed [inserted_mob] into a mob transformation machine.", user)
		else
			to_chat(user, span_notice("You cannot put \the [W] into the machine. ((The micro must be connected to the server.))"))
			return TRUE
	else if(istype(W,/obj/item/grab)) //Is someone being shoved into the machine?
		var/obj/item/grab/the_grab = W
		var/mob/living/inserted_mob = the_grab?.grab_target() //Get the mob that is grabbed.
		if(!inserted_mob.allow_spontaneous_tf)
			to_chat(user, span_notice("You cannot put \the [W] into the machine. ((The prefs of the micro forbid this action.))"))
			return TRUE
		if(inserted_mob.stat == DEAD)
			to_chat(user, span_notice("[W] is dead."))
			return TRUE
		if(inserted_mob.tf_mob_holder)
			to_chat(user, span_notice("[W] must be in their original form."))
			return TRUE
		if(inserted_mob.client)
			var/response
			var/_answer_k380 = consent_answers["k380"]
			if(isnull(_answer_k380))
				open_request(src, /datum/prompt/choice/replicator_consent, PROC_REF(consent_insert_answered), answerer = inserted_mob, instigator = user, source_item = W, consent_answers = consent_answers, consent_key = "k380", question = "Are you -sure- you want to be put in this machine?\n(This machine will turn you into one of the various types of mobs in the game.)", title = "WARNING: Are you sure you want to be put in the machine and transformed?", choices = list("No", "Certain"))
				return
			response = _answer_k380
			if(response != "Certain")
				to_chat(user, span_notice("[W] stops you from placing them in the machine."))
				return TRUE
			else
				var/_answer_k385 = consent_answers["k385"]
				if(isnull(_answer_k385))
					open_request(src, /datum/prompt/choice/replicator_consent, PROC_REF(consent_insert_answered), answerer = inserted_mob, instigator = user, source_item = W, consent_answers = consent_answers, consent_key = "k385", question = "This is the last warning: Are you absolutely certain you want to be transformed into a mob?", title = "WARNING: FINAL CHANCE!", choices = list("No", "Certain"))
					return
				response = _answer_k385
				if(response != "Certain")
					to_chat(user, span_notice("[W] stops you from placing them in the machine."))
					return TRUE
				if(isvoice(inserted_mob) || W.loc == src)
					return TRUE
				log_and_message_admins("has just placed [inserted_mob] into a mob transformation machine.", user)
				user.drop_item() //Dropping a grab destroys it.
				//Grabs require a bit of extra work.
				//We want them to drop their clothing/items as well.
				if(ishuman(inserted_mob)) //So, this WORKS. Works very well!
					var/mob/living/carbon/human/inserted_human = inserted_mob
					for(var/obj/item/I in inserted_mob)
						if(istype(I, /obj/item/implant) || istype(I, /obj/item/nif))
							continue
						inserted_human.drop_from_inventory(I)
				inserted_mob.forceMove(src)
				rel_add(src, nameof(stored_materials), inserted_mob)
				act_message(user, src, others = span_filter_notice(span_bold("%U%") + " inserts \the [inserted_mob] into %T%."))
				return TRUE
		else
			to_chat(user, span_notice("You cannot put \the [W] into the machine. ((The micro must be connected to the server.))"))
			return TRUE
	else if(istype(W, /obj/item/holder/mouse)) //No you can't turn your army of mice into giant rats.
		to_chat(user, span_notice("You cannot put \the [W] into the machine. The machine reads 'NOT ENOUGH BIOMASS'."))
		return TRUE
	user.drop_item() //Put the micro on the floor (or drop the item)
	if(istype(W, /obj/item/holder/micro)) //I hate this but it's the only way to get their stuff to drop.
		var/obj/item/holder/micro/micro_holder = W
		var/mob/living/inserted_mob = micro_holder.held_mob //Get the actual mob.
		if(ishuman(inserted_mob)) //Only humans have the drop_from_inventory proc.
			var/mob/living/carbon/human/inserted_human = inserted_mob
			for(var/obj/item/I in inserted_human) //Drop any remaining items! This only really seems to affect hands.
				if(istype(I, /obj/item/implant) || istype(I, /obj/item/nif))
					continue
				inserted_human.drop_from_inventory(I)
			//Now that we've dropped all the items they have, let's shove them back into the micro holder.
	W.forceMove(src)
	rel_add(src, nameof(stored_materials), W)
	act_message(user, src, others = span_filter_notice(span_bold("%U%") + " inserts %I% into %T%."), item = W)
	return TRUE

/obj/machinery/replicator/vore/ui_data(datum/act/eval/A)
	var/list/data = ..()
	var/list/merged_1 = ui_data_obj_machinery_replicator_vore(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/replicator/vore's window data.
/obj/machinery/replicator/vore/proc/ui_data_obj_machinery_replicator_vore(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["tgui_construction"] = (tgui_vore_selection || list())
	return data

CAPABILITIES(/obj/machinery/replicator/vore)
	op("construct", ui_act("construct", arg("key", schema_text(4096))), then(PROC_REF(ui_act_construct)))
/obj/machinery/replicator/vore/ui_act_construct(datum/act/op/A, key_arg)
	. = ..()
	if(.)
		return
	var/key = key_arg
	if(key in created_mobs)
		if(LAZYLEN(stored_materials) > LAZYLEN(spawning_types))
			if(LAZYLEN(spawning_types))
				visible_message(span_notice("[icon2html(src,viewers(src))] a [pick("light","dial","display","meter","pad")] on [src]'s front [pick("blinks","flashes")] [pick("red","yellow","blue","orange","purple","green","white")]."))
			else
				visible_message(span_notice("[icon2html(src,viewers(src))] [src]'s front compartment slides shut."))
			spawning_types.Add(LAZYACCESS(created_mobs, key))
			spawn_progress_time = 0
			set_use_power(USE_POWER_ACTIVE)
			icon_state = "borgcharger1(old)"
		else
			visible_message(fail_message)



//////////////////////////////
//////CLOTHING REPLICATOR/////
//////////////////////////////

/obj/machinery/replicator/clothing
	name = "alien machine"
	desc = "It's some kind of pod with strange wires and gadgets all over it. This one appears to have a humanoid shaped slot as an input and images of various objects on the buttons." //This hole was made for me!
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "borgcharger0(old)"
	var/quantity = 35 //This needs to be replaced with a GUI that lets you select the item you want.
	var/list/created_items
	var/list/tgui_vore_selection
	var/list/viable_items = list( // ALLOW(instance_list): d: edited in place per instance (1 writers)
	/obj/item/clothing/accessory/ring,
	/obj/item/clothing/gloves/evening,
	/obj/item/clothing/gloves/black,
	/obj/item/clothing/under/swimsuit/black,
	/obj/item/clothing/under/shorts/black,
	/obj/item/clothing/under/dress/maid,
	/obj/item/clothing/suit/oversize,
	/obj/item/clothing/suit/kimono/red,
	/obj/item/toy/plushie/lizardplushie/kobold,
	/obj/item/toy/plushie/borgplushie/medihound,
	/obj/item/toy/plushie/marble_fox,
	/obj/item/toy/plushie/lizard,
	/obj/item/toy/plushie/tuxedo_cat,
	/obj/item/clothing/head/pin/flower,
	/obj/item/clothing/head/wizard,
	/obj/item/clothing/head/wizard/marisa,
	/obj/item/clothing/head/beret,
	/obj/item/clothing/head/that,
	/obj/item/clothing/head/bowler,
	/obj/item/clothing/shoes/hitops/red,
	/obj/item/clothing/shoes/boots/jackboots,
	/obj/item/clothing/shoes/boots/workboots,
	/obj/item/clothing/shoes/boots/workboots/toeless,
	/obj/item/clothing/shoes/flipflop,
	/obj/item/clothing/shoes/boots/duty,
	/obj/item/clothing/shoes/footwraps,
	/obj/item/storage/smolebrickcase,
	/obj/item/lipstick,
	/obj/item/material/fishing_rod/modern,
	/obj/item/inflatable_duck,
	/obj/item/toy/syndicateballoon,
	/obj/item/towel,
	/obj/item/bedsheet/rainbowdouble
	) 	// Currently: 3 gloves, 5 undersuits, 3 oversuits, 5 plushies, 5 headwear, 7 shoes, 7 misc. = 35
		//Fishing hat was going to be added, but it was simply too powerful for this world.

// ALLOW(init/INSTANCE_STATE): rolls its control buttons and what each one makes
/obj/machinery/replicator/clothing/Initialize(mapload) //The specific thing about the VORE replicator is that it will only contain obj/items. Only things that can be picked up, used, and worn!
	. = ..() //TODO: Someone can replace the 'alien' interface with something neater sometime. It is simply out of my abilities at the current moment.

	for(var/i=0, i<quantity, i++)
		var/background = pick("yellow","purple","green","blue","red","orange","white")
		var/static/list/icons = list(
			"round" = "circle",
			"square" = "square",
			"diamond" = "gem",
			"heart" = "heart",
			"dog" = "dog",
			"human" = "user",
		)
		var/icon = pick(icons)
		var/static/list/colors = list(
			"toggle" = "pink",
			"switch" = "yellow",
			"lever" = "red",
			"button" = "black",
			"pad" = "white",
			"hole" = "black",
		)
		var/color = pick(colors)
		var/button_desc = "a [background], [icon] shaped [color]"
		var/generated_item = pick(viable_items)
		viable_items.Remove(generated_item)
		LAZYSET(created_items, button_desc, generated_item)
		LAZYINITLIST(tgui_vore_selection); tgui_vore_selection.Add(list(list(
			"key" = button_desc,
			"background" = background,
			"icon" = icons[icon],
			"foreground" = colors[color],
		)))

/obj/machinery/replicator/clothing/work_step(datum/act/timer/A)
	// Works while something is queued and it has power; a queue (its UI) or power wakes it.
	if(!spawning_types.len)
		last_process_time = 0
		return PROCESS_KILL
	if(!powered())
		last_process_time = 0
		return work_wait_for_power(src)
	if(!last_process_time)
		EXPIRY_STAMP(src, last_process_time, CLOCK_WORLD)
	if(spawning_types.len && powered())
		spawn_progress_time += world.time - last_process_time
		if(spawn_progress_time > max_spawn_time)
			src.visible_message(span_notice("[icon2html(src,viewers(src))] [src] pings!"))

			var/obj/source_material = pop(stored_materials)
			var/spawn_type = pop(spawning_types)
			var/obj/item/spawned_obj = new spawn_type(src.loc)
			var/obj/item/original_name = spawned_obj.name //Get the item's name before it's prefixed. Used for micro code.
			if(source_material)
				if(length(source_material.name) < MAX_MESSAGE_LEN)
					spawned_obj.name = "[source_material] " +  spawned_obj.name
				if(length(source_material.desc) < MAX_MESSAGE_LEN * 2)
					if(spawned_obj.desc)
						spawned_obj.desc += " It is made of [source_material]."
					else
						spawned_obj.desc = "It is made of [source_material]."
			if(istype(source_material,/obj/item/holder/micro))
				var/obj/item/holder/micro/micro_holder = source_material //Tells the machine that a micro is the material being used
				var/mob/mob_to_be_changed = micro_holder.held_mob //Get the mob.
				var/mob/living/M = mob_to_be_changed
				M.tf_into(spawned_obj, TRUE, original_name)

			else if(isliving(source_material))//Did they shove a person in there normally?
				var/mob/living/M = source_material //If so, this cuts down the work we have to do!
				M.tf_into(spawned_obj, TRUE, original_name)

			spawn_progress_time = 0
			max_spawn_time = rand(30,100)

			if(!spawning_types.len || !length(stored_materials))
				set_use_power(USE_POWER_IDLE)
				icon_state = "borgcharger0(old)"

		else if(prob(5))
			src.visible_message(span_notice("[icon2html(src,viewers(src))] [src] [pick("clicks","whizzes","whirrs","whooshes","clanks","clongs","clonks","bangs")]."))

	EXPIRY_STAMP(src, last_process_time, CLOCK_WORLD)

/// Requirement: also no possessed or vore-blacklisted items.
/obj/machinery/replicator/clothing/can_insert(mob/living/user, atom/target, obj/item/held)
	. = ..()
	if(. == TRUE && (held.possessed_voice || is_type_in_list(held, GLOB.item_vore_blacklist)))
		return "you cannot put [held] into the machine"

/obj/machinery/replicator/clothing/interaction_insert(mob/living/user, obj/item/W)
	return consent_insert_stage(user, W, list())

/obj/machinery/replicator/clothing/proc/consent_insert_stage(mob/living/user, obj/item/W, list/consent_answers)
	if(istype(W, /obj/item/holder/micro) || istype(W, /obj/item/holder/mouse)) //Are you putting a micro/mouse in it?
		var/obj/item/holder/micro/micro_holder = W
		var/mob/living/inserted_mob = micro_holder.held_mob //Get the actual mob.
		if(!inserted_mob.allow_spontaneous_tf) //Do they allow TF?
			to_chat(user, span_notice("You cannot put \the [W] into the machine. ((The prefs of the micro forbid this action.))"))
			return TRUE
		if(inserted_mob.stat == DEAD) //Hey medical...
			to_chat(user, span_notice("[W] is dead."))
			return TRUE
		if(inserted_mob.tf_mob_holder) //No recursion!!!
			to_chat(user, span_notice("[W] must be in their original form."))
			return TRUE
		if(inserted_mob.client)
			var/response //Let's see if they are SURE they accept the fact they will be a clothing, plushie, or something else.
			var/_answer_k604 = consent_answers["k604"]
			if(isnull(_answer_k604))
				open_request(src, /datum/prompt/choice/replicator_consent, PROC_REF(consent_insert_answered), answerer = inserted_mob, instigator = user, source_item = W, consent_answers = consent_answers, consent_key = "k604", question = "Are you -sure- you want to be put in this machine?\n(This machine can turn you into various clothing, footwear, plushies, and other miscellaneous objects. This means that more likely than not, you will be used as whatever object is used. Make certain your preferences align with this possibility.)", title = "WARNING: Are you sure you want to be put in the machine and transformed?", choices = list("No", "Certain"))
				return
			response = _answer_k604
			if(response != "Certain") //If they don't agree, stop.
				to_chat(user, span_notice("[W] stops you from placing them in the machine."))
				return TRUE
			else //If they /do/ agree, give them one last chance.
				var/_answer_k609 = consent_answers["k609"]
				if(isnull(_answer_k609))
					open_request(src, /datum/prompt/choice/replicator_consent, PROC_REF(consent_insert_answered), answerer = inserted_mob, instigator = user, source_item = W, consent_answers = consent_answers, consent_key = "k609", question = "This is the last warning: Are you absolutely certain you want to be transformed into an object and have the possibility of being used as such?", title = "WARNING: FINAL CHANCE!", choices = list("No", "I accept the possibilities"))
					return
				response = _answer_k609
				if(response != "I accept the possibilities")
					to_chat(user, span_notice("[W] stops you from placing them in the machine."))
					return TRUE
				if(isvoice(inserted_mob) || W.loc == src) //This is a sanity check to keep them from entering it multiple times.
					return TRUE
				log_and_message_admins("has just placed [inserted_mob] into an item transformation machine.", user)
		else
			to_chat(user, span_notice("You cannot put \the [W] into the machine. ((The micro must be connected to the server.))"))
			return TRUE
	else if(istype(W,/obj/item/grab)) //Is someone being shoved into the machine?
		var/obj/item/grab/the_grab = W
		var/mob/living/inserted_mob = the_grab?.grab_target() //Get the mob that is grabbed.
		if(!inserted_mob.allow_spontaneous_tf)
			to_chat(user, span_notice("You cannot put \the [W] into the machine. ((The prefs of the micro forbid this action.))"))
			return TRUE
		if(inserted_mob.stat == DEAD)
			to_chat(user, span_notice("[W] is dead."))
			return TRUE
		if(inserted_mob.tf_mob_holder)
			to_chat(user, span_notice("[W] must be in their original form."))
			return TRUE
		if(inserted_mob.client)
			var/response
			var/_answer_k633 = consent_answers["k633"]
			if(isnull(_answer_k633))
				open_request(src, /datum/prompt/choice/replicator_consent, PROC_REF(consent_insert_answered), answerer = inserted_mob, instigator = user, source_item = W, consent_answers = consent_answers, consent_key = "k633", question = "Are you -sure- you want to be put in this machine?\n(This machine can turn you into various clothing, footwear, plushies, and other miscellaneous objects. This means that more likely than not, you will be used as whatever object is used. Make certain your preferences align with this possibility.)", title = "WARNING: Are you sure you want to be put in the machine and transformed?", choices = list("No", "Certain"))
				return
			response = _answer_k633
			if(response != "Certain")
				to_chat(user, span_notice("[W] stops you from placing them in the machine."))
				return TRUE
			else
				var/_answer_k638 = consent_answers["k638"]
				if(isnull(_answer_k638))
					open_request(src, /datum/prompt/choice/replicator_consent, PROC_REF(consent_insert_answered), answerer = inserted_mob, instigator = user, source_item = W, consent_answers = consent_answers, consent_key = "k638", question = "This is the last warning: Are you absolutely certain you want to be transformed into an object and have the possibility of being used as such?", title = "WARNING: FINAL CHANCE!", choices = list("No", "I accept the possibilities"))
					return
				response = _answer_k638
				if(response != "I accept the possibilities")
					to_chat(user, span_notice("[W] stops you from placing them in the machine."))
					return TRUE
				if(isvoice(inserted_mob) || W.loc == src)
					return TRUE
				log_and_message_admins("has just placed [inserted_mob] into an item transformation machine.", user)
				user.drop_item() //Dropping a grab destroys it.
				//Grabs require a bit of extra work.
				//We want them to drop their clothing/items as well.
				if(ishuman(inserted_mob)) //So, this WORKS. Works very well!
					var/mob/living/carbon/human/inserted_human = inserted_mob
					for(var/obj/item/I in inserted_mob)
						if(istype(I, /obj/item/implant) || istype(I, /obj/item/nif))
							continue
						inserted_human.drop_from_inventory(I)
				inserted_mob.forceMove(src)
				rel_add(src, nameof(stored_materials), inserted_mob)
				act_message(user, src, others = span_filter_notice(span_bold("%U%") + " inserts \the [inserted_mob] into %T%."))
				return TRUE
		else
			to_chat(user, span_notice("You cannot put \the [W] into the machine. ((They must be connected to the server.))"))
			return TRUE

	user.drop_item() //Put the micro on the floor (or drop the item)
	if(istype(W, /obj/item/holder/micro)) //I hate this but it's the only way to get their stuff to drop.
		var/obj/item/holder/micro/micro_holder = W
		var/mob/living/inserted_mob = micro_holder.held_mob //Get the actual mob.
		if(ishuman(inserted_mob)) //Only humans have the drop_from_inventory proc.
			var/mob/living/carbon/human/inserted_human = inserted_mob
			for(var/obj/item/I in inserted_human) //Drop any remaining items! This only really seems to affect hands.
				if(istype(I, /obj/item/implant) || istype(I, /obj/item/nif))
					continue
				inserted_human.drop_from_inventory(I)
			//Now that we've dropped all the items they have, let's shove them back into the micro holder.
	W.forceMove(src)
	rel_add(src, nameof(stored_materials), W)
	act_message(user, src, others = span_filter_notice(span_bold("%U%") + " inserts %I% into %T%."), item = W)
	return TRUE


CAPABILITIES(/obj/machinery/replicator/clothing)
	interface("XenoarchReplicatorClothing")
	without("ui_open")
	op("construct", ui_act("construct", arg("key", schema_text(4096))), then(PROC_REF(ui_act_construct)))

/obj/machinery/replicator/clothing/ui_data(datum/act/eval/A)
	var/list/data = ..()
	var/list/merged_1 = ui_data_obj_machinery_replicator_clothing(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/replicator/clothing's window data.
/obj/machinery/replicator/clothing/proc/ui_data_obj_machinery_replicator_clothing(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["tgui_construction"] = (tgui_vore_selection || list())
	return data

/obj/machinery/replicator/clothing/ui_act_construct(datum/act/op/A, key_arg)
	. = ..()
	if(.)
		return
	var/key = key_arg
	if(key in created_items)
		if(LAZYLEN(stored_materials) > LAZYLEN(spawning_types))
			if(LAZYLEN(spawning_types))
				visible_message(span_notice("[icon2html(src,viewers(src))] a [pick("light","dial","display","meter","pad")] on [src]'s front [pick("blinks","flashes")] [pick("red","yellow","blue","orange","purple","green","white")]."))
			else
				visible_message(span_notice("[icon2html(src,viewers(src))] [src]'s front compartment slides shut."))
			spawning_types.Add(LAZYACCESS(created_items, key))
			spawn_progress_time = 0
			set_use_power(USE_POWER_ACTIVE)
			icon_state = "borgcharger1(old)"
		else
			visible_message(fail_message)

/// Original insertion arguments remain weak while the prospective transformed mob answers.
/datum/prompt/choice/replicator_consent
	timeout = 0
	buttons = TRUE
	var/mob/instigator
	var/obj/item/source_item
	var/instigator_expected = FALSE
	var/source_item_expected = FALSE
	var/list/consent_answers
	var/consent_key

CAPABILITIES(/datum/prompt/choice/replicator_consent)
	ref_one(nameof(instigator), /mob)
	ref_one(nameof(source_item), /obj/item)

/datum/prompt/choice/replicator_consent/prepare(datum/act/A)
	. = ..()
	var/mob/captured_user = instigator
	var/obj/item/captured_item = source_item
	instigator_expected = !isnull(captured_user)
	source_item_expected = !isnull(captured_item)
	rel_clear(src, nameof(instigator))
	rel_clear(src, nameof(source_item))
	if(captured_user && !QDELETED(captured_user))
		rel_set(src, nameof(instigator), captured_user)
	if(captured_item && !QDELETED(captured_item))
		rel_set(src, nameof(source_item), captured_item)

/datum/prompt/choice/replicator_consent/recheck_extra()
	. = ..()
	if(.)
		return
	if(instigator_expected && QDELETED(instigator))
		return "gone"
	if(source_item_expected && QDELETED(source_item))
		return "gone"

/obj/machinery/replicator/vore/proc/consent_insert_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = consent_insert_apply(A)
	SStgui.update_uis(src)
	return .

/obj/machinery/replicator/vore/proc/consent_insert_apply(datum/act/request/A)
	var/datum/prompt/choice/replicator_consent/ask = A.answer
	ask.consent_answers[ask.consent_key] = ask.value
	return consent_insert_stage(ask.instigator, ask.source_item, ask.consent_answers)

/obj/machinery/replicator/clothing/proc/consent_insert_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = consent_insert_apply(A)
	SStgui.update_uis(src)
	return .

/obj/machinery/replicator/clothing/proc/consent_insert_apply(datum/act/request/A)
	var/datum/prompt/choice/replicator_consent/ask = A.answer
	ask.consent_answers[ask.consent_key] = ask.value
	return consent_insert_stage(ask.instigator, ask.source_item, ask.consent_answers)
