use byond_dmb::{bytecode, dmb::Dmb};

fn main() {
    let mut args = std::env::args().skip(1);
    let path = args.next().expect("DMB path");
    let filter = args.next().expect("procedure path filter");
    let dmb = Dmb::from_bytes(&std::fs::read(path).unwrap()).unwrap();
    for (id, proc_) in dmb.procs.iter().enumerate() {
        let name = String::from_utf8_lossy(dmb.string(proc_.strings[0]).unwrap_or_default());
        if !name.contains(&filter) {
            continue;
        }
        println!("proc#{id} {name}");
        if let Some(words) = dmb.proc_code_words(id) {
            for instruction in bytecode::decode(words).unwrap() {
                println!(
                    "  {:04} {:03x} {:?}",
                    instruction.offset, instruction.opcode, instruction.operands
                );
            }
        }
    }
}
