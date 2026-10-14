use byond_dmb::dmb::Dmb;

fn target(dmb: &Dmb, kind: u8, id: u32) -> String {
    let class_id = if kind == 8 {
        dmb.mobs[id as usize].class
    } else {
        id
    };
    let class = &dmb.classes[class_id as usize];
    String::from_utf8_lossy(dmb.string(class.path_string_id()).unwrap_or_default()).into_owned()
}

fn main() {
    let path = std::env::args().nth(1).expect("DMB path");
    let dmb = Dmb::from_bytes(&std::fs::read(path).unwrap()).unwrap();
    for (class_id, class) in dmb.classes.iter().enumerate() {
        let owner = String::from_utf8_lossy(dmb.string(class.path_string_id()).unwrap_or_default());
        if !owner.starts_with("/datum/type_tag_fixture") {
            continue;
        }
        for (var_id, _) in dmb
            .class_variable_declarations(class_id)
            .unwrap_or_default()
        {
            let variable = &dmb.variables[var_id as usize];
            let name = String::from_utf8_lossy(dmb.string(variable.name).unwrap_or_default());
            if name.starts_with("tag_") {
                println!(
                    "{owner}.{name}: kind={} id={} target={}",
                    variable.kind,
                    variable.value,
                    target(&dmb, variable.kind, variable.value)
                );
            }
        }
        for item in dmb.class_initial_values(class_id).unwrap_or_default() {
            let variable = &dmb.variables[item.variable_id as usize];
            let name = String::from_utf8_lossy(dmb.string(variable.name).unwrap_or_default());
            if name.starts_with("tag_") {
                let value = item.value;
                println!(
                    "{owner}.{name} override: tag={} id={} target={}",
                    value.tag(),
                    value.id(),
                    target(&dmb, value.tag(), value.id())
                );
            }
        }
    }
}
