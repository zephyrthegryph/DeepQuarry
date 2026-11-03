//! Unique original Initialize policy, shared by legacy and borrowed workspace adapters.
use crate::{tree::SourceFile,pat_match,dm::{sys::col0,pylines::py_splitlines},util::{before_slashes,py_lstrip},key_policy_control::{self as kc,Control}};
/// One file's part of the table-init pass: its `init_from_table` flags `(type, on)` in file order,
/// and its `Initialize()` / `LateInitialize()` headers `(line, type)` that no ALLOW(init) kept.
#[derive(serde::Serialize,serde::Deserialize,Default,PartialEq)]
pub(crate) struct TableFacts {
    pub(crate) flags: Vec<(String, bool)>,
    pub(crate) headers: Vec<(u32, String)>,
}

pub(crate) fn table_facts(f:&SourceFile)->TableFacts{table_facts_using(f,&mut kc::Compatibility,&mut|lines,number|Ok(crate::dm::pylines::allowed_in_recorded(f,lines,number,"init"))).unwrap_or_else(|never|match never{})}
pub(crate) fn table_facts_using<C:Control>(f:&SourceFile,control:&mut C,allowed:&mut impl FnMut(&[&str],usize)->Result<bool,C::Error>)->Result<TableFacts,C::Error>{
 control.checkpoint()?;
    let init_header = pat_match!(r"^(/[\w/]+)/Initialize\s*\(");
    let late_header = pat_match!(r"^(/[\w/]+)/LateInitialize\s*\(");
    let type_block = pat_match!(r"^(/[\w/]+)\s*(//.*)?$");
    let table_flag = pat_match!(r"^\s+init_from_table\s*=\s*(TRUE|FALSE|1|0)\b");
    let mut out = TableFacts::default();
    let lines = crate::dm::pylines::py_splitlines_using(f.text(),control)?;
    let mut block: Option<String> = None;
    for (i, line) in lines.iter().enumerate() {
        control.checkpoint()?;
        let number = i + 1;
        let line = *line;
        if let Some(head) = type_block.captures(line) {
            if !line.contains('(') {
                block = Some(kc::own(control,head.s(1))?);
                continue;
            }
        }
        if col0(line) {
            block = None;
        }
        if let Some(flag) = table_flag.captures(line) {
            if let Some(b) = &block {
                kc::row(control,&mut out.flags)?;out.flags.push((kc::own(control,b)?,matches!(flag.s(1),"TRUE"|"1")));
            }
        }
        let header = init_header.captures(line).or_else(|| late_header.captures(line));
        if let Some(h) = header {
            // Asked for every header, not only one that would count.
            if !allowed(&lines,number)? {
                kc::row(control,&mut out.headers)?;out.headers.push((number as u32,kc::own(control,h.s(1))?));
            }
        }
    }
    Ok(out)
}

/// The reason codes an `ALLOW(init/CODE)` keep may carry (also listed in `[lint.init] reason_codes`):
/// INSTANCE_STATE (a value only this instance has: a map edit, a random roll, a copy of where it is built), CTOR_ARGS (it
/// consumes extra constructor arguments), FRAMEWORK (a base of the init chain itself).
pub const REASON_CODES: &[&str] = &["INSTANCE_STATE", "CTOR_ARGS", "FRAMEWORK"];

/// The code of an `ALLOW(init/CODE): reason` on `line`, Some("") for a bare `ALLOW(init): reason`, None for no keep.
pub(crate) fn init_code(line:&str)->Option<String>{init_code_using(line,&mut kc::Compatibility).unwrap_or_else(|never|match never{})}
fn init_code_using<C:Control>(line:&str,control:&mut C)->Result<Option<String>,C::Error>{
    Ok(match crate::allow::parse_with(line,control)? {
        Some(a) if !a.reason.is_empty() && a.names.contains("init") => Some(a.codes.get("init").cloned().unwrap_or_default()),
        _ => None,
    })
}

