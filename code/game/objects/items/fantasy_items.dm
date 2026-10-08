
/obj/item/healthanalyzer/scroll //reports all of the above, as well as name and quantity of nonmed reagents in stomach
	name = "scroll of divination"
	desc = "An unusual scroll that appears to report all of the details of a person's health when waved near them. Oddly, it seems to have a little metal chip up near the handles..."
	profile_type = /datum/diagnostic_profile/health_analyzer/phasic
	icon_state = "health_scroll"


/obj/item/tool/crowbar/alien/magic
	name = "sentient crowbar"
	desc = "A crowbar with a green gem set in it and a green ribbon tied to it, it floats lightly by itself and appears to be able to pry on its own. It almost feels like there is some sort of anti gravity generator running in it..."
	catalogue_data = list(/datum/category_item/catalogue/anomalous/precursor_a/alien_crowbar)
	icon_state = "crowbar_sentient"

/obj/item/tool/screwdriver/alien/magic
	name = "vintage screwdriver of revolving"
	desc = "A vintage screwdriver that spins as fast as a drill with little aid, it has a red gem on the handle. It oddly sounds like a drill too..."
	catalogue_data = list(/datum/category_item/catalogue/anomalous/precursor_a/alien_screwdriver)
	icon = 'icons/obj/abductor.dmi'
	icon_state = "screwdriver_old"

/obj/item/weldingtool/alien/magic
	name = "bellows of flame"
	desc = "A set of bellows that have a yellow gem on the spout, they emit flames when pressed. Oddly seems to have a faint phoron smell to it..."
	catalogue_data = list(/datum/category_item/catalogue/anomalous/precursor_a/alien_welder)
	icon = 'icons/obj/abductor.dmi'
	icon_state = "bellows"

/obj/item/tool/wirecutters/alien/magic
	name = "secateurs of organisation"
	desc = "Extremely sharp secateurs, fitted with a glowing blue gem, said to be magically enhanced for speed. There seems to be a little whirring sound coming from beneath that gem..."
	icon = 'icons/obj/abductor.dmi'
	icon_state = "cutters_magic"

/obj/item/tool/wrench/alien/magic
	name = "pliers of molding"
	desc = "A set of pliers that seems to mold to the shape of their target, housing a pink gem. Oddly seems to have a slightly slimey texture at the metal..."
	catalogue_data = list(/datum/category_item/catalogue/anomalous/precursor_a/alien_wrench)
	icon = 'icons/obj/abductor.dmi'
	icon_state = "pliers"

/obj/item/surgical/bone_clamp/alien/magic
	icon = 'icons/obj/abductor.dmi'
	toolspeed = 0.75
	icon_state = "bone_boneclamp"
	name = "bone bone clamp"
	desc = "A bone clamp made of bones for fixing bones using bones, it feels strangely adept. In fact, it doesn't really feel like actual bone at all..."

// Bath

/obj/structure/bed/bath
	name = "wash tub"
	desc = "A wooden tub that can be filled with water for washing yourself."
	icon_state = "bath"
	base_icon = "bath"
	flags = OPENCONTAINER
	var/amount_per_transfer_from_this = 5

/obj/structure/bed/bath/look_parts(datum/look/look)
	if(reagents.total_volume < 1)
		look.state("bath")
	else if(reagents.total_volume < 50)
		look.state("bath1")
	else if(reagents.total_volume < 150)
		look.state("bath2")
	else if(reagents.total_volume < 301)
		look.state("bath3")

CAPABILITIES(/obj/structure/bed/bath)
	reagents(300)
	op("bath_interaction_item", item(/obj/item), then(PROC_REF(bath_interaction_item)))

