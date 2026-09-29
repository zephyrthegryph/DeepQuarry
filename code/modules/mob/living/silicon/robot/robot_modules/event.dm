//CHOMPNOTE - if upstream edits the sprite lists it will have to be manually copied into our station_vr file, anything else is just read from here
/* Other, unaffiliated modules */
/obj/item/robot_module/robot/malf
	hide_on_manifest = TRUE
	ui_theme = "malfunction"
	idcard_type = /obj/item/card/id/lost

// The module that borgs on the surface have.  Generally has a lot of useful tools in exchange for questionable loyalty to the crew.
/obj/item/robot_module/robot/malf/lost
	name = "lost robot module"

/obj/item/robot_module/robot/malf/lost/create_equipment(mob/living/silicon/robot/robot)
	..()
	// Sec
	own_add(src, nameof(modules), new /obj/item/melee/robotic/baton/shocker(src))
	own_add(src, nameof(modules), new /obj/item/handcuffs/cyborg(src))
	own_add(src, nameof(modules), new /obj/item/borg/combat/shield(src))

	// Med
	own_add(src, nameof(modules), new /obj/item/healthanalyzer(src))
	own_add(src, nameof(modules), new /obj/item/shockpaddles/robot(src))
	own_add(src, nameof(modules), new /obj/item/reagent_containers/borghypo/lost(src))

	// Engi
	own_add(src, nameof(modules), new /obj/item/weldingtool/electric/mounted(src))
	own_add(src, nameof(modules), new /obj/item/tool/screwdriver/cyborg(src))
	own_add(src, nameof(modules), new /obj/item/tool/wrench/cyborg(src))
	own_add(src, nameof(modules), new /obj/item/tool/wirecutters/cyborg(src))
	own_add(src, nameof(modules), new /obj/item/multitool/cyborg(src))

	// Sci
	own_add(src, nameof(modules), new /obj/item/robotanalyzer(src))

	// Potato
	own_add(src, nameof(emag), new /obj/item/gun/energy/robotic/laser/retro(src))

	var/datum/matter_synth/wire = new /datum/matter_synth/wire()
	own_add(src, nameof(synths), wire)

	own_add(src, nameof(modules), new /obj/item/dogborg/sleeper/lost(src))
	own_add(src, nameof(modules), new /obj/item/dogborg/pounce(src))

/obj/item/robot_module/robot/malf/lost/adjust_gps(obj/item/gps/robot/robot_gps)
	robot_gps.long_range = TRUE
	robot_gps.hide_signal = TRUE
	robot_gps.can_hide_signal = TRUE

/obj/item/robot_module/robot/malf/lost/handle_special_unlocks(mob/living/silicon/robot/owner_robot)
	if(!owner_robot.emag_items)
		owner_robot.scramble_hardware(20)
	if (owner_robot.churn_count == 5)
		own_add(src, nameof(emag), new /obj/item/self_repair_system/advanced(src))
		owner_robot.hud_used.update_robot_modules_display()

/obj/item/robot_module/robot/malf/gravekeeper
	name = "gravekeeper robot module"

