/obj/item/flame/candle
	name = "red candle"
	desc = "a red pillar candle. Its specially-formulated fuel-oxidizer wax mixture allows continued combustion in airless environments."
	icon = 'icons/obj/candle.dmi'
	icon_state = "candle1"
	drop_sound = SFX_ITEMS_DROP_GLOVES
	pickup_sound = SFX_ITEMS_PICKUP_GLOVES
	w_class = ITEMSIZE_TINY
	light_color = "#E09D37"
	var/wax = 7200 // FOUR HOUR burn time, taking into account process only calling once every two seconds or so.
	var/icon_type = "candle"

TRACKED(/obj/item/flame/candle, wax)

/// 1 (fresh) to 3 (nearly gone) by remaining wax.
/obj/item/flame/candle/proc/appearance_wax_stage()
	if(wax > 3600) // Icon update to match 4 hour burn
		return 1
	if(wax > 800)
		return 2
	return 3

/obj/item/flame/candle/draw(datum/look/look)
	..()
	look.state(look_state())

/// The icon state of the candle as it burns.
/obj/item/flame/candle/proc/look_state()
	return "[icon_type][appearance_wax_stage()][lit ? "_lit" : ""]"

CAPABILITIES(/obj/item/flame/candle)
	op("snuff", in_hand(), then(PROC_REF(snuffed)))
	op("light_from", item(/obj/item), passes(), when(req(PROC_REF(offers_flame))), then(PROC_REF(lit_from)))


/// The held thing is a flame that burns: a lit lighter, match or candle.
/obj/item/flame/candle/proc/offers_flame(datum/act/op/A)
	var/obj/item/W = A.held
	if(istype(W, /obj/item/flame/lighter) || istype(W, /obj/item/flame/match) || istype(W, /obj/item/flame/candle))
		var/obj/item/flame/F = W
		return !!F.lit
	return FALSE

/// A burning flame lights the candle, and the click goes on to the ordinary attack.
/obj/item/flame/candle/proc/lit_from(datum/act/op/A)
	light(user = A.actor)
	return OP_OK

/obj/item/flame/candle/welder_act(mob/user, obj/item/W)
	var/obj/item/weldingtool/WT = W.get_welder()
	if(WT.isOn())
		light(span_notice("\The [user] casually lights the [src] with [W]."))
	return TRUE


/obj/item/flame/candle/proc/light(flavor_text, mob/user)
	if(!lit)
		if(isnull(flavor_text))
			flavor_text = user ? span_notice("\The [user] lights the [src].") : span_notice("\The [src] lights up.")
		set_lit(TRUE)
		visible_message(flavor_text)
		set_light(CANDLE_LUM)

/obj/item/flame/candle/periodic_step()
	set_wax(wax - 1)
	if(!wax)
		if(istype(src.loc, /mob))
			src.dropped(src.loc)
		replace_with(src, /obj/item/trash/candle)
		return
	update_icon()
	if(istype(loc, /turf)) //start a fire if possible
		var/turf/T = loc
		T.hotspot_expose(700, 5)

/// Using a lit candle in the hand snuffs it.
/obj/item/flame/candle/proc/snuffed(datum/act/op/A)
	if(lit)
		set_lit(FALSE)
		set_light(0)
	return OP_OK

/obj/item/flame/candle/small
	name = "small red candle"
	desc = "a small red candle, for more intimate candle occasions."
	icon = 'icons/obj/candle.dmi'
	icon_state = "smallcandle"
	icon_type = "smallcandle"
	w_class = ITEMSIZE_SMALL

/obj/item/flame/candle/white
	name = "white candle"
	desc = "a white pillar candle. Its specially-formulated fuel-oxidizer wax mixture allows continued combustion in airless environments."
	icon = 'icons/obj/candle.dmi'
	icon_state = "whitecandle"
	icon_type = "whitecandle"
	w_class = ITEMSIZE_SMALL

/obj/item/flame/candle/black
	name = "black candle"
	desc = "a black pillar candle. Ominous."
	icon = 'icons/obj/candle.dmi'
	icon_state = "blackcandle"
	icon_type = "blackcandle"
	w_class = ITEMSIZE_SMALL

/obj/item/flame/candle/candelabra
	name = "candelabra"
	desc = "a small gold candelabra. The cups that hold the candles save some of the wax from dripping off, allowing the candles to burn longer."
	icon = 'icons/obj/candle.dmi'
	icon_state = "candelabra"
	w_class = ITEMSIZE_SMALL
	wax = 20000

/obj/item/flame/candle/candelabra/proc/appearance_candelabra_suffix()
	if(wax == 0)
		return "_melted"
	return lit ? "_lit" : ""

/obj/item/flame/candle/candelabra/look_state()
	return "candelabra[appearance_candelabra_suffix()]"

/obj/item/flame/candle/everburn
	wax = 99999

/obj/item/flame/candle/everburn/Initialize(mapload)
	. = ..()
	light(span_notice("\The [src] mysteriously lights itself!."))

/obj/item/flame/candle/candelabra/everburn
	wax = 99999

/obj/item/flame/candle/candelabra/everburn/Initialize(mapload)
	. = ..()
	light(span_notice("\The [src] mysteriously lights itself!."))

/obj/item/flame/candle/everburn/periodic_step()
	// The permanent light has no fuel state to advance. Leaving it in SSobj also
	// exposed its turf as a 700 K hotspot forever, keeping whole atmos regions awake.
	return PROCESS_KILL

/obj/item/flame/candle/candelabra/everburn/periodic_step()
	return PROCESS_KILL
