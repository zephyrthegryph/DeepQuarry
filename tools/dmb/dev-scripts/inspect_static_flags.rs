use byond_dmb::dmb::Dmb;

fn main() {
    let path = std::env::args().nth(1).expect("DMB path");
    let dmb = Dmb::from_bytes(&std::fs::read(path).unwrap()).unwrap();
    for (class_id, class) in dmb.classes.iter().enumerate() {
        let owner = String::from_utf8_lossy(dmb.string(class.path_string_id()).unwrap_or_default());
        if !owner.contains("temp_static_fixture") && !owner.contains("class_const_fixture") {
            continue;
        }
        for (id, flags) in dmb
            .class_variable_declarations(class_id)
            .unwrap_or_default()
        {
            let var = &dmb.variables[id as usize];
            let name = String::from_utf8_lossy(dmb.string(var.name).unwrap_or_default());
            println!("{owner}.{name}: flags={flags} kind={}", var.kind);
        }
    }
    for (id, flags) in dmb.global_variable_flags().unwrap_or_default() {
        let var = &dmb.variables[id as usize];
        let name = String::from_utf8_lossy(dmb.string(var.name).unwrap_or_default());
        if name.starts_with("TAG_") || name.starts_with("tag_") {
            println!("footer {name}: id={id} flags={flags} kind={}", var.kind);
        }
    }
}
