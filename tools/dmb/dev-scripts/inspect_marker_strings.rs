use byond_dmb::dmb::Dmb;

fn main() {
    let path = std::env::args().nth(1).expect("DMB path");
    let dmb = Dmb::from_bytes(&std::fs::read(path).unwrap()).unwrap();
    for value in &dmb.strings {
        if value
            .data
            .windows(2)
            .any(|pair| pair[0] == b'K' && pair[1].is_ascii_hexdigit())
        {
            println!(
                "{}",
                value
                    .data
                    .iter()
                    .map(|byte| format!("{byte:02x}"))
                    .collect::<Vec<_>>()
                    .join(" ")
            );
        }
    }
}
