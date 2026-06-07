/obj/structure/largecrate
	name = "large crate"
	desc = "A hefty wooden crate."
	icon = 'icons/obj/storage.dmi'
	icon_state = "densecrate"
	density = TRUE
	var/list/starts_with

/obj/structure/largecrate/Initialize(mapload)
	. = ..()
	if(starts_with)
		create_objects_in_loc(src, starts_with)
		starts_with = null
	for(var/obj/I in src.loc)
		if(I.density || I.anchored || I == src || !I.simulated)
			continue
		I.forceMove(src)
	update_icon()

/obj/structure/largecrate/attack_hand(mob/user as mob)
	to_chat(user, span_notice("You need a crowbar to pry this open!"))
	return

/obj/structure/largecrate/attackby(obj/item/W as obj, mob/user as mob)
	var/turf/T = get_turf(src)
	if(!T)
		to_chat(user, span_notice("You can't open this here!"))
	if(W.has_tool_quality(TOOL_CROWBAR))
		new /obj/item/stack/material/wood(src)

		for(var/atom/movable/AM in contents)
			if(AM.simulated)
				AM.forceMove(T)
			//VOREStation Add Start
			if(isanimal(AM))
				var/mob/living/simple_mob/AMBLINAL = AM
				if(!AMBLINAL.mind)
					AMBLINAL.ghostjoin = 1
					AMBLINAL.ghostjoin_icon()
					GLOB.active_ghost_pods |= AMBLINAL
			//VOREStation Add End
		user.visible_message(span_notice("[user] pries \the [src] open."), \
								span_notice("You pry open \the [src]."), \
								span_notice("You hear splitting wood."))
		qdel(src)
	else
		return attack_hand(user)

/obj/structure/largecrate/mule
	name = "MULE crate"

/obj/structure/largecrate/hoverpod
	name = "\improper Hoverpod assembly crate"
	desc = "You aren't sure how this crate is so light, but the Wulf Aeronautics logo might be a hint."
	icon_state = "vehiclecrate"

/obj/structure/largecrate/hoverpod/attackby(obj/item/W as obj, mob/user as mob)
	if(W.has_tool_quality(TOOL_CROWBAR))
		var/obj/item/mecha_parts/mecha_equipment/ME
		var/obj/mecha/working/hoverpod/H = new (loc)

		ME = new /obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp
		ME.attach(H)
		ME = new /obj/item/mecha_parts/mecha_equipment/tool/passenger
		ME.attach(H)
	..()

/obj/structure/largecrate/donksoftvendor
	name = "\improper Donk-Soft vendor crate"
	desc = "A hefty wooden crate displaying the logo of Donk-Soft. It's rather heavy."
	starts_with = list(/obj/machinery/vending/donksoft)

/obj/structure/largecrate/lasertag_turrets
	name = "lasertag turret crate"
	desc = "A hefty wooden crate displaying the logo of Laz-co. It's rather heavy."
	starts_with = list(/obj/machinery/porta_turret/lasertag/blue, /obj/machinery/porta_turret/lasertag/red, /obj/machinery/porta_turret/lasertag/omni)

/obj/structure/largecrate/vehicle
	name = "vehicle crate"
	desc = "Wulf Aeronautics says it comes in a box for the consumer's sake... How is this so light?"
	icon_state = "vehiclecrate"

/obj/structure/largecrate/vehicle/Initialize(mapload)
	. = ..()
	for(var/obj/O in contents)
		O.update_icon()

/obj/structure/largecrate/vehicle/bike
	name = "spacebike crate"
	starts_with = list(/obj/structure/vehiclecage/spacebike)

/obj/structure/largecrate/vehicle/quadbike
	name = "\improper ATV crate"
	desc = "A hefty wooden crate proudly displaying the logo of Ward-Takahashi's automotive division."
	starts_with = list(/obj/structure/vehiclecage/quadbike)

/obj/structure/largecrate/vehicle/quadtrailer
	name = "\improper ATV trailer crate"
	desc = "A hefty wooden crate proudly displaying the logo of Ward-Takahashi's automotive division."
	starts_with = list(/obj/structure/vehiclecage/quadtrailer)

