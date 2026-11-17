// Organised kits for the treatment items that used to have no spawn path: the stabilisation kit
// (stabilisation/field_stabilisation.dm) holds the field dressings, the two below hold the
// instruments. Medbay lockers stock them (code/content/structures/crates_lockers/closets/secure/medical.dm).

/// Airway, ventilation and chest decompression: the tools for a patient who is not breathing properly.
/obj/item/storage/firstaid/resuscitation
	name = "resuscitation kit"
	desc = "A medic's airway case: a bag-valve mask, an airway kit and decompression needles, for a patient who is not breathing properly."
	icon_state = "o2"
	item_state_slots = list(slot_r_hand_str = "firstaid-o2", slot_l_hand_str = "firstaid-o2")
	starts_with = list(
		/obj/item/bag_valve_mask = 1,
		/obj/item/airway_kit = 1,
		/obj/item/decompression_needle = 2,
	)

/// The handheld vitals instruments: a thermometer, a blood pressure cuff and a pulse oximeter.
/obj/item/storage/firstaid/diagnostic
	name = "vitals kit"
	desc = "A case of bedside instruments: a medical thermometer, a blood pressure cuff and a pulse oximeter."
	icon_state = "firstaid"
	starts_with = list(
		/obj/item/thermometer_medical = 1,
		/obj/item/bp_cuff = 1,
		/obj/item/pulse_oximeter = 1,
	)
