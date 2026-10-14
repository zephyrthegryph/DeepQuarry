use byond_dmb::dmb::Dmb;
fn main() {
    let dmb = Dmb::from_bytes(&std::fs::read(std::env::args().nth(1).unwrap()).unwrap()).unwrap();
    for (class_id, class) in dmb.classes.iter().enumerate() {
        let path = dmb.string(class.path_string_id()).unwrap_or_default();
        if path == b"/datum/a"
            || path == b"/datum/b"
            || path == b"/datum/a/child"
            || path == b"/datum/a/child/grandchild"
            || path == b"/obj/fixture/defaults"
            || path == b"/obj/fixture/defaults/child"
            || path == b"/obj/item/spacecash"
            || path == b"/mob/fixture/eyes"
            || path == b"/mob/fixture/eyes/child"
            || path == b"/area/fixture/glow"
            || path == b"/mob/dview"
            || path == b"/obj/fixture/transform"
            || path == b"/obj/item/projectile/energy/flash"
            || path == b"/obj/structure/bed/chair/sofa"
            || path == b"/area"
            || path == b"/obj/machinery/chemical_dispenser"
            || path == b"/obj/machinery/computer/arcade"
            || path == b"/obj/item/storage/box/fluff"
            || path == b"/obj/item/rcd"
        {
            println!("class {} {}", class_id, String::from_utf8_lossy(path));
            for (var_id, flags) in dmb
                .class_variable_declarations(class_id)
                .unwrap_or_default()
            {
                let var = &dmb.variables[var_id as usize];
                println!(
                    "  var {var_id} {} flags={flags} kind={} value={}",
                    String::from_utf8_lossy(dmb.string(var.name).unwrap()),
                    var.kind,
                    var.value
                );
            }
            println!(
                "  initial {:?}",
                dmb.class_initial_values(class_id)
                    .unwrap_or_default()
                    .iter()
                    .map(|v| (v.variable_id, v.value))
                    .collect::<Vec<_>>()
            );
            for entry in dmb.class_initial_values(class_id).unwrap_or_default() {
                let name = dmb
                    .string(dmb.variables[entry.variable_id as usize].name)
                    .unwrap_or_default();
                if [
                    b"ambience".as_slice(),
                    b"modes",
                    b"has_items",
                    b"prizes",
                    b"dispense_reagents",
                ]
                .contains(&name)
                {
                    println!(
                        "  target initial {} {:?}",
                        String::from_utf8_lossy(name),
                        entry.value
                    );
                }
            }
            for value in dmb.class_initial_values(class_id).unwrap_or_default() {
                if value.value.tag() == 62 {
                    println!(
                        "  hidden initializer payload={} list={:?} string={:?} proc={:?} var={:?}",
                        value.value.id(),
                        dmb.lists.get(value.value.id() as usize),
                        dmb.string(value.value.id()),
                        dmb.procs.get(value.value.id() as usize).map(|p| p.strings),
                        dmb.variables
                            .get(value.value.id() as usize)
                            .map(|v| (v.kind, v.name))
                    );
                }
            }
            println!(
                "  transform flag={} values={:?}",
                class.transform_flag, class.transform
            );
            println!(
                "  overrides {:?}",
                dmb.class_builtin_overrides(class_id)
                    .unwrap_or_default()
                    .iter()
                    .map(|v| (
                        String::from_utf8_lossy(dmb.string(v.name_string_id).unwrap()).into_owned(),
                        v.value
                    ))
                    .collect::<Vec<_>>()
            );
            if let Some(mob) = dmb.mobs.iter().find(|mob| mob.class == class_id as u32) {
                println!(
                    "  mob sight={:?} dark={:?} invisible={:?}",
                    mob.sight_bits(),
                    mob.see_in_dark_setting(),
                    mob.see_invisible_setting()
                );
            }
        }
    }
}