/obj/item/robot_module/robot/malf/gravekeeper/create_equipment(mob/living/silicon/robot/robot)
	..()
	// For fending off animals and looters
	own_add(src, nameof(modules), new /obj/item/melee/robotic/baton/shocker(src))
	own_add(src, nameof(modules), new /obj/item/borg/combat/shield(src))

	// For repairing gravemarkers
	own_add(src, nameof(modules), new /obj/item/weldingtool/electric/mounted(src))
	own_add(src, nameof(modules), new /obj/item/tool/screwdriver/cyborg(src))
	own_add(src, nameof(modules), new /obj/item/tool/wrench/cyborg(src))

	// For growing flowers
	own_add(src, nameof(modules), new /obj/item/robotic_multibelt/botanical(src))

	// For digging and beautifying graves
	own_add(src, nameof(modules), new /obj/item/shovel(src))
	own_add(src, nameof(modules), new /obj/item/gripper/gravekeeper(src))

	// For really persistent looters
	own_add(src, nameof(emag), new /obj/item/gun/energy/robotic/laser/retro(src))

	var/datum/matter_synth/wood = new /datum/matter_synth/wood(50000) // "Buffing this to 50k on account of broken code not letting us pick up more stacks. Wee."
	own_add(src, nameof(synths), wood)

	var/obj/item/stack/material/cyborg/wood/W = new (src)
	rel_add(W, nameof(W.synths), wood)
	own_add(src, nameof(modules), W)

	// For uwu
	own_add(src, nameof(modules), new /obj/item/dogborg/sleeper/compactor/generic(src))
	own_add(src, nameof(emag), new /obj/item/dogborg/pounce(src))

	// "Giving the gravekeeper drone more modules to allow it to actually do it's job."
	own_add(src, nameof(modules), new /obj/item/tool/wirecutters/cyborg(src)) //Gotta clear those pesky landmines somehow. Also allows for deconstruction of things in the way!
	own_add(src, nameof(modules), new /obj/item/multitool(src))
	own_add(src, nameof(modules), new /obj/item/soap/nanotrasen(src))
	own_add(src, nameof(modules), new /obj/item/storage/bag/trash(src))
	own_add(src, nameof(modules), new /obj/item/mop(src))
	own_add(src, nameof(modules), new /obj/item/lightreplacer(src))
	own_add(src, nameof(modules), new /obj/item/gripper/no_use/loader(src))
	own_add(src, nameof(modules), new /obj/item/gripper(src))
	own_add(src, nameof(modules), new /obj/item/pickaxe(src))
	own_add(src, nameof(modules), new /obj/item/floor_painter(src))
	own_add(src, nameof(modules), new /obj/item/pen/robopen(src))
	own_add(src, nameof(modules), new /obj/item/form_printer(src))
	own_add(src, nameof(modules), new /obj/item/gripper/paperwork(src))
	own_add(src, nameof(modules), new /obj/item/hand_labeler(src))
	own_add(src, nameof(modules), new /obj/item/stamp(src))
	own_add(src, nameof(modules), new /obj/item/stamp/denied(src))

	var/obj/item/flame/lighter/zippo/L = new /obj/item/flame/lighter/zippo(src) // starts unlit: lit, it would burn on the slow lane from module creation
	own_add(src, nameof(modules), L)

	var/datum/matter_synth/metal = new /datum/matter_synth/metal(50000)
	var/datum/matter_synth/glass = new /datum/matter_synth/glass(50000)
	var/datum/matter_synth/plasteel = new /datum/matter_synth/plasteel(20000)
	var/datum/matter_synth/plastic = new /datum/matter_synth/plastic(50000)
	var/datum/matter_synth/wire = new /datum/matter_synth/wire()
	own_add(src, nameof(synths), metal)
	own_add(src, nameof(synths), glass)
	own_add(src, nameof(synths), plasteel)
	own_add(src, nameof(synths), plastic)
	own_add(src, nameof(synths), wire)

	var/obj/item/matter_decompiler/MD = new /obj/item/matter_decompiler(src)
	rel_set(MD, nameof(MD.metal), metal)
	rel_set(MD, nameof(MD.glass), glass)
	own_add(src, nameof(modules), MD)

	var/obj/item/stack/material/cyborg/steel/M = new (src)
	rel_add(M, nameof(M.synths), metal)
	own_add(src, nameof(modules), M)

	var/obj/item/stack/material/cyborg/glass/G = new (src)
	rel_add(G, nameof(G.synths), glass)
	own_add(src, nameof(modules), G)

	var/obj/item/stack/rods/cyborg/rods = new /obj/item/stack/rods/cyborg(src)
	rel_add(rods, nameof(rods.synths), metal)
	own_add(src, nameof(modules), rods)

	var/obj/item/stack/cable_coil/cyborg/C = new /obj/item/stack/cable_coil/cyborg(src)
	rel_add(C, nameof(C.synths), wire)
	own_add(src, nameof(modules), C)

	var/obj/item/stack/material/cyborg/plasteel/PS = new (src)
	rel_add(PS, nameof(PS.synths), plasteel)
	own_add(src, nameof(modules), PS)

	var/obj/item/stack/tile/wood/cyborg/WT = new /obj/item/stack/tile/wood/cyborg(src)
	rel_add(WT, nameof(WT.synths), wood)
	own_add(src, nameof(modules), WT)

	var/obj/item/stack/tile/floor/cyborg/S = new /obj/item/stack/tile/floor/cyborg(src)
	rel_add(S, nameof(S.synths), metal)
	own_add(src, nameof(modules), S)

	var/obj/item/stack/tile/roofing/cyborg/CT = new /obj/item/stack/tile/roofing/cyborg(src)
	rel_add(CT, nameof(CT.synths), metal)
	own_add(src, nameof(modules), CT)

	var/obj/item/stack/material/cyborg/glass/reinforced/RG = new (src)
	rel_add(RG, nameof(RG.synths), metal)
	rel_add(RG, nameof(RG.synths), glass)
	own_add(src, nameof(modules), RG)

	var/obj/item/stack/material/cyborg/plastic/PL = new (src)
	rel_add(PL, nameof(PL.synths), plastic)
	own_add(src, nameof(modules), PL) //CHOMEdit End

/obj/item/robot_module/robot/malf/gravekeeper/handle_special_unlocks(mob/living/silicon/robot/owner_robot)
	if(!owner_robot.emag_items)
		owner_robot.scramble_hardware(10)
	if (owner_robot.churn_count == 5)
		own_add(src, nameof(emag), new /obj/item/self_repair_system/advanced(src))
		owner_robot.hud_used.update_robot_modules_display()
