// Resource ids (doc/rewrite/final_api.html, section 9, foundation X2). RESOURCE_DEF(RES_X, adapter =, schema =) declares a
// resource and its adapter; the adapters are procs and live with their domain, never here.

RESOURCE_DEF(RES_FUEL, adapter = /datum/resource/fuel)
RESOURCE_DEF(RES_USES, adapter = /datum/resource/uses)
RESOURCE_DEF(RES_CHARGE, adapter = /datum/resource/charge)
RESOURCE_DEF(RES_STACK, adapter = /datum/resource/stack)
RESOURCE_DEF(RES_ITEM, adapter = /datum/resource/item)
RESOURCE_DEF(RES_COOLDOWN, adapter = /datum/resource/cooldown)
RESOURCE_DEF(RES_BLOOD, adapter = /datum/resource/blood)
RESOURCE_DEF(RES_DARK_ENERGY, adapter = /datum/resource/dark_energy)
RESOURCE_DEF(RES_REAGENTS, adapter = /datum/resource/reagents)
RESOURCE_DEF(RES_SLOT_CAPACITY, adapter = /datum/resource/slot_capacity)
RESOURCE_DEF(RES_CREDITS, adapter = /datum/resource/credits)

#define RES_FUEL 1
#define RES_USES 2
#define RES_CHARGE 3
#define RES_STACK 4
#define RES_ITEM 5
#define RES_COOLDOWN 6
#define RES_BLOOD 7
#define RES_DARK_ENERGY 8
#define RES_REAGENTS 9
#define RES_SLOT_CAPACITY 10
#define RES_CREDITS 11