/// The owner a header line names (`/obj/x/Initialize(` is `/obj/x`); empty when the line writes none.
pub(crate) fn text_owner(line: &str) -> String {
    let init_header = pat_match!(r"^(/[\w/]+)/Initialize\s*\(");
    init_header.captures(line).map(|c| c.s(1).to_string()).unwrap_or_default()
}

/// The atom built-ins `SETTER()`-registered in code/game/atom/atom_visual.dm.
const VISUAL_SETTER_VARS: &[&str] = &["color", "alpha", "layer", "plane", "pixel_x", "pixel_y", "pixel_w", "pixel_z", "appearance_flags", "gender"];

/// What an `init_lines` statement is about, for its identity (`owner::Initialize::target`):
///
/// * a write `x = v`, `src.x += v`, `var/T/x = v` or the call of its setter `set_x(v)`: the var `x` (so converting a write to its setter,
///   which the `tracked` lint asks for, is the same site; `a.b = v` is `a.b`);
/// * a call `proc(args)`, `src.proc(args)`, `obj.proc(args)`, `PROC_REF` macros included: the callee;
/// * control flow (`if`, `else`, `for`, `while`, `switch`, ...): the keyword, so editing a condition keeps the site;
/// * `return v`: `return`;
/// * anything else (the argument lines of a multi-line call, a bare expression): `expr`.
///
/// Sites that share a target share an identity; the ratchet counts them per identity, so a fix still shrinks the count and a new
/// line of the same target still fails once the count is exceeded.
pub fn init_line_target(stmt: &str) -> String {
    let t = stmt.trim();
    let control = pat_match!(r"^(else\s+if|if|else|for|while|switch|do|try|catch|spawn)\b");
    if let Some(c) = control.captures(t) {
        return c.s(1).split_whitespace().collect::<Vec<_>>().join(" ");
    }
    if pat_match!(r"^return\b").is_match(t) {
        return "return".to_string();
    }
    let t = t.strip_prefix("src.").unwrap_or(t);
    // `var/list/x = ...` / `var/x`: the declared name.
    let decl = pat_match!(r"^var/(?:[\w/]*/)?(\w+)\s*(?:=|$|\[)");
    if let Some(c) = decl.captures(t) {
        return c.s(1).to_string();
    }
    let assign = pat_match!(r"^(\.|[A-Za-z_][\w.\[\]]*)\s*(?:\|\||&&|<<|>>|[-+*/%|&^])?=(?:[^=]|$)");
    if let Some(c) = assign.captures(t) {
        return c.s(1).to_string();
    }
    let call = pat_match!(r"^([A-Za-z_][\w.:]*)\s*\(");
    if let Some(c) = call.captures(t) {
        let callee = c.s(1);
        if let Some(var) = callee.strip_prefix("set_") {
            if !var.is_empty() && !var.contains('.') {
                return var.to_string();
            }
        }
        // `obj.set_color(v)` is the write `obj.color = v` converted to its registered visual setter (code/game/atom/atom_visual.dm): the same
        // site (`a.b`). Only those: `cell.set_charge(v)` is a call like any other.
        if let Some((recv, last)) = callee.rsplit_once('.') {
            if let Some(var) = last.strip_prefix("set_") {
                if VISUAL_SETTER_VARS.contains(&var) && !recv.is_empty() {
                    return format!("{recv}.{var}");
                }
            }
        }
        return callee.to_string();
    }
    "expr".to_string()
}

