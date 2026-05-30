
/obj/machinery/artillerycontrol
	var/reload = 180
	name = "bluespace artillery control"
	icon_state = "control_boxp1"
	icon = 'icons/obj/machines/particle_accelerator2.dmi'
	density = TRUE
	anchored = TRUE

/obj/machinery/artillerycontrol/process()
	if(src.reload<180)
		src.reload++

/obj/structure/artilleryplaceholder
	name = "artillery"
	icon = 'icons/obj/machines/artillery.dmi'
	anchored = TRUE
	density = TRUE

/obj/structure/artilleryplaceholder/decorative
	density = FALSE

/obj/machinery/artillerycontrol/attack_hand(mob/user as mob)
	// DQEdit — single-action panel; tgui_alert is the right primitive.
	user.set_machine(src)
	var/choice = tgui_alert(
		user,
		"Locked on. Charge progress: [reload]/180.\n\nDeployment authorized by [using_map.company_name] Naval Command. Remember, friendly fire is grounds for termination of your contract and life.",
		"Bluespace Artillery Control",
		list("Open Fire", "Cancel"),
	)
	if(choice == "Open Fire")
		Topic("fire=1", list("fire" = "1"))

/obj/machinery/artillerycontrol/Topic(href, href_list)
	..()
	if (usr.stat || usr.restrained())
		return
	if ((usr.contents.Find(src) || (in_range(src, usr) && istype(src.loc, /turf))) || (istype(usr, /mob/living/silicon)))
		var/A = tgui_input_list(usr, "Area to jump bombard", "Open Fire", GLOB.teleportlocs)
		var/area/thearea = GLOB.teleportlocs[A]
		if (usr.stat || usr.restrained()) return
		if(src.reload < 180) return
		if ((usr.contents.Find(src) || (in_range(src, usr) && istype(src.loc, /turf))) || (istype(usr, /mob/living/silicon)))
			GLOB.command_announcement.Announce("Bluespace artillery fire detected. Brace for impact.", new_sound = ANNOUNCER_MSG_BSA_FIRED)
			message_admins("[key_name_admin(usr)] has launched an artillery strike.", 1)
			var/list/L = list()
			for(var/turf/T in get_area_turfs(thearea.type))
				L+=T
			var/loc = pick(L)
			explosion(loc,2,5,11)
			reload = 0
