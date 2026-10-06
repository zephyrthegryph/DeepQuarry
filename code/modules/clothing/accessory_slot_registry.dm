/*
 * /datum/accessory_slot_registry
 *
 * Central registry for accessory slot definitions and clothing stat modifiers.
 *
 * Slots are defined as compile-time bitflags (ACCESSORY_SLOT_* in items_clothing.dm).
 * The registry wraps them in a query API so clothing subtypes can ask
 * "does this clothing have a free slot of this type?" without inline bitmath,
 * and so accessories can register stat modifiers that are applied/reverted
 * declaratively rather than through ad-hoc on_attached/on_removed proc chains.
 *
 * Public API:
 *   register_slot(slot_flag, slot_name)
 *     — Registers a new slot constant with a human-readable name.
 *       The compile-time bitflag must be declared in items_clothing.dm.
 *
 *   get_slot_name(slot_flag)       — Returns the display name for a slot flag.
 *   get_valid_slots(clothing)      — Returns the valid_accessory_slots bitfield.
 *   has_free_slot(clothing, flags) — TRUE if all bits in flags are available.
 *
 *   register_modifier(accessory, clothing, /datum/accessory_stat_modifier)
 *     — Registers a stat modifier applied when accessory is attached to clothing.
 *   remove_modifiers(accessory, clothing)
 *     — Reverts all modifiers registered by accessory on clothing.
 */

// Stat modifier datum — carry a closure over the values to add/remove.
/datum/accessory_stat_modifier
	/// Human-readable label for debugging.
	var/label = "modifier"
	/// Armour adjustment: armour key -> points added while applied. Null = no armour change.
	var/list/armor_delta
	/// Slowdown delta (positive = slower).
	var/slowdown_delta = 0
	/// Force delta (melee damage).
	var/force_delta = 0
	/// The clothing item this modifier was applied to.
	var/tmp/obj/item/clothing/target
	/// The registry key ("[accessory ref]:[clothing ref]") this modifier was registered under.
	var/registry_key

/datum/accessory_stat_modifier/New(obj/item/clothing/new_target, label_str)
	rel_set(src, nameof(target), new_target)
	if(label_str)
		label = label_str

/*
 * proc/apply(obj/item/clothing/clothing)
 *
 * Applies the modifier deltas to clothing.  Called by register_modifier().
 */
/datum/accessory_stat_modifier/proc/apply(obj/item/clothing/clothing)
	if(!istype(clothing))
		return
	clothing.force += force_delta
	clothing.slowdown += slowdown_delta
	if(LAZYLEN(armor_delta))
		clothing.set_armor(clothing.get_armor().add(dq_armor(armor_delta)))

/*
 * proc/revert(obj/item/clothing/clothing)
 *
 * Reverts the modifier deltas from clothing.  Called by remove_modifiers().
 */
/datum/accessory_stat_modifier/proc/revert(obj/item/clothing/clothing)
	if(!istype(clothing))
		return
	clothing.force -= force_delta
	clothing.slowdown -= slowdown_delta
	if(LAZYLEN(armor_delta))
		clothing.set_armor(clothing.get_armor().add(dq_armor(armor_delta).scaled(-1)))

/datum/accessory_slot_registry
	/// Assoc list of slot_flag (number) → display name (string).
	var/list/slot_names = list() // ALLOW(instance_list): d: singleton registry, filled at init
	/// Owned flat list of every applied /datum/accessory_stat_modifier. Each one carries its
	/// registry_key ("[accessory]:[clothing]" ref strings) so remove_modifiers() can find its set.
	var/list/active_modifiers

CAPABILITIES(/datum/accessory_slot_registry)
	owns_many(nameof(active_modifiers))

/*
 * proc/register_slot(slot_flag, slot_name)
 *
 * Registers a slot constant with a display name.  Safe to call multiple times
 * for the same flag — subsequent calls update the name.
 */
/datum/accessory_slot_registry/proc/register_slot(slot_flag, slot_name)
	slot_names["[slot_flag]"] = slot_name

/*
 * proc/get_slot_name(slot_flag)
 *
 * Returns the display name for slot_flag, or "unknown slot" if not registered.
 */
/datum/accessory_slot_registry/proc/get_slot_name(slot_flag)
	return slot_names["[slot_flag]"] || "unknown slot"

/*
 * proc/get_valid_slots(obj/item/clothing/clothing)
 *
 * Returns the valid_accessory_slots bitfield for clothing.
 * Returns 0 for non-clothing or clothing with null valid_accessory_slots.
 */
/datum/accessory_slot_registry/proc/get_valid_slots(obj/item/clothing/clothing)
	if(!istype(clothing))
		return 0
	return clothing.valid_accessory_slots || 0