/// A definition header as the text rule reads one (`/type/Initialize(` at column 0; a commented-out line is not one).
pub(crate) fn text_header(line: &str) -> Option<Def> {
    let init_header = pat_match!(r"^(/[\w/]+)/Initialize\s*\(");
    let late_header = pat_match!(r"^(/[\w/]+)/LateInitialize\s*\(");
    let turf_materialize = pat_match!(r"^/turf(/[\w/]*)?/on_materialize\s*\(");
    if line.starts_with("//") {
        return None;
    }
    if turf_materialize.is_match(line) {
        Some(Def::TurfMaterialize)
    } else if late_header.is_match(line) {
        Some(Def::Late)
    } else if init_header.is_match(line) {
        Some(Def::Init)
    } else {
        None
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Def {
    Init,
    Late,
    TurfMaterialize,
}


pub(crate) fn table_violation_using<C:Control>(path:&str,lookup:&impl Fn(&str)->Option<bool>,control:&mut C)->Result<bool,C::Error>{
 kc::reserve(control,||path.len().checked_add(1)?.checked_mul(4*std::mem::size_of::<&str>())?.checked_add(128))?;let parts:Vec<_>=path.split('/').collect();for cut in(2..=parts.len()).rev(){control.checkpoint()?;kc::reserve(control,||path.len().checked_add(128))?;let ancestor=parts[..cut].join("/");if let Some(on)=lookup(&ancestor){return Ok(on&&cut!=parts.len())}}Ok(false)
}

pub(crate) trait Output<E>{fn site(&mut self,rule:&'static str,line:usize,message:String,identity:String)->Result<(),E>;fn allowed(&mut self,lines:&[&str],line:usize)->Result<bool,E>;}
pub(crate) fn judge_definition_using<C:Control,O:Output<C::Error>>(lines:&[&str],number:usize,kind:Def,owner:&str,control:&mut C,out:&mut O)->Result<(),C::Error>{
    control.checkpoint()?;
        match kind {
            Def::TurfMaterialize => out.site("turf_on_materialize",number,String::new(),String::new())?,
            Def::Late => out.site("late_initialize",number,String::new(),String::new())?,
            Def::Init => {
                let line = lines.get(number - 1).copied().unwrap_or("");
                let above = if number > 1 { lines[number - 2] } else { "" };
                let code=match init_code_using(line,control)?{Some(code)=>Some(code),None if py_lstrip(above).starts_with("//")=>init_code_using(above,control)?,None=>None};
                match code {
                    Some(c) if REASON_CODES.contains(&c.as_str()) => {
                        out.allowed(lines,number)?; // records the annotation as used
                    }
                    Some(c)=>{kc::reserve(control,||c.len().checked_mul(8)?.checked_add(2048))?;let message=kc::format(control,format_args!("ALLOW(init{}) needs a reason code: ALLOW(init/CODE), CODE one of {}",if c.is_empty(){String::new()}else{format!("/{c}")},REASON_CODES.join(", ")))?;out.site("initialize",number,message,String::new())?;},
                    None => {}
                }
                let world_read = crate::pat!(r"(?<![\w.])(?:o?range|view)\s*\(|\bGetAbove\s*\(|\bGetBelow\s*\(|\bGLOB\.|\bSTART_PROCESSING\s*\(");
                for n in crate::lifecycle_source::body_lines_using(lines,number as u32,control)? {
                    control.checkpoint()?;
                    let code = before_slashes(lines[n - 1]);
                    let stmt = code.trim();
                    kc::reserve(control,||stmt.len().checked_mul(4)?.checked_add(128))?;let super_call = matches!(stmt.replace(' ', "").as_str(), ".=..()" | "..()" | "return..()" | "return" | "return.");
                    if !stmt.is_empty() && !super_call {
                        // Identified by the type, the proc and the target the line writes or calls, not by its text: see [`init_line_target`].
                        kc::reserve(control,||stmt.len().checked_mul(8)?.checked_add(owner.len())?.checked_add(2048))?;let identity=kc::format(control,format_args!("{}::Initialize::{}",owner,init_line_target(stmt)))?;out.site("init_lines",n,String::new(),identity)?;
                    }
                    if world_read.is_match(code) && !out.allowed(lines,n)? {
                        out.site("world_reads",n,String::new(),String::new())?;
                    }
                }
            }
        }
        Ok(())
    }

