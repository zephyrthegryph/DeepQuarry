/obj/item/modular_computer/tablet/preset/custom_loadout/cheap/install_default_hardware()
	..()
	own_set(src, "processor_unit", new/obj/item/computer_hardware/processor_unit/small(src))
	own_set(src, "tesla_link", new/obj/item/computer_hardware/tesla_link(src))
	own_set(src, "hard_drive", new/obj/item/computer_hardware/hard_drive/micro(src))
	own_set(src, "network_card", new/obj/item/computer_hardware/network_card(src))
	own_set(src, "battery_module", new/obj/item/computer_hardware/battery_module/nano(src))
	battery_module.charge_to_full()

/obj/item/modular_computer/tablet/preset/custom_loadout/advanced/install_default_hardware()
	..()
	own_set(src, "processor_unit", new/obj/item/computer_hardware/processor_unit/small(src))
	own_set(src, "tesla_link", new/obj/item/computer_hardware/tesla_link(src))
	own_set(src, "hard_drive", new/obj/item/computer_hardware/hard_drive/small(src))
	own_set(src, "network_card", new/obj/item/computer_hardware/network_card/advanced(src))
	own_set(src, "nano_printer", new/obj/item/computer_hardware/nano_printer(src))
	own_set(src, "card_slot", new/obj/item/computer_hardware/card_slot(src))
	own_set(src, "battery_module", new/obj/item/computer_hardware/battery_module(src))
	battery_module.charge_to_full()

/obj/item/modular_computer/tablet/preset/custom_loadout/standard/install_default_hardware()
	..()
	own_set(src, "processor_unit", new/obj/item/computer_hardware/processor_unit/small(src))
	own_set(src, "tesla_link", new/obj/item/computer_hardware/tesla_link(src))
	own_set(src, "hard_drive", new/obj/item/computer_hardware/hard_drive/small(src))
	own_set(src, "network_card", new/obj/item/computer_hardware/network_card(src))
	own_set(src, "battery_module", new/obj/item/computer_hardware/battery_module/micro(src))
	battery_module.charge_to_full()


/obj/item/modular_computer/tablet/preset/custom_loadout/rugged
	name = "rugged tablet computer"
	desc = "A rugged tablet computer."
	icon = 'icons/obj/modular_tablet.dmi'
	icon_state = "rugged"
	icon_state_unpowered = "rugged"
	max_integrity = 300
	integrity_failure = 1/3 // Stops working below 100 integrity.

/obj/item/modular_computer/tablet/preset/custom_loadout/rugged/install_default_hardware()
	..()
	own_set(src, "processor_unit", new/obj/item/computer_hardware/processor_unit/small(src))
	own_set(src, "tesla_link", new/obj/item/computer_hardware/tesla_link(src))
	own_set(src, "hard_drive", new/obj/item/computer_hardware/hard_drive/small(src))
	own_set(src, "network_card", new/obj/item/computer_hardware/network_card(src))
	own_set(src, "battery_module", new/obj/item/computer_hardware/battery_module/micro(src))
	battery_module.charge_to_full()

/obj/item/modular_computer/tablet/preset/custom_loadout/elite
	name = "elite tablet computer"
	desc = "A more expensive tablet computer."
	icon = 'icons/obj/modular_tablet.dmi'
	icon_state = "elite"
	icon_state_unpowered = "elite"

/obj/item/modular_computer/tablet/preset/custom_loadout/elite/install_default_hardware()
	..()
	own_set(src, "processor_unit", new/obj/item/computer_hardware/processor_unit/small(src))
	own_set(src, "tesla_link", new/obj/item/computer_hardware/tesla_link(src))
	own_set(src, "hard_drive", new/obj/item/computer_hardware/hard_drive/small(src))
	own_set(src, "network_card", new/obj/item/computer_hardware/network_card/advanced(src))
	own_set(src, "nano_printer", new/obj/item/computer_hardware/nano_printer(src))
	own_set(src, "card_slot", new/obj/item/computer_hardware/card_slot(src))
	own_set(src, "battery_module", new/obj/item/computer_hardware/battery_module(src))
	battery_module.charge_to_full()

/obj/item/modular_computer/tablet/preset/custom_loadout/hybrid
	name = "hybrid tablet computer"
	desc = "A human/alien hybrid tech tablet computer."
	icon = 'icons/obj/modular_tablet.dmi'
	icon_state = "hybrid"
	icon_state_unpowered = "hybrid"

/obj/item/modular_computer/tablet/preset/custom_loadout/hybrid/install_default_hardware()
	..()
	own_set(src, "processor_unit", new/obj/item/computer_hardware/processor_unit/photonic/small(src))
	own_set(src, "tesla_link", new/obj/item/computer_hardware/tesla_link(src))
	own_set(src, "hard_drive", new/obj/item/computer_hardware/hard_drive/small(src))
	own_set(src, "network_card", new/obj/item/computer_hardware/network_card/advanced(src))
	own_set(src, "nano_printer", new/obj/item/computer_hardware/nano_printer(src))
	own_set(src, "card_slot", new/obj/item/computer_hardware/card_slot(src))
	own_set(src, "battery_module", new/obj/item/computer_hardware/battery_module/lambda(src))
	battery_module.charge_to_full()
