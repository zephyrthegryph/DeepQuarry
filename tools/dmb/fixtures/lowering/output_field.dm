/proc/output_field(var/mob/M)
    M.client << "hello"
/proc/output_field_computed(var/mob/M,var/x)
    M.client << x+1
