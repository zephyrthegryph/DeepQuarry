use byond_dmb::dmb::Dmb;

fn main() {
    let mut args = std::env::args().skip(1);
    let path = args.next().expect("DMB path");
    let names: Vec<String> = args.collect();
    let dmb = Dmb::from_bytes(&std::fs::read(path).unwrap()).unwrap();
    for (id, variable) in dmb.variables.iter().enumerate() {
        let name = String::from_utf8_lossy(dmb.string(variable.name).unwrap_or_default());
        if names.iter().any(|candidate| candidate == &name) {
            println!(
                "{id} {name} kind={} value={}",
                variable.kind, variable.value
            );
        }
    }
}
