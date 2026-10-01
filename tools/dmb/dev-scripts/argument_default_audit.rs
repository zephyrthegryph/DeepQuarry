use byond_dmb::dmb::Dmb;

fn main() {
    let path = std::env::args().nth(1).expect("DMB path");
    let dmb = Dmb::from_bytes(&std::fs::read(path).unwrap()).unwrap();
    println!("proc_references={:?}", dmb.proc_references);
    for (id, proc) in dmb.procs.iter().enumerate() {
        let name = dmb.string(proc.strings[0]).map(String::from_utf8_lossy);
        let args = dmb.proc_arguments(id).unwrap_or_default();
        if proc.strings[0] == 0xffff
            || name
                .as_deref()
                .is_some_and(|name| name.contains("default_arg") || name.contains("argument_in"))
        {
            println!(
                "proc#{id} name={name:?} source=({}, {}) flags={} args={args:?} code={:?}",
                proc.source_parameter,
                proc.source_kind,
                proc.flags,
                dmb.proc_code_words(id).unwrap_or_default()
            );
            for arg in args {
                println!(
                    "  default index={:?} proc={:?}",
                    arg.source_expression_index(),
                    dmb.argument_source_proc_id(&arg)
                );
            }
        }
    }
}
