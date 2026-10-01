/proc/output_literal(var/mob/M)
    M << "hello"
/proc/output_number(var/mob/M)
    M << 5
/proc/output_variable(var/mob/M,var/x)
    M << x
/proc/output_computed(var/mob/M,var/x)
    M << x+1
