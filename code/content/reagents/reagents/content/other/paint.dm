/datum/reagent/paint
	name = REAGENT_PAINT
	id = REAGENT_ID_PAINT
	description = "This paint will stick to almost any object."
	taste_description = "chalk"
	reagent_state = LIQUID
	dermal_absorption = 0 //NOOOOOOOOOOO
	color = "#808080"
	overdose = REAGENTS_OVERDOSE * 0.5
	color_weight = 20
	scannable = SCANNABLE_ADVANCED
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_COSMETIC

/datum/reagent/paint/touch_turf(turf/T)
	..()
	if(istype(T) && !istype(T, /turf/space))
		T.set_color(color)

/datum/reagent/paint/touch_obj(obj/O)
	..()
	if(istype(O))
		O.set_color(color)

/datum/reagent/paint/touch_mob(mob/M)
	..()
	if(istype(M) && !istype(M, /mob/observer)) //painting ghosts: not allowed
		M.set_color(color) //maybe someday change this to paint only clothes and exposed body parts for human mobs.

/datum/reagent/paint/get_data()
	return color

/datum/reagent/paint/initialize_data(newdata)
	set_color(newdata)
	return

/datum/reagent/paint/mix_data(newdata, newamount)
	var/list/colors = list(0, 0, 0, 0)
	var/tot_w = 0

	var/hex1 = uppertext(color)
	var/hex2 = uppertext(newdata)
	if(length(hex1) == 7)
		hex1 += "FF"
	if(length(hex2) == 7)
		hex2 += "FF"
	if(length(hex1) != 9 || length(hex2) != 9)
		return
	colors[1] += hex2num(copytext(hex1, 2, 4)) * volume
	colors[2] += hex2num(copytext(hex1, 4, 6)) * volume
	colors[3] += hex2num(copytext(hex1, 6, 8)) * volume
	colors[4] += hex2num(copytext(hex1, 8, 10)) * volume
	tot_w += volume
	colors[1] += hex2num(copytext(hex2, 2, 4)) * newamount
	colors[2] += hex2num(copytext(hex2, 4, 6)) * newamount
	colors[3] += hex2num(copytext(hex2, 6, 8)) * newamount
	colors[4] += hex2num(copytext(hex2, 8, 10)) * newamount
	tot_w += newamount

	set_color(rgb(colors[1] / tot_w, colors[2] / tot_w, colors[3] / tot_w, colors[4] / tot_w))
	return
