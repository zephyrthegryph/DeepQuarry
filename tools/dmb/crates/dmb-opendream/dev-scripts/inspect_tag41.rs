use byond_dmb::dmb::Dmb;

fn main() {
    let path = std::env::args().nth(1).expect("DMB path");
    let dmb = Dmb::from_bytes(&std::fs::read(path).unwrap()).unwrap();
    let mut shown = 0;
    for (owner_id, owner) in dmb.classes.iter().enumerate() {
        for item in dmb.class_initial_values(owner_id).unwrap_or_default() {
            if item.value.tag() != 41 {
                continue;
            }
            let var = &dmb.variables[item.variable_id as usize];
            let name = String::from_utf8_lossy(dmb.string(var.name).unwrap_or_default());
            let owner_path =
                String::from_utf8_lossy(dmb.string(owner.path_string_id()).unwrap_or_default());
            let payload = item.value.id();
            let instance = dmb.instances.get(payload as usize);
            let target = instance
                .and_then(|instance| {
                    let class = if instance.kind == 8 {
                        dmb.mobs.get(instance.class as usize)?.class
                    } else {
                        instance.class
                    };
                    dmb.classes.get(class as usize)
                })
                .and_then(|class| dmb.string(class.path_string_id()))
                .map(String::from_utf8_lossy);
            println!(
                "{owner_path}.{name} payload={} instance_kind={:?} initializer={:?} target={:?}",
                payload,
                instance.map(|v| v.kind),
                instance.map(|v| v.initializer),
                target
            );
            shown += 1;
            if shown >= 30 {
                return;
            }
        }
    }
}
