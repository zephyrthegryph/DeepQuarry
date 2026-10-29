#define SCHEMA(T,V,K)
#define TRACKED_SCHEMA(T,V,K)
#define SYSTEM_DEF(T)
#define NATIVE_ONE /atom/var/native_unkept = 0
#define NATIVE_TWO /atom/var/native_kept = 0 // ALLOW(base_vars): fixture intentionally keeps the macro declared instance field
/atom
    var/base_plain
    var/schema_value
    var/raw_schema
    var/hidden_hint
    var/not_value
    var/schema_disabled
    var/list/list_kept = list() // ALLOW(instance_list): fixture deliberately keeps this list allocation for the owner
    var/list/base_kept = list() // ALLOW(base_vars): fixture intentionally keeps this base type list field
    var/static/list/shared = list() // ALLOW(base_vars): static storage must not consume this annotation
    var/list/last_default = null
    last_default = list()
SCHEMA(/atom, schema_value, map_of(schema_text(), schema_path(/obj), nullable = 1))
SCHEMA(/atom, not_value, schema_ref(/obj))
NATIVE_ONE
NATIVE_TWO // ALLOW(base_vars): fixture intentionally keeps the macro declared instance field
/datum/ordinary
    var/scalar // ALLOW(base_vars): raw declarations consume keeps even without typed candidate status
    var/list/cache = list()
/datum/controller/probe
    var/list/cache = list()
SYSTEM_DEF(fixture)
/datum/system/fixture
    var/list/cache = list()
#if 0
/datum/inactive
    var/scalar // ALLOW(base_vars): inactive source declarations still consume their raw policy keeps
SCHEMA(/atom, schema_disabled, num())
#endif
/datum/record/fixture/proc/business()
    return
/datum/record/fixture/proc/set_value()
    return