/obj/structure/largecrate/animal
	icon_state = "crittercrate"
	desc = "A hefty wooden crate with air holes. It is marked with the logo of NanoTrasen Pastures and the slogan, '90% less cloning defects* than competing brands**, or your money back***!'"

/obj/structure/largecrate/animal/mulebot
	name = "Mulebot crate"
	desc = "A hefty wooden crate labelled 'Proud Product of the Xion Manufacturing Group'"
	icon_state = "mulecrate"
	starts_with = list(/mob/living/bot/mulebot)

/obj/structure/largecrate/animal/corgi
	name = "corgi carrier"
	starts_with = list(/mob/living/simple_mob/animal/passive/dog/corgi)

/obj/structure/largecrate/animal/cow
	name = "cow crate"
	starts_with = list(/mob/living/simple_mob/animal/passive/cow)

/obj/structure/largecrate/animal/goat
	name = "goat crate"
	starts_with = list(/mob/living/simple_mob/animal/goat)

/obj/structure/largecrate/animal/cat
	name = "cat carrier"
	starts_with = list(/mob/living/simple_mob/animal/passive/cat)

/obj/structure/largecrate/animal/cat/bones
	starts_with = list(/mob/living/simple_mob/animal/passive/cat/bones)

/obj/structure/largecrate/animal/chick
	name = "chicken crate"
	starts_with = list(/mob/living/simple_mob/animal/passive/chick = 5)

/obj/structure/largecrate/animal/turkey
	name = "turkey crate"
	starts_with = list(/mob/living/simple_mob/vore/turkey)

/obj/structure/largecrate/animal/catslug
	name = "catslug carrier"
	starts_with = list(/mob/living/simple_mob/vore/alienanimals/catslug)

/obj/structure/largecrate/animal/mothroach
	name = "mothroach carrier"
	starts_with = list(/mob/living/simple_mob/animal/passive/mothroach)

/obj/structure/largecrate/anomaly
	name = "anomaly harvesting crate"
	starts_with = list(
		/obj/machinery/anomaly_harvester,
		/obj/item/anomaly_releaser/science,
		/obj/item/assembly/signaler/anomaly/choice/,
		/obj/item/anomaly_scanner
	)


// === merged from largecrate_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/structure/largecrate/birds //This is an awful hack, but it's the only way to get multiple mobs spawned in one crate.
	name = "Bird crate"
	desc = "You hear chirping and cawing inside the crate. It sounds like there are a lot of birds in there..."

/obj/structure/largecrate/birds/attackby(obj/item/W as obj, mob/user as mob)
	if(W.has_tool_quality(TOOL_CROWBAR))
		new /obj/item/stack/material/wood(src)
		new /mob/living/simple_mob/animal/passive/bird(src)
		new /mob/living/simple_mob/animal/passive/bird/parrot/kea(src)
		new /mob/living/simple_mob/animal/passive/bird/parrot/eclectus(src)
		new /mob/living/simple_mob/animal/passive/bird/parrot/grey_parrot(src)
		new /mob/living/simple_mob/animal/passive/bird/parrot/black_headed_caique(src)
		new /mob/living/simple_mob/animal/passive/bird/parrot/white_caique(src)
		new /mob/living/simple_mob/animal/passive/bird/parrot/budgerigar(src)
		new /mob/living/simple_mob/animal/passive/bird/parrot/budgerigar/blue(src)
		new /mob/living/simple_mob/animal/passive/bird/parrot/budgerigar/bluegreen(src)
		new /mob/living/simple_mob/animal/passive/bird/black_bird(src)
		new /mob/living/simple_mob/animal/passive/bird/azure_tit(src)
		new /mob/living/simple_mob/animal/passive/bird/european_robin(src)
		new /mob/living/simple_mob/animal/passive/bird/goldcrest(src)
		new /mob/living/simple_mob/animal/passive/bird/ringneck_dove(src)
		new /mob/living/simple_mob/animal/passive/bird/parrot/cockatiel(src)
		new /mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/white(src)
		new /mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/yellowish(src)
		new /mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/grey(src)
		new /mob/living/simple_mob/animal/passive/bird/parrot/sulphur_cockatoo(src)
		new /mob/living/simple_mob/animal/passive/bird/parrot/white_cockatoo(src)
		new /mob/living/simple_mob/animal/passive/bird/parrot/pink_cockatoo(src)
		var/turf/T = get_turf(src)
		for(var/atom/movable/AM in contents)
			if(AM.simulated) AM.forceMove(T)
		user.visible_message(span_notice("[user] pries \the [src] open."), \
								span_notice("You pry open \the [src]."), \
								span_notice("You hear splitting wood."))
		qdel(src)
	else
		return attack_hand(user)

