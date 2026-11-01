#define __LINE__ 99
#define __FILE__ "shadow_file"
/proc/context_shadow_dynamic_probe()
    return __FILE__ + "[__LINE__]"
#undef __FILE__
#undef __LINE__
