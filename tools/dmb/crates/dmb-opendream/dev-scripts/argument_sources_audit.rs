use byond_dmb::dmb::Dmb;
use std::collections::HashMap;

fn main() {
    let path = std::env::args().nth(1).expect("DMB path");
    let dmb = Dmb::from_bytes(&std::fs::read(path).unwrap()).unwrap();
    let mut kinds = HashMap::<u32, usize>::new();
    for (proc_id, proc) in dmb.procs.iter().enumerate() {
        for arg in dmb.proc_arguments(proc_id).unwrap_or_default() {
            if arg.value_source != 0x7d01 {
                *kinds.entry(arg.value_source).or_default() += 1;
                let path = dmb.string(proc.strings[0]).map(String::from_utf8_lossy);
                let name = dmb
                    .string(dmb.variables[arg.variable_id as usize].name)
                    .map(String::from_utf8_lossy);
                println!(
                    "{path:?} arg={name:?} source={:04x} ref={:?}",
                    arg.value_source,
                    dmb.argument_source_proc_id(&arg)
                );
            }
        }
    }
    println!("source codes={kinds:?}");
}
