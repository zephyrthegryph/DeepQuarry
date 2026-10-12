use byond_dmb::dmb::Dmb;

fn main() {
    let path = std::env::args().nth(1).expect("DMB path");
    let dmb = Dmb::from_bytes(&std::fs::read(path).unwrap()).unwrap();
    for (id, proc) in dmb.procs.iter().enumerate() {
        let name = String::from_utf8_lossy(dmb.string(proc.strings[0]).unwrap_or_default());
        if name.contains("/proc/stub_") {
            println!("{name}: {:?}", dmb.proc_code_words(id).unwrap_or_default());
        }
    }
}
