use byond_dmb::dmb::Dmb;

fn main() {
    let path = std::env::args().nth(1).expect("DMB path");
    let dmb = Dmb::from_bytes(&std::fs::read(path).unwrap()).unwrap();
    for proc in &dmb.procs {
        let name = String::from_utf8_lossy(dmb.string(proc.strings[0]).unwrap_or_default());
        if name.contains("/verb/v_") {
            println!(
                "{name}: source_kind={} parameter={} flags={}",
                proc.source_kind, proc.source_parameter, proc.flags
            );
        }
    }
}
