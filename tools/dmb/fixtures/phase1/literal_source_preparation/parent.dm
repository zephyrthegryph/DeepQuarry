#if ENABLE_CHILD
#define VALUE 4
#define FILE_DIR "inner-assets"
#include "nested.dm"
#undef FILE_DIR
#endif
/datum/preparation_probe
    var/value = VALUE
