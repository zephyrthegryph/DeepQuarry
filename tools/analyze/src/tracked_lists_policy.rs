//! Exact tracked-list declaration/lookalike selection and output policy.
//! Shared by legacy and captured producers; semantic ownership stays external.
use crate::{tree::SourceFile,pat_match,sparse_slots_policy::Output};
/// One TRACKED list var: the type that declares it and the var.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, serde::Serialize, serde::Deserialize, Default)]
pub struct Decl {
    pub ty: String,
    pub var: String,
    pub rel: String,
    pub line: u32,
}

/// The `TRACKED(T, v)` declaration lines of one file.
pub fn declarations_in(f:&SourceFile)->Vec<Decl>{let mut out=Vec::new();visit_declarations(f.text(),&f.rel,&mut crate::key_policy_control::Compatibility,&mut|_,ty,var,line|{out.push(Decl{ty:ty.to_owned(),var:var.to_owned(),rel:f.rel.clone(),line});Ok(())}).unwrap_or_else(|never|match never{});out}
fn declaration_pattern()->&'static crate::pat::Pat{pat_match!(r"TRACKED\(\s*(/[\w/]+)\s*,\s*(\w+)\s*\)")}
/// SAME literal line selector; callbacks retain identifiers only after admission.
pub fn visit_declarations<C:crate::key_policy_control::Control>(raw:&str,_relative:&str,c:&mut C,emit:&mut impl FnMut(&mut C,&str,&str,u32)->Result<(),C::Error>)->Result<(),C::Error>{
 if !raw.contains("TRACKED"){return c.checkpoint()}
 crate::key_policy_control::reserve(c,||declaration_pattern().capture_group_count().checked_mul(4)?.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(std::mem::size_of::<crate::pat::Caps<'_>>()+128))?;
 for(i,line)in raw.lines().enumerate(){c.checkpoint()?;let text=line.trim_start();if text.starts_with('#')||text.starts_with("//"){continue}if let Some(m)=declaration_pattern().captures(text){let line=if C::CHECKED{u32::try_from(i).ok().and_then(|n|n.checked_add(1)).ok_or_else(||c.overflow())?}else{i as u32+1};emit(c,m.s(1).trim_end_matches('/'),m.s(2),line)?;}}
 c.checkpoint()
}

/// The procs and the version var for one list var.
pub fn emit(out: &mut Output, d: &Decl) {
    let (t, v) = (&d.ty, &d.var);
    let tail = |out: &mut Output| {
        out.line_fmt(format_args!("\t{}_version++", v));
        out.line_fmt(format_args!("\ttracked_changed(src, \"{}\")",d.var));
        out.line("\treturn TRUE");
    };
    out.doc_fmt(format_args!("TRACKED({}, {}) at {}:{}: the list's version, bumped by every change through add_{}, include_{}, remove_{}, set_{}_at, clear_{}, insert_{}, swap_{} and cut_{}.", t, v, d.rel, d.line, v, v, v, v, v, v, v, v));
    out.line_fmt(format_args!("{}/var/{}_version = 0 // ALLOW(base_vars): a tracked list's version counter (TRACKED, tools/analyze/src/gens/tracked_lists.rs)", t, v));
    out.line_fmt(format_args!("{}/proc/add_{}(x)", t, v));
    out.line_fmt(format_args!("\tif(isnull({}))", v));
    out.line_fmt(format_args!("\t\t{} = list()", v));
    out.line_fmt(format_args!("\t{} += x", v));
    tail(out);
    out.line_fmt(format_args!("{}/proc/include_{}(x)", t, v));
    out.line_fmt(format_args!("\tvar/was_null = isnull({})", v));
    out.line_fmt(format_args!("\tvar/before = length({})", v));
    out.line("\tif(was_null)");
    out.line_fmt(format_args!("\t\t{} = list()", v));
    out.line_fmt(format_args!("\t{} |= x", v));
    out.line_fmt(format_args!("\tif(length({}) == before)", v));
    out.line("\t\tif(was_null)");
    out.line_fmt(format_args!("\t\t\t{} = null", v));
    out.line("\t\treturn FALSE");
    tail(out);
    out.line_fmt(format_args!("{}/proc/remove_{}(x)", t, v));
    out.line_fmt(format_args!("\tvar/before = length({})", v));
    out.line("\tif(!before)");
    out.line("\t\treturn FALSE");
    out.line_fmt(format_args!("\t{} -= x", v));
    out.line_fmt(format_args!("\tif(length({}) == before)", v));
    out.line("\t\treturn FALSE");
    tail(out);
    out.line_fmt(format_args!("{}/proc/set_{}_at(index, x)", t, v));
    out.line_fmt(format_args!("\tif(isnull({}))", v));
    out.line_fmt(format_args!("\t\t{} = list()", v));
    out.line_fmt(format_args!("\tvar/had = isnum(index) || (index in {})", v));
    out.line_fmt(format_args!("\tif(had && TRACKED_UNCHANGED({}[index], x))", v));
    out.line("\t\treturn FALSE");
    out.line_fmt(format_args!("\t{}[index] = x", v));
    tail(out);
    out.line_fmt(format_args!("{}/proc/insert_{}(index, x)", t, v));
    out.line_fmt(format_args!("\tif(isnull({}))", v));
    out.line_fmt(format_args!("\t\t{} = list()", v));
    out.line_fmt(format_args!("\t{}.Insert(index, x)", v));
    tail(out);
    out.line_fmt(format_args!("{}/proc/swap_{}(a, b)", t, v));
    out.line_fmt(format_args!("\tif(a == b || !length({}))", v));
    out.line("\t\treturn FALSE");
    out.line_fmt(format_args!("\t{}.Swap(a, b)", v));
    tail(out);
    out.line_fmt(format_args!("{}/proc/cut_{}(start = 1, end = 0)", t, v));
    out.line_fmt(format_args!("\tvar/before = length({})", v));
    out.line("\tif(!before)");
    out.line("\t\treturn FALSE");
    out.line_fmt(format_args!("\t{}.Cut(start, end)", v));
    out.line_fmt(format_args!("\tif(length({}) == before)", v));
    out.line("\t\treturn FALSE");
    tail(out);
    out.line_fmt(format_args!("{}/proc/clear_{}()", t, v));
    out.line_fmt(format_args!("\tif(!length({}))", v));
    out.line("\t\treturn FALSE");
    out.line_fmt(format_args!("\t{}.Cut()", v));
    tail(out);
    out.blank();
}

/// A proc definition whose name looks generated (`add_x`, `set_x_at`, ...), by file: `(line, type if written on the line, name)`.
pub fn lookalike_candidates(relative:&str,raw:&str)->bool{relative!="code/engine/_generated/tracked_lists.dm"&&(raw.contains("proc/")||raw.contains("_at("))}
pub fn lookalikes(f:&SourceFile)->Vec<(u32,String,String)>{if !lookalike_candidates(&f.rel,f.text()){return Vec::new()}let mut out=Vec::new();visit_lookalikes(&f.code().text,&mut crate::key_policy_control::Compatibility,&mut|_,line,owner,name|{out.push((line,owner.to_owned(),name.to_owned()));Ok(())}).unwrap_or_else(|never|match never{});out}
/// SAME top/nested generated-name matcher over the original code view.
pub fn visit_lookalikes<C:crate::key_policy_control::Control>(code:&str,c:&mut C,emit:&mut impl FnMut(&mut C,u32,&str,&str)->Result<(),C::Error>)->Result<(),C::Error>{
 let top=crate::pat!(r"^(/[\w/]*?)/(?:proc/)?((?:add|include|remove|clear|insert|swap|cut)_\w+|set_\w+_at)\s*\(");let nested=crate::pat!(r"^\s+(?:proc/)((?:add|include|remove|clear|insert|swap|cut)_\w+|set_\w+_at)\s*\(");
 crate::key_policy_control::reserve(c,||top.capture_group_count().max(nested.capture_group_count()).checked_mul(4)?.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(std::mem::size_of::<crate::pat::Caps<'_>>()+128))?;
 for(i,line)in code.lines().enumerate(){c.checkpoint()?;let point=if C::CHECKED{u32::try_from(i).ok().and_then(|n|n.checked_add(1)).ok_or_else(||c.overflow())?}else{i as u32+1};if let Some(m)=top.captures(line){emit(c,point,m.s(1),m.s(2))?}else if let Some(m)=nested.captures(line){emit(c,point,"",m.s(1))?}}c.checkpoint()
}