/*
 * proc/has_free_slot(obj/item/clothing/clothing, flags)
 *
 * Returns TRUE if all bits in flags are both valid and not yet consumed by an
 * attached accessory.  Equivalent to clothing.can_attach_accessory() without
 * needing a concrete accessory object.
 */
/datum/accessory_slot_registry/proc/has_free_slot(obj/item/clothing/clothing, flags)
	if(!istype(clothing) || !flags)
		return FALSE

	var/valid = get_valid_slots(clothing)
	if((valid & flags) != flags)
		return FALSE

	// Check consumed restricted slots
	var/consumed_restricted = 0
	if(LAZYLEN(clothing.accessories))
		for(var/obj/item/clothing/accessory/A as anything in clothing.accessories)
			consumed_restricted |= A.slot
	consumed_restricted &= clothing.restricted_accessory_slots || 0

	return !(consumed_restricted & flags)

/*
 * proc/register_modifier(obj/item/clothing/accessory/accessory,
 *                         obj/item/clothing/clothing,
 *                         datum/accessory_stat_modifier/modifier)
 *
 * Registers and immediately applies modifier on behalf of accessory.
 * The registry owns the modifier datum and reverts it on remove_modifiers().
 */
/datum/accessory_slot_registry/proc/register_modifier(obj/item/clothing/accessory/accessory, obj/item/clothing/clothing, datum/accessory_stat_modifier/modifier)
	if(!istype(accessory) || !istype(clothing) || !istype(modifier))
		return

	rel_set(modifier, nameof(modifier.target), clothing)
	modifier.apply(clothing)

	modifier.registry_key = "[REF(accessory)]:[REF(clothing)]"
	own_move(modifier, src, nameof(active_modifiers))

/*
 * proc/remove_modifiers(obj/item/clothing/accessory/accessory,
 *                        obj/item/clothing/clothing)
 *
 * Reverts and deletes all modifiers previously registered by accessory on clothing.
 * Called from /obj/item/clothing/accessory/on_removed().
 */
/datum/accessory_slot_registry/proc/remove_modifiers(obj/item/clothing/accessory/accessory, obj/item/clothing/clothing)
	if(!length(active_modifiers))
		return

	var/key = "[REF(accessory)]:[REF(clothing)]"
	for(var/datum/accessory_stat_modifier/mod as anything in active_modifiers.Copy())
		if(mod.registry_key != key)
			continue
		mod.revert(clothing)
		rel_remove(src, nameof(active_modifiers), mod)

// remaining stat modifiers are reverted.
/datum/accessory_slot_registry/on_destroy(force)
	// Revert all remaining modifiers to leave the world consistent.
	// The modifiers themselves are owned and disposed of by the framework in phase 4.
	for(var/datum/accessory_stat_modifier/mod as anything in active_modifiers)
		mod.revert(mod.target())
	..()

/// Global singleton.  Self-initializes with built-in slot names on New().
GLOBAL_DATUM_INIT(accessory_slot_registry, /datum/accessory_slot_registry, new)

/datum/accessory_slot_registry/New()
	..()
	// Register all built-in ACCESSORY_SLOT_* constants with display names.
	register_slot(ACCESSORY_SLOT_UTILITY,  "Utility")
	register_slot(ACCESSORY_SLOT_WEAPON,   "Weapon")
	register_slot(ACCESSORY_SLOT_ARMBAND,  "Armband")
	register_slot(ACCESSORY_SLOT_RANK,     "Rank")
	register_slot(ACCESSORY_SLOT_DEPT,     "Department")
	register_slot(ACCESSORY_SLOT_DECOR,    "Decoration")
	register_slot(ACCESSORY_SLOT_MEDAL,    "Medal")
	register_slot(ACCESSORY_SLOT_TIE,      "Tie")
	register_slot(ACCESSORY_SLOT_INSIGNIA, "Insignia")
	register_slot(ACCESSORY_SLOT_OVER,     "Over-layer")
	register_slot(ACCESSORY_SLOT_ARMOR_C,  "Armor (chest)")
	register_slot(ACCESSORY_SLOT_ARMOR_A,  "Armor (arms)")
	register_slot(ACCESSORY_SLOT_ARMOR_L,  "Armor (legs)")
	register_slot(ACCESSORY_SLOT_ARMOR_S,  "Armor (shoulders)")
	register_slot(ACCESSORY_SLOT_ARMOR_M,  "Armor (main)")
	register_slot(ACCESSORY_SLOT_HELM_C,   "Helmet (crest)")
	register_slot(ACCESSORY_SLOT_RING,     "Ring")
	register_slot(ACCESSORY_SLOT_WRIST,    "Wrist")

/// the target this refers to (a relation view: null once it is deleted).
/datum/accessory_stat_modifier/proc/target() as /obj/item/clothing
	return target
