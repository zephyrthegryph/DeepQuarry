use byond_dmb::{bytecode, dmb::Dmb};
use std::{env, fs};
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let a = env::args().collect::<Vec<_>>();
    let d = Dmb::from_bytes(&fs::read(&a[1])?)?;
    for (id, p) in d.procs.iter().enumerate() {
        let path = String::from_utf8_lossy(d.string(p.strings[0]).unwrap_or_default());
        if a[2..].iter().any(|x| path.ends_with(x)) {
            println!("{id} {path}");
            for i in
                bytecode::decode(d.proc_code_words(id).unwrap()).map_err(|e| format!("{e:?}"))?
            {
                println!("{:04x} {:x} {:?}", i.offset, i.opcode, i.operands);
            }
        }
    }
    Ok(())
}
