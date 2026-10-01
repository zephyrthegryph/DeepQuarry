use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::PathBuf;

fn const_name(name: &str) -> String {
    let mut out = String::new();
    let mut previous_lower = false;
    for ch in name.chars() {
        if ch.is_ascii_uppercase() && previous_lower {
            out.push('_');
        }
        out.push(ch.to_ascii_uppercase());
        previous_lower = ch.is_ascii_lowercase() || ch.is_ascii_digit();
    }
    out
}

fn main() {
    println!("cargo:rerun-if-changed=src/opcodes.txt");
    let source = fs::read_to_string("src/opcodes.txt").expect("read opcode registry");
    let mut seen = HashMap::<String, u32>::new();
    let mut output =
        String::from("// Generated from src/opcodes.txt; edit that registry instead.\n");
    for (line_number, line) in source.lines().enumerate() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let mut parts = line.split_whitespace();
        let code = parts.next().expect("opcode number");
        let name = parts.next().expect("opcode name");
        let number = u32::from_str_radix(code, 16)
            .unwrap_or_else(|_| panic!("invalid opcode on line {}", line_number + 1));
        let base = const_name(name);
        let identifier = if seen.insert(base.clone(), number).is_some() {
            format!("{base}_AT_{number:X}")
        } else {
            base
        };
        output.push_str(&format!("pub const {identifier}: u32 = 0x{number:X};\n"));
    }
    let path = PathBuf::from(env::var_os("OUT_DIR").expect("Cargo output directory"));
    fs::write(path.join("opcodes_generated.rs"), output).expect("write opcode constants");
}
