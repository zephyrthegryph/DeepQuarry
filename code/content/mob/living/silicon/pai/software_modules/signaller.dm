/datum/pai_software/signaller
	name = "Remote Signaler"
	ram_cost = 5
	id = "signaller"
	toggle = 0

CAPABILITIES(/datum/pai_software/signaller)
	interface("Signaler", title = "Signaler", state = nameof(GLOB.tgui_always_state))
	ui_shape(frequency = num(), minFrequency = num(), maxFrequency = num(), code = num())
	op("signal", ui_act("signal"), then(PROC_REF(ui_act_signal)))
	op("freq", ui_act("freq", arg("freq", num())), then(PROC_REF(ui_act_freq)))
	op("code", ui_act("code", arg("code", num(1, 100))), then(PROC_REF(ui_act_code)))
	op("reset", ui_act("reset", arg("reset", schema_text(4096))), then(PROC_REF(ui_act_reset)))

/datum/pai_software/signaller/ui_data(datum/act/eval/A)
	var/mob/living/silicon/pai/user = A.actor
	var/list/data = list()

	var/obj/item/radio/integrated/signal/R = user.sradio

	data["frequency"] = R.frequency
	data["minFrequency"] = RADIO_LOW_FREQ
	data["maxFrequency"] = RADIO_HIGH_FREQ
	data["code"] = R.code

	return data

/datum/pai_software/signaller/proc/ui_act_signal(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/silicon/pai/pai = user
	if(!istype(pai))
		return
	var/obj/item/radio/integrated/signal/R = pai.sradio
	R.send_signal("ACTIVATE")
	for(var/mob/O in hearers(1, R.loc))
		O.show_message("[icon2html(R,O.client)] *beep* *beep*", 3, "*beep* *beep*", 2)

/datum/pai_software/signaller/proc/ui_act_freq(datum/act/op/A, freq)
	var/mob/user = A.actor
	var/mob/living/silicon/pai/pai = user
	if(!istype(pai))
		return
	var/obj/item/radio/integrated/signal/R = pai.sradio
	var/frequency = unformat_frequency(freq)
	frequency = sanitize_frequency(frequency, RADIO_LOW_FREQ, RADIO_HIGH_FREQ)
	R.set_frequency(frequency)
	. = TRUE

/datum/pai_software/signaller/proc/ui_act_code(datum/act/op/A, code)
	var/mob/user = A.actor
	var/mob/living/silicon/pai/pai = user
	if(!istype(pai))
		return
	var/obj/item/radio/integrated/signal/R = pai.sradio
	R.set_code(round(code))
	. = TRUE

/datum/pai_software/signaller/proc/ui_act_reset(datum/act/op/A, reset)
	var/mob/user = A.actor
	var/mob/living/silicon/pai/pai = user
	if(!istype(pai))
		return
	var/obj/item/radio/integrated/signal/R = pai.sradio
	if(reset == "freq")
		R.set_frequency(initial(R.frequency))
	else
		R.set_code(initial(R.code))
	. = TRUE