/obj/structure/bed/bath/proc/bath_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/mop) || istype(I, /obj/item/soap)) // "Allows soap and rags to be used on mopbuckets"
		if(reagents.total_volume < 1)
			to_chat(user, span_warning("\The [src] is out of water!"))
		else
			reagents.trans_to_obj(I, 5)
			to_chat(user, span_notice("You wet \the [I] in \the [src]."))
			play_sfx(src, SFX_EFFECTS_SLOSH)
	if(istype(I, /obj/item/reagent_containers/glass))
		update_icon()
		return OP_PASS
	else if(istype(I, /obj/item/grab))
		var/obj/item/grab/G = I
		var/mob/living/affecting = G?.grab_target()
		if(has_buckled_mobs()) //Handles trying to buckle someone else to a chair when someone else is on it
			to_chat(user, span_notice("\The [src] already has someone buckled to it."))
			return OP_PASS
		act_message(user, src, others = span_notice("%U% attempts to buckle [affecting] into %T%!"))
		task_start(/datum/task/timed/bath_bath_buckle, user, G?.grab_target(), receiver = src, I = I, affecting = affecting)
	return OP_PASS

/datum/task/timed/bath_bath_buckle
	duration = 2 SECONDS
	complete_proc = /obj/structure/bed/bath/proc/bath_buckle_done
	var/obj/item/I
	var/mob/living/affecting

/obj/structure/bed/bath/proc/bath_buckle_done(datum/task/timed/bath_bath_buckle/task)
	var/obj/item/I = task.I
	var/mob/user = task.actor
	var/mob/living/affecting = task.affecting
	affecting.forceMove(loc)
	if(buckle_mob(affecting))
		act_message(affecting, src, MSG_SELF(span_danger("You are buckled to %T% by [user.name]!")), \
			MSG_OTHERS(span_danger("%U% is buckled to %T% by [user.name]!")), \
			MSG_BLIND(span_notice("You hear metal clanking.")))
	consume(I, user)


//oven

/obj/machinery/appliance/cooker/oven/yeoldoven
	name = "oven"
	desc = "Old fashioned cookies are ready, dear."
	icon_state = "yeoldovenopen"
	tgui_id = "CookingOvenOld"

DECLARE_APPEARANCE_PROC(/obj/machinery/appliance/cooker/oven/yeoldoven, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/appliance/cooker/oven/yeoldoven/appearance_overlays()
	. = list()
	if(!open)
		if(!has_condition())
			icon_state = "yeoldovenclosed_on"
			if(cooking == TRUE)
				icon_state = "yeoldovenclosed_cooking"
				if(oven_loop)
					oven_loop.start(src)
			else
				icon_state = "yeoldovenclosed_on"
				if(oven_loop)
					oven_loop.stop(src)
		else
			icon_state = "yeoldovenclosed_off"
			if(oven_loop)
				oven_loop.stop(src)
	else
		icon_state = "yeoldovenopen"
		if(oven_loop)
			oven_loop.stop(src)

//toilet

/obj/structure/toilet/wooden
	name = "wooden toilet"
	desc = "It's basically a hole in a box with a bucket inside. This one seems remarkably clean."
	icon_state = "toilet3"
	open = 1

// a hole in a box: a touch does nothing (no lid, no cistern to loot), and its own item use replaces the toilet's
CAPABILITIES(/obj/structure/toilet/wooden)
	without("use")
	without("item")
	without("item_cyborg")
	op("wooden_touch", hand(), ungated(), then(PROC_REF(wooden_touched)))
	op("wooden_item", item(/obj/item), when(req_actor_kind(/mob/living/silicon/robot, not = TRUE)), then(PROC_REF(wooden_interaction_item)))
	op("wooden_item_cyborg", item(/obj/item), when(req_actor_kind(/mob/living/silicon/robot)), then(PROC_REF(wooden_interaction_item_cyborg)))

/// A touch takes the click and does nothing.
/obj/structure/toilet/wooden/proc/wooden_touched(datum/act/op/A)
	return OP_OK

/// Old attackby: a swirlie for a grabbed mob, or an item into the cistern.
/obj/structure/toilet/wooden/proc/wooden_interaction_item(datum/act/op/A)
	return wooden_item_used(A, FALSE)

/// A cyborg's module never goes in the cistern.
/obj/structure/toilet/wooden/proc/wooden_interaction_item_cyborg(datum/act/op/A)
	return wooden_item_used(A, TRUE)

/obj/structure/toilet/wooden/proc/wooden_item_used(datum/act/op/A, cyborg)
	var/mob/living/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/grab))
		user.setClickCooldown(user.get_attack_speed(I))
		var/obj/item/grab/G = I

		if(isliving(G?.grab_target()))
			var/mob/living/GM = G?.grab_target()

			if(G.state>1)
				if(!GM.loc == get_turf(src))
					to_chat(user, span_notice("[GM.name] needs to be on the toilet."))
					return OP_PASS
				var/mob/living/swirlie = swirlie_mob
				if(open && !swirlie)
					act_message(user, null, MSG_SELF(span_notice("You start to give [GM.name] a swirlie!")), MSG_OTHERS(span_danger("%U% starts to give [GM.name] a swirlie!")))
					rel_set(src, nameof(swirlie_mob), GM)
					task_start(/datum/task/timed/wooden_wooden_swirlie, user, GM, receiver = src)
					rel_clear(src, nameof(swirlie_mob))
				else
					act_message(user, src, MSG_SELF(span_notice("You slam [GM.name] into %T%!")), MSG_OTHERS(span_danger("%U% slams [GM.name] into %T%!")))
					GM.injure(INJURY_BLUNT, 5, source = src)
			else
				to_chat(user, span_notice("You need a tighter grip."))

	if(cistern && !cyborg) //STOP PUTTING YOUR MODULES IN THE TOILET.
		if(I.w_class > 3)
			to_chat(user, span_notice("\The [I] does not fit."))
			return OP_PASS
		if(w_items + I.w_class > 5)
			to_chat(user, span_notice("The cistern is full."))
			return OP_PASS
		user.drop_item()
		I.forceMove(src)
		w_items += I.w_class
		to_chat(user, "You carefully place \the [I] into the cistern.")
		return OP_PASS
	return OP_PASS