/obj/structure/largecrate/animal/pred
	name = "Predator carrier"
	starts_with = list(/mob/living/simple_mob/vore/catgirl)

/obj/structure/largecrate/animal/pred/Initialize(mapload) //This is nessesary to get a random one each time.
	starts_with = list(pick(/mob/living/simple_mob/vore/bee,
						/mob/living/simple_mob/vore/catgirl;3,
						/mob/living/simple_mob/vore/aggressive/frog,
						/mob/living/simple_mob/vore/horse,
						/mob/living/simple_mob/vore/aggressive/panther,
						/mob/living/simple_mob/vore/aggressive/giant_snake,
						/mob/living/simple_mob/vore/wolf,
						/mob/living/simple_mob/animal/space/bear;0.5,
						/mob/living/simple_mob/animal/space/carp,
						/mob/living/simple_mob/vore/aggressive/mimic,
						/mob/living/simple_mob/vore/aggressive/rat,
						/mob/living/simple_mob/vore/aggressive/rat/tame,
						/mob/living/simple_mob/vore/aggressive/rat/labrat, //CHOMPEdit
						/mob/living/simple_mob/vore/zorgoia, //CHOMPstation edit
						/mob/living/simple_mob/vore/rabbit,
						/mob/living/simple_mob/vore/weretiger;0.5,
//						/mob/living/simple_mob/vore/otie;0.5
						))
	return ..()

/obj/structure/largecrate/animal/dangerous
	name = "Dangerous Predator carrier"
	starts_with = list(/mob/living/simple_mob/animal/space/alien)

/obj/structure/largecrate/animal/dangerous/Initialize(mapload)
	starts_with = list(pick(/mob/living/simple_mob/animal/space/carp/large,
						/mob/living/simple_mob/vore/aggressive/deathclaw,
						/mob/living/simple_mob/vore/aggressive/dino,
						/mob/living/simple_mob/animal/space/alien,
						/mob/living/simple_mob/animal/space/alien/drone,
						/mob/living/simple_mob/animal/space/alien/sentinel,
						/mob/living/simple_mob/animal/space/alien/queen,
						/mob/living/simple_mob/vore/otie/feral, //ChompEDIT uncomment
						/mob/living/simple_mob/vore/otie/feral/chubby, //ChompEDIT add
						/mob/living/simple_mob/vore/otie/red, //ChompEDIT uncomment
						/mob/living/simple_mob/vore/aggressive/corrupthound))
	return ..()

/obj/structure/largecrate/animal/guardbeast
	name = "VARMAcorp autoNOMous security solution"
	desc = "The VARMAcorp bioengineering division flagship product on trained optimal snowflake guard dogs."
	icon = 'icons/obj/storage_vr.dmi'
	icon_state = "sotiecrate"
	starts_with = list(/mob/living/simple_mob/vore/otie/security)

/obj/structure/largecrate/animal/otie/guardbeast/Initialize(mapload)
	starts_with = list(pick(/mob/living/simple_mob/vore/otie/security,
						/mob/living/simple_mob/vore/otie/security/chubby))
	return ..()

/obj/structure/largecrate/animal/guardmutant
	name = "VARMAcorp autoNOMous security solution for hostile environments."
	desc = "The VARMAcorp bioengineering division flagship product on trained optimal snowflake guard dogs. This one can survive hostile atmosphere."
	icon = 'icons/obj/storage_vr.dmi'
	icon_state = "sotiecrate"
	starts_with = list(/mob/living/simple_mob/vore/otie/security/phoron)

