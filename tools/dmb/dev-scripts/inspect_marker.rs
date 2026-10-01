use byond_dmb::dmb::Dmb;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let dmb = Dmb::from_bytes(&std::fs::read(&args[1]).unwrap()).unwrap();
    let var_markers: std::collections::HashSet<u32> = dmb
        .variables
        .iter()
        .filter(|v| v.kind == 62)
        .map(|v| v.value)
        .collect();
    let initial_markers: std::collections::HashSet<u32> = (0..dmb.classes.len())
        .flat_map(|id| dmb.class_initial_values(id).unwrap_or_default())
        .filter(|v| v.value.tag() == 62)
        .map(|v| v.value.id())
        .collect();
    println!(
        "var records={} unique markers={} max={:?}, initial markers={} max={:?}, overlap={}",
        dmb.variables.iter().filter(|v| v.kind == 62).count(),
        var_markers.len(),
        var_markers.iter().max(),
        initial_markers.len(),
        initial_markers.iter().max(),
        var_markers.intersection(&initial_markers).count()
    );
    let builtin = (0..dmb.classes.len())
        .flat_map(|id| dmb.class_builtin_overrides(id).unwrap_or_default())
        .filter(|value| value.value.tag() == 62)
        .map(|value| value.value.id())
        .collect::<Vec<_>>();
    println!(
        "builtin markers={} unique={}",
        builtin.len(),
        builtin
            .iter()
            .collect::<std::collections::HashSet<_>>()
            .len()
    );
    if dmb.variables.len() < 300 {
        for variable in dmb.variables.iter().filter(|value| value.kind == 62) {
            println!(
                "variable marker {} {:?}",
                variable.value,
                dmb.string(variable.name).map(String::from_utf8_lossy)
            );
        }
    }
    for (class_id, class) in dmb.classes.iter().enumerate() {
        if dmb.string(class.path_string_id()) != Some(args[2].as_bytes()) {
            continue;
        }
        println!("class {class_id} init_proc={}", class.initializer_proc_id());
        for (var_id, flags) in dmb
            .class_variable_declarations(class_id)
            .unwrap_or_default()
        {
            let var = &dmb.variables[var_id as usize];
            if dmb.string(var.name) == Some(args[3].as_bytes()) {
                println!(
                    "decl {var_id} flags={flags} kind={} payload={}",
                    var.kind, var.value
                );
            }
        }
        for value in dmb.class_initial_values(class_id).unwrap_or_default() {
            let var = &dmb.variables[value.variable_id as usize];
            if dmb.string(var.name) == Some(args[3].as_bytes()) {
                println!(
                    "initial var={} tag={} payload={}",
                    value.variable_id,
                    value.value.tag(),
                    value.value.id()
                );
            }
        }
        if class.initializer_proc_id() != 0xffff {
            let words = dmb
                .proc_code_words(class.initializer_proc_id() as usize)
                .unwrap_or_default();
            println!("init words={words:?}");
        }
    }
}
