use byond_dmb::dmb::Dmb;

fn main() {
    for path in std::env::args().skip(1) {
        let dmb = Dmb::from_bytes(&std::fs::read(&path).unwrap()).unwrap();
        let value = dmb.string(dmb.world.hub_password).unwrap_or_default();
        println!("{path}: {}", String::from_utf8_lossy(value));
    }
}
