var/global/filter_kind = "blur"
/proc/filter_values()
    filter(size=1)
    filter(type=0)
    filter(type=null)
    filter(type="__not_a_filter_type__")
    filter(type="blur",color="#ffffff")
    var/kind = "blur"
    filter(type=kind,color="#ffffff")
    kind = "outline"
    filter(type=kind,color="#ffffff")
    filter(type=global.filter_kind)
    filter(type=(kind="blur"),color="#ffffff")
    filter(type=(0 ? "blur" : "outline"),color="#ffffff")
    filter(type=astype("blur"),color="#ffffff")
    filter(type=/datum)
    filter(type=list(1))