/datum/task/timed/wooden_wooden_swirlie
	duration = 3 SECONDS
	complete_proc = /obj/structure/toilet/wooden/proc/wooden_swirlie_done

/obj/structure/toilet/wooden/proc/wooden_swirlie_done(datum/task/timed/wooden_wooden_swirlie/task)
	var/mob/living/user = task.actor
	var/mob/living/GM = task.target
	act_message(user, null, MSG_SELF(span_notice("You give [GM.name] a swirlie!")), MSG_OTHERS(span_danger("%U% gives [GM.name] a swirlie!")), MSG_BLIND("You hear a toilet flushing."))
	if(!GM.internal)
		GM.body?.add_restriction(src, BF_AIRWAY, 0, 5 SECONDS) // a faceful of water


/// The look (the draw sweep: from APPEARANCE_NONE).
/obj/structure/toilet/wooden/draw(datum/look/look)
	..()
	// APPEARANCE_NONE: the mapped sprite, without the parent's declared states and layers
	look.state(null)

//cooking pot

/obj/machinery/microwave/cookingpot
	name = "cooking pot"
	icon_state = "cookingpot"
	desc = "An old fashioned cooking pot above some logs."

	visible_action = "starts cooking"
	audible_action = "fire roar"

/obj/machinery/microwave/cookingpot/draw(datum/look/look)
	..()
	// APPEARANCE_NONE: the mapped sprite, without the parent's declared states and layers
	look.state(null)
	if(broken)
		look.state("cookingpotb")
		return
	if(dirty >= 100)
		if(operating)
			look.state("cookingpotbloody1")
		else
			look.state("cookingpotbloody0")
		return
	if(operating)
		look.state("cookingpot1")
	else
		look.state("cookingpot")

/obj/machinery/microwave/cookingpot/broke(spark = FALSE)
	. = ..()

// Magic bluespace stuff

/obj/item/clothing/gloves/bluespace/magic
	name = "bracer of resilience"
	desc = "A bracer that is said to make one resistent to size changing magic."
	icon = 'icons/inventory/accessory/item.dmi'
	icon_state = "bs_magic"

//harpoon

/obj/item/bluespace_harpoon/wand
	name = "teleportation wand"
	desc = "An odd wand that weighs more than it looks like it should. It has a wire protruding from it and a glass-like tip, suggesting there may be more tech behind this than magic."

	icon = 'icons/obj/gun.dmi'
	icon_state = "harpoonwand-2"

