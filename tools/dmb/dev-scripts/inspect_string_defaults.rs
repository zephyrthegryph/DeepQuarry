use byond_dmb::dmb::Dmb;

fn main() {
    let path = std::env::args().nth(1).expect("DMB path");
    let dmb = Dmb::from_bytes(&std::fs::read(path).unwrap()).unwrap();
    for variable in &dmb.variables {
        let name = String::from_utf8_lossy(dmb.string(variable.name).unwrap_or_default());
        if !name.starts_with("tag_") {
            continue;
        }
        let bytes = dmb.string(variable.value).unwrap_or_default();
        println!("{name}: kind={} bytes={:?}", variable.kind, bytes);
    }
}
