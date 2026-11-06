// Type metadata defaults: the types whose instances run slot hooks (slot_hooks_enabled()).
/datum/type_metadata_registry/register_defaults()
	register(/obj/item/organ, TYPE_META_SLOT_HOOKS, TRUE)
