//! BYOND's builtin vars and procs (`/atom/var/layer`, `/world/var/fps`, `/datum/proc/New`, the global constants such as `AREA_LAYER`):
//! the declarations no source file makes. The semantic tree holds the builtin types but not these members, and the lints ask for them
//! like any other (`var_decl("/atom", "loc")`, `proc_ref("/datum", "New")`). `builtins.tsv` is the table, one line per member:
//!
//! - `V <type> <name> <declares 0|1> <declared type> <flag bits> <constant>`: a var (flags: 1 static, 2 const, 4 tmp; the constant
//!   `-` none, `null`, `f:<number>`, `s:<text>`, `r:<resource>`, `o` another kind).
//! - `P <type> <name> <declares 0|1> <verb 0|1> <parameter,...>`: a proc (declares: the builtin declaration is on this type).
//!
//! Fields are tab-separated; `\t`, `\n` and `\\` are escaped in text. The table was written from SpacemanDMM's builtin table (the one the
//! converted tree carries) by `analyze sem builtins-dump`, so both models answer the same.

use std::collections::HashMap;
use std::sync::OnceLock;

/// A var's constant value, as far as the lints read one.
#[derive(Clone, Debug, PartialEq)]
pub enum Const {
    Null,
    Float(f32),
    String(String),
    Resource(String),
    Other,
}

#[derive(Clone, Debug)]
pub struct BuiltinVar {
    pub declares: bool,
    pub declared: String,
    pub flags: u32,
    pub constant: Option<Const>,
}

#[derive(Clone, Debug)]
pub struct BuiltinProc {
    pub declares: bool,
    pub verb: bool,
    pub parameters: Vec<String>,
}

#[derive(Default)]
pub struct Builtins {
    /// type -> (name, var) in table order.
    pub vars: HashMap<String, Vec<(String, BuiltinVar)>>,
    pub procs: HashMap<String, Vec<(String, BuiltinProc)>>,
}

impl Builtins {
    pub fn var(&self, ty: &str, name: &str) -> Option<&BuiltinVar> {
        self.vars.get(ty)?.iter().find(|(n, _)| n == name).map(|(_, v)| v)
    }

    pub fn proc(&self, ty: &str, name: &str) -> Option<&BuiltinProc> {
        self.procs.get(ty)?.iter().find(|(n, _)| n == name).map(|(_, p)| p)
    }
}

const TABLE: &str = include_str!("builtins.tsv");

pub fn get() -> &'static Builtins {
    static B: OnceLock<Builtins> = OnceLock::new();
    B.get_or_init(|| parse(TABLE))
}

fn unescape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars();
    while let Some(c) = chars.next() {
        if c == '\\' {
            match chars.next() {
                Some('t') => out.push('\t'),
                Some('n') => out.push('\n'),
                Some(other) => out.push(other),
                None => out.push('\\'),
            }
        } else {
            out.push(c);
        }
    }
    out
}

fn escape(s: &str) -> String {
    s.replace('\\', "\\\\").replace('\t', "\\t").replace('\n', "\\n")
}

fn parse(text: &str) -> Builtins {
    let mut b = Builtins::default();
    for line in text.lines() {
        let f: Vec<&str> = line.split('\t').collect();
        match f.as_slice() {
            ["V", ty, name, declares, declared, flags, constant] => {
                let constant = match *constant {
                    "-" => None,
                    "null" => Some(Const::Null),
                    "o" => Some(Const::Other),
                    c => Some(match c.split_once(':') {
                        Some(("f", n)) => Const::Float(n.parse().unwrap_or(0.0)),
                        Some(("s", t)) => Const::String(unescape(t)),
                        Some(("r", t)) => Const::Resource(unescape(t)),
                        _ => Const::Other,
                    }),
                };
                let var = BuiltinVar { declares: *declares == "1", declared: declared.to_string(), flags: flags.parse().unwrap_or(0), constant };
                b.vars.entry(ty.to_string()).or_default().push((unescape(name), var));
            }
            ["P", ty, name, declares, verb, params] => {
                let parameters = if params.is_empty() { Vec::new() } else { params.split(',').map(unescape).collect() };
                let proc = BuiltinProc { declares: *declares == "1", verb: *verb == "1", parameters };
                b.procs.entry(ty.to_string()).or_default().push((unescape(name), proc));
            }
            _ => {}
        }
    }
    b
}

/// The table from the converted tree's builtins (`analyze sem builtins-dump`).
pub fn dump(sem: &crate::sem::Sem) -> String {
    use dreammaker::constants::Constant;
    let mut out = String::new();
    let mut types: Vec<_> = sem.objtree.iter_types().collect();
    types.sort_by(|a, b| a.get().path.cmp(&b.get().path));
    for ty in types {
        let t = ty.get();
        let path = if t.path.is_empty() { "/".to_string() } else { t.path.clone() };
        for (name, v) in &t.vars {
            let builtin_value = v.value.location.is_builtins();
            let builtin_declaration = v.declaration.as_ref().is_some_and(|d| d.location.is_builtins());
            if !builtin_value && !builtin_declaration {
                continue;
            }
            let (declares, declared, flags) = match v.declaration.as_ref().filter(|d| d.location.is_builtins()) {
                Some(d) => {
                    let declared = if d.var_type.type_path.is_empty() { String::new() } else { format!("/{}", d.var_type.type_path.join("/")) };
                    (1, declared, u32::from(d.var_type.flags.is_static()) | u32::from(d.var_type.flags.is_const()) << 1 | u32::from(d.var_type.flags.is_tmp()) << 2)
                }
                None => (0, String::new(), 0),
            };
            let constant = match v.value.constant.as_ref().filter(|_| builtin_value) {
                None => "-".to_string(),
                Some(Constant::Null(_)) => "null".to_string(),
                Some(Constant::Float(n)) => format!("f:{n}"),
                Some(Constant::String(s)) => format!("s:{}", escape(s)),
                Some(Constant::Resource(s)) => format!("r:{}", escape(s)),
                Some(_) => "o".to_string(),
            };
            out.push_str(&format!("V\t{path}\t{}\t{declares}\t{declared}\t{flags}\t{constant}\n", escape(name)));
        }
        for (name, p) in &t.procs {
            let Some(value) = p.value.iter().find(|v| v.location.is_builtins()) else { continue };
            let declares = p.declaration.as_ref().is_some_and(|d| d.location.is_builtins());
            let verb = p.declaration.as_ref().is_some_and(|d| d.kind == dreammaker::ast::ProcDeclKind::Verb);
            let params: Vec<String> = value.parameters.iter().map(|q| escape(&q.name)).collect();
            out.push_str(&format!("P\t{path}\t{}\t{}\t{}\t{}\n", escape(name), u8::from(declares), u8::from(verb), params.join(",")));
        }
    }
    out
}