DECLARE_APPEARANCE_PROC(/obj/item/bluespace_harpoon/wand, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/bluespace_harpoon/wand/appearance_overlays()
	. = list()
	if(transforming)
		switch(mode)
			if(0)
				flick("harpoonwand-2-change", src)
				icon_state = "harpoonwand-1"
			if(1)
				flick("harpoonwand-1-change",src)
				icon_state = "harpoonwand-2"
		transforming = 0

/*
 * magic orb
 */

/obj/item/gun/energy/taser/magic
	name = "orb of lightning"
	desc = "An orb filled with electrical energy, it looks oddly like a toy plasma orb..."
	description_fluff = ""
	icon_state = "orb"

//Kettle

/obj/machinery/chemical_dispenser/kettle //reskin of coffee dispenser
	name = "kettle"
	desc = "A kettle used for making hot drinks."
	icon_state = "kettle"
	ui_title = "kettle"
	accept_drinking = 1
	import_job = null

/obj/machinery/chemical_dispenser/kettle/full
	spawn_cartridges = list(
			/obj/item/reagent_containers/chem_disp_cartridge/coffee,
			/obj/item/reagent_containers/chem_disp_cartridge/cafe_latte,
			/obj/item/reagent_containers/chem_disp_cartridge/soy_latte,
			/obj/item/reagent_containers/chem_disp_cartridge/hot_coco,
			/obj/item/reagent_containers/chem_disp_cartridge/milk,
			/obj/item/reagent_containers/chem_disp_cartridge/cream,
			/obj/item/reagent_containers/chem_disp_cartridge/sugar,
			/obj/item/reagent_containers/chem_disp_cartridge/tea,
			/obj/item/reagent_containers/chem_disp_cartridge/ice,
			/obj/item/reagent_containers/chem_disp_cartridge/mint,
			/obj/item/reagent_containers/chem_disp_cartridge/orange,
			/obj/item/reagent_containers/chem_disp_cartridge/lemon,
			/obj/item/reagent_containers/chem_disp_cartridge/lime,
			/obj/item/reagent_containers/chem_disp_cartridge/berry,
			/obj/item/reagent_containers/chem_disp_cartridge/greentea,
			/obj/item/reagent_containers/chem_disp_cartridge/decaf,
			/obj/item/reagent_containers/chem_disp_cartridge/chaitea,
			/obj/item/reagent_containers/chem_disp_cartridge/decafchai
		)

// teleporter

/obj/item/perfect_tele/magic
	name = "teleportation tome"
	desc = "A large tome that can be used to teleport to special pages that can be removed from it. The spine seems to have some sort buzzing tech inside..."
	icon = 'icons/obj/props/fantasy.dmi'
	icon_state = "teleporter"
	beacons_left = 3
	cell_type = /obj/item/cell/device
	beacon_word = "page"
	maker_word = "tome"
	beacon_type = /obj/item/perfect_tele_beacon/magic

/obj/item/perfect_tele_beacon/magic
	name = "teleportation page"
	desc = "A single page from a tome, with a glowing blue symbol on it. It seems like the symbol is raised as though there were something running beneath it..."
	icon = 'icons/obj/props/fantasy.dmi'
	icon_state = "page"

//sizegun

/obj/item/slow_sizegun/magic
	name = "wand of growth and shrinking"
	desc = "A wand said to be able to shrink or grow it's targets, it's encrusted with glowing gems and a... trigger?"
	icon = 'icons/obj/gun.dmi'
	icon_state = "sizegun-magic-0"
	base_icon_state = "sizegun-magic"

//locked door

/obj/structure/simple_door/dungeon
	material_name = MAT_CULT

/obj/structure/simple_door/dungeon/locked
	locked = TRUE
	breakable = FALSE
	lock_id = "dungeon"

/obj/item/simple_key/dungeon
	name = "old key"
	desc = "A plain, old-timey key, as one might use to unlock a door."
	icon_state = "dungeon"
	key_id = "dungeon"
