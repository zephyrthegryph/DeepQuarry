/obj/cable
 icon_state="0-1"
 var/d1=0
 var/d2=1
/obj/base
/obj/base/proc/Initialize(mapload)
 return 1
/obj/cable
 parent_type=/obj/base
/obj/cable/Initialize(mapload)
 . = ..()
 var/dash=findtext(icon_state,"-")
 d1=text2num(copytext(icon_state,1,dash))
 d2=text2num(copytext(icon_state,dash+1))
 var/turf/T=src.loc
 if(T)
  T.is_plating()
 power_register()
/obj/cable/proc/power_register()
 world.log << "REGISTER state=[icon_state] d1=[d1] d2=[d2] null1=[isnull(d1)] null2=[isnull(d2)]"
/turf/proc/is_plating()
 return 1
/obj/cable/proc/parse()
 var/dash=findtext(icon_state,"-")
 var/left=copytext(icon_state,1,dash)
 var/right=copytext(icon_state,dash+1)
 d1=text2num(left)
 d2=text2num(right)
 world.log << "CABLE state=[icon_state] dash=[dash] left=[left] right=[right] d1=[d1] d2=[d2] null1=[isnull(d1)] null2=[isnull(d2)]"
 return list(d1,d2)
/obj/cable/green
 color="#00ff00"
/obj/cable/green/deep
 alpha=200
/world/New()
 for(var/obj/cable/M in world)
  world.log << "MAPPED cable"
  world.log << "BEFORE mapped type=[M.type] state=[M.icon_state] d1=[M.d1] d2=[M.d2] null1=[isnull(M.d1)] null2=[isnull(M.d2)]"
  M.Initialize(1)
  M.parse()
 var/obj/cable/C=new /obj/cable/green/deep
 world.log << "BEFORE created type=[C.type] state=[C.icon_state] d1=[C.d1] d2=[C.d2] null1=[isnull(C.d1)] null2=[isnull(C.d2)]"
 C.Initialize(0)
 C.parse()
 world.log << "CONSTANT text2num0=[text2num("0")] text2num1=[text2num("1")] copy=[copytext("0-1",1,2)] parsed=[text2num(copytext("0-1",1,2))]"
 del(world)