/obj/structure/largecrate/animal/otie/guardmutant/Initialize(mapload)
	starts_with = list(pick(/mob/living/simple_mob/vore/otie/security/phoron;2,
						/mob/living/simple_mob/vore/otie/security/phoron/red;0.5,
						/mob/living/simple_mob/vore/otie/security/phoron/red/chubby;0.5))
	return ..()

/obj/structure/largecrate/animal/otie
	name = "VARMAcorp adoptable reject (Dangerous!)"
	desc = "A warning on the side says the creature inside was returned to the supplier after injuring or devouring several unlucky members of the previous adoption family. It was given a second chance with the next customer. Godspeed and good luck with your new pet!"
	icon = 'icons/obj/storage_vr.dmi'
	icon_state = "otiecrate2"
	starts_with = list(/mob/living/simple_mob/vore/otie/cotie)
	var/taped = 1

/obj/structure/largecrate/animal/otie/Initialize(mapload)
	starts_with = list(pick(/mob/living/simple_mob/vore/otie/cotie,
						/mob/living/simple_mob/vore/otie/cotie/chubby))
	return ..()

/obj/structure/largecrate/animal/otie/phoron
	name = "VARMAcorp adaptive beta subject (Experimental)"
	desc = "VARMAcorp experimental hostile environment adaptive breeding development kit. WARNING, DO NOT RELEASE IN WILD!"
	starts_with = list(/mob/living/simple_mob/vore/otie/cotie/phoron)

/obj/structure/largecrate/animal/otie/phoron/Initialize(mapload)
	starts_with = list(pick(/mob/living/simple_mob/vore/otie/cotie/phoron;2,
						/mob/living/simple_mob/vore/otie/red/friendly;0.5,
						/mob/living/simple_mob/vore/otie/red/chubby;0.5)) //ChompEDIT add
	return ..()

/obj/structure/largecrate/animal/otie/attack_hand(mob/living/carbon/human/M as mob)//I just couldn't decide between the icons lmao
	if(taped == 1)
		playsound(src, 'sound/items/poster_ripped.ogg', 50, 1)
		icon_state = "otiecrate"
		taped = 0
	..()

/obj/structure/largecrate/animal/catgirl
	name = "Catgirl Crate"
	desc = "A sketchy looking crate with airholes that seems to have had most marks and stickers removed. You can almost make out 'genetically-engineered subject' written on it."
	starts_with = list(/mob/living/simple_mob/vore/catgirl)

/obj/structure/largecrate/animal/wolfgirl
	name = "Wolfgirl Crate"
	desc = "A sketchy looking crate with airholes that shakes and thuds every now and then. Someone seems to be demanding they be let out."
	starts_with = list(/mob/living/simple_mob/vore/wolfgirl)

/obj/structure/largecrate/animal/fennec
	name = "Fennec Crate"
	desc = "Bounces around a lot. Looks messily packaged, were they in a hurry?"
	starts_with = list(/mob/living/simple_mob/vore/fennec)

/obj/structure/largecrate/animal/fennec/Initialize(mapload)
	starts_with = list(pick(/mob/living/simple_mob/vore/fennec,
						/mob/living/simple_mob/vore/fennix;0.5))
	return ..()

/obj/structure/largecrate/animal/jerboa
	name = "Jerboa Crate"
	desc = "Lots, and lots of squeaking."
	starts_with = list(/mob/living/simple_mob/animal/passive/mouse/jerboa)

/obj/structure/largecrate/animal/weretiger
	name = "Weretiger Crate"
	desc = "You can hear a lot of annoyed scratches, clearly someone doesn't enjoy being locked up."
	starts_with = list(/mob/living/simple_mob/vore/weretiger)

/obj/structure/largecrate/tits
	name = "A pair of Great tits"
	desc = "You can hear two round things inside"
	starts_with = list (/mob/living/simple_mob/animal/passive/bird/azure_tit/great, /mob/living/simple_mob/animal/passive/bird/azure_tit/great)
