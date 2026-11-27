//! BYOND's builtin types, vars and procs as SpacemanDMM knows them (`builtins.txt`, dumped from dreammaker's `builtins.rs` table by
//! [`dump_dreammaker`] and checked against it by `tests/builtins_dump.rs`). One record per line, in the table's registration order:
//!
//! - `T <path>`: a type.
//! - `V <owner> <name> <flags> <type>`: a declared var (`<owner>` `/` is the root; `<type>` the declared type's pieces joined by `/`,
//!   `-` for none), optionally followed by ` = <value>` for a constant (`f <number>` or `s <text>`).
//! - `v <owner> <name>`: a value for a builtin var declared on a parent.
//! - `P <owner> <name> <kind> <parameters>`: a proc value (`<kind>` `proc`, `verb` or `-` for an override; parameters joined by `,`).
use super::model::{ModelBuilder, Param, ProcDecl, ProcKind, ProcValue, ReturnType, VarFlags};
use dm::Location;

const TEXT: &str = include_str!("builtins.txt");

/// A builtin constant's value: what BYOND's predefined macro for it expands to.
#[derive(Clone, Debug, PartialEq)]
pub enum ConstValue {
    Number(f32),
    Text(String),
}

fn owner_path(owner: &str) -> &str {
    if owner == "/" {
        ""
    } else {
        owner
    }
}

/// Register every builtin record.
pub fn register(b: &mut ModelBuilder) {
    for line in TEXT.lines() {
        let mut parts = line.splitn(2, ' ');
        let (Some(tag), Some(rest)) = (parts.next(), parts.next()) else { continue };
        match tag {
            "T" => {
                b.add_type_path(Location::builtins(), rest);
            }
            "V" => {
                let (decl, _value) = rest.split_once(" = ").map_or((rest, None), |(d, v)| (d, Some(v)));
                let f: Vec<&str> = decl.split(' ').collect();
                let ty = b.add_type_path(Location::builtins(), owner_path(f[0]));
                let flags = VarFlags(f[2].parse().unwrap_or(0));
                let type_path = if f[3] == "-" { Vec::new() } else { f[3].split('/').map(str::to_owned).collect() };
                b.builtin_var(ty, f[1], Some((flags, type_path)));
            }
            "v" => {
                let f: Vec<&str> = rest.split(' ').collect();
                let ty = b.add_type_path(Location::builtins(), owner_path(f[0]));
                b.builtin_var(ty, f[1], None);
            }
            "P" => {
                let f: Vec<&str> = rest.splitn(4, ' ').collect();
                let ty = b.add_type_path(Location::builtins(), owner_path(f[0]));
                let declaration = match f[2] {
                    "proc" => Some(ProcKind::Proc),
                    "verb" => Some(ProcKind::Verb),
                    _ => None,
                }
                .map(|kind| ProcDecl { kind, is_final: false, location: Location::builtins(), return_type: ReturnType::None });
                let parameters = f
                    .get(3)
                    .filter(|p| !p.is_empty() && **p != "-")
                    .map(|p| p.split(',').map(|n| Param { name: n.to_owned(), type_path: Vec::new(), location: Location::default() }).collect())
                    .unwrap_or_default();
                b.add_proc(ty, f[1], declaration, ProcValue { location: Location::builtins(), parameters, body: None });
            }
            _ => {}
        }
    }
}

/// The builtin global constants (`NORTH`, `WAVE_SIDEWAYS`) and their values: the names SpacemanDMM reads as global vars where
/// dmbc's preprocessor expands its predefined macros.
pub fn constants() -> &'static foldhash::HashMap<String, ConstValue> {
    static TABLE: std::sync::OnceLock<foldhash::HashMap<String, ConstValue>> = std::sync::OnceLock::new();
    TABLE.get_or_init(|| {
        let mut out = foldhash::HashMap::default();
        for line in TEXT.lines() {
            let Some(rest) = line.strip_prefix("V / ") else { continue };
            let Some((decl, value)) = rest.split_once(" = ") else { continue };
            let name = decl.split(' ').next().unwrap_or("");
            let value = match value.split_once(' ') {
                Some(("f", n)) => n.parse().ok().map(ConstValue::Number),
                Some(("s", t)) => Some(ConstValue::Text(t.to_owned())),
                _ => None,
            };
            if let Some(value) = value {
                out.insert(name.to_owned(), value);
            }
        }
        out
    })
}

/// dreammaker's builtin table in this file's format.
pub fn dump_dreammaker() -> String {
    use std::fmt::Write as _;
    let tree = dm::objtree::ObjectTree::with_builtins();
    let mut out = String::new();
    let owner = |t: dm::objtree::TypeRef| if t.is_root() { "/".to_owned() } else { t.path.clone() };
    for t in tree.iter_types() {
        if !t.is_root() {
            let _ = writeln!(out, "T {}", t.path);
        }
    }
    for t in tree.iter_types() {
        for (name, var) in t.vars.iter() {
            match &var.declaration {
                Some(decl) => {
                    let flags = decl.var_type.flags;
                    let mut bits = 0u8;
                    if flags.is_static() {
                        bits |= VarFlags::STATIC;
                    }
                    if flags.is_const() {
                        bits |= VarFlags::CONST;
                    }
                    if flags.is_tmp() {
                        bits |= VarFlags::TMP;
                    }
                    if flags.is_final() {
                        bits |= VarFlags::FINAL;
                    }
                    if flags.is_private() {
                        bits |= VarFlags::PRIVATE;
                    }
                    if flags.is_protected() {
                        bits |= VarFlags::PROTECTED;
                    }
                    let ty = if decl.var_type.type_path.is_empty() { "-".to_owned() } else { decl.var_type.type_path.join("/") };
                    let _ = write!(out, "V {} {name} {bits} {ty}", owner(t));
                    match &var.value.constant {
                        Some(dm::constants::Constant::Float(n)) => {
                            let _ = write!(out, " = f {n}");
                        }
                        Some(dm::constants::Constant::String(s)) => {
                            let _ = write!(out, " = s {s}");
                        }
                        _ => {}
                    }
                    out.push('\n');
                }
                None => {
                    let _ = writeln!(out, "v {} {name}", owner(t));
                }
            }
        }
        for (name, proc) in t.procs.iter() {
            for (i, value) in proc.value.iter().enumerate() {
                let kind = match (&proc.declaration, i) {
                    (Some(d), 0) => d.kind.name(),
                    _ => "-",
                };
                let params: Vec<&str> = value.parameters.iter().map(|p| p.name.as_str()).collect();
                let _ = writeln!(out, "P {} {name} {kind} {}", owner(t), if params.is_empty() { "-".to_owned() } else { params.join(",") });
            }
        }
    }
    out
}
