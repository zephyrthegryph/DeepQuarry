//! ONE historical derived() entry lexical policy. This is not a DM parser or
//! source/model receipt; callers lend authentic existing raw procedure views.
use crate::{key_policy_control::{self as kc,Control},reactive_reaction_policy::Procedure,pat,util::py_strip,derived_reads_collect_policy::paren_args};
use std::collections::BTreeSet;
#[derive(Clone,Debug,PartialEq)]pub(crate) struct Entry{pub rel:String,pub line:usize,pub kind:&'static str,pub name:Option<String>,pub local:BTreeSet<String>,pub remote:Vec<(Option<String>,String)>,pub hops:Vec<String>}
const NAMEOF:&str=r"nameof\(\s*(?:(/[\w/]+)::)?(\w+)\s*\)$";
fn kind(call:&str)->&'static str{match call{"runs_while"=>"runs","drawn_from"=>"drawn","ui_from"=>"ui","rust_push"=>"push",_=>"derive"}}
fn capture<C:Control>(control:&mut C,pattern:&crate::pat::Pat)->Result<(),C::Error>{kc::reserve(control,||pattern.capture_group_count().checked_mul(4)?.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(std::mem::size_of::<crate::pat::Caps<'_>>()+64))}
fn split<C:Control>(text:&str,control:&mut C)->Result<Vec<String>,C::Error>{let mut out=Vec::new();let mut depth=0i32;let mut from=0;for(at,ch)in text.char_indices(){control.checkpoint()?;if "([{".contains(ch){depth+=1}else if ")]}".contains(ch){depth-=1}if ch==','&&depth==0{kc::row(control,&mut out)?;out.push(kc::own(control,py_strip(&text[from..at]))?);from=at+1;}}if !py_strip(&text[from..]).is_empty(){kc::row(control,&mut out)?;out.push(kc::own(control,py_strip(&text[from..]))?);}Ok(out)}
fn text<C:Control>(out:&mut String,part:&str,control:&mut C)->Result<(),C::Error>{let required=out.len().checked_add(part.len()).ok_or_else(||control.overflow())?;if C::CHECKED&&required>out.capacity(){let wanted=required.checked_next_power_of_two().ok_or_else(||control.overflow())?;let bound=wanted.checked_mul(4).ok_or_else(||control.overflow())?;kc::reserve(control,||Some(bound))?;out.try_reserve_exact(wanted-out.len()).map_err(|_|control.allocation_failed())?;if out.capacity()>bound{return Err(control.allocation_failed())}}out.push_str(part);Ok(())}
pub(crate) fn entries<C:Control>(proc:Procedure<'_>,header:usize,control:&mut C)->Result<Vec<Entry>,C::Error>{
 let mut text=String::new();let mut starts=Vec::new();let mut lines=Vec::new();let mut first=true;
 for(number,line)in proc.lines.iter(){control.checkpoint()?;if py_strip(line).is_empty(){continue}if !first{self::text(&mut text,"\n",control)?;}first=false;kc::row(control,&mut starts)?;starts.push(text.len());kc::row(control,&mut lines)?;lines.push(number);self::text(&mut text,line,control)?;}
 let mut entries=Vec::new();let mut pos=0;loop{control.checkpoint()?;let pattern=pat!(r"(?<![\w.])(runs_while|drawn_from|ui_from|rust_push|derive)\s*\(");capture(control,pattern)?;let Some(m)=pattern.captures_at(&text,pos)else{break};let(inner,end)=paren_args(&text,m.end(0)-1);pos=end;let kind=kind(m.s(1));let mut args=split(inner,control)?;let mut name=None;
  if kind=="derive"{if let Some(first)=args.first(){capture(control,pat!(NAMEOF))?;if let Some(m)=pat!(NAMEOF).captures(first){name=Some(kc::own(control,m.s(2))?)}}if !args.is_empty(){args.remove(0);}}
  let mut local=BTreeSet::new();let mut remote=Vec::new();let mut hops=Vec::new();
  for arg in &args{control.checkpoint()?;capture(control,pat!(NAMEOF))?;if let Some(n)=pat!(NAMEOF).captures(arg){kc::reserve(control,||Some(512))?;local.insert(kc::own(control,n.s(2))?);continue}
   let relation=pat!(r"(?s)(rel|rel_each)\((.*)\)$");capture(control,relation)?;if let Some(h)=relation.captures(arg){let parts=split(h.s(2),control)?;if let Some(link)=parts.first(){capture(control,pat!(NAMEOF))?;if let Some(l)=pat!(NAMEOF).captures(link){kc::row(control,&mut hops)?;hops.push(kc::own(control,l.s(2))?);kc::reserve(control,||Some(512))?;local.insert(kc::own(control,l.s(2))?);}}if let Some(far)=parts.get(1){capture(control,pat!(NAMEOF))?;if let Some(f)=pat!(NAMEOF).captures(far){kc::row(control,&mut remote)?;remote.push((f.get(1).map(|s|kc::own(control,s)).transpose()?,kc::own(control,f.s(2))?));}}}
  }
  let idx=starts.partition_point(|&s|s<=m.start(0));let line=if lines.is_empty(){header}else{lines[idx-1]};kc::row(control,&mut entries)?;entries.push(Entry{rel:kc::own(control,proc.relative)?,line,kind,name,local,remote,hops});
 }control.checkpoint()?;Ok(entries)
}
#[cfg(test)]mod tests{
 use super::*;use crate::reactive_reaction_policy::Lines;
 #[test]fn same_original_derived_entry_shapes_preserve_names_hops_remote_types_and_lines(){let lines=vec![(8,"\treturn list(".into()),(9,"\t\tderive(nameof(total), nameof(a), rel_each(nameof(items), nameof(/obj/item::value))),".into()),(10,"\t\tui_from(nameof(/ignored::local_name)), drawn_from(), runs_while(nameof(state)))".into())];let proc=Procedure{owner:"/obj/unit",name:"derived",relative:"code/unit.dm",args:")",lines:Lines::Owned(&lines)};let rows=entries(proc,7,&mut kc::Compatibility).unwrap();assert_eq!(rows.len(),4);assert_eq!((rows[0].kind,rows[0].line,rows[0].name.as_deref()),("derive",9,Some("total")));assert_eq!(rows[0].local.iter().map(String::as_str).collect::<Vec<_>>(),["a","items"]);assert_eq!(rows[0].hops,["items"]);assert_eq!(rows[0].remote,[(Some("/obj/item".into()),"value".into())]);assert_eq!(rows[1].local.iter().map(String::as_str).collect::<Vec<_>>(),["local_name"]);assert!(rows[1].remote.is_empty());assert!(rows[2].local.is_empty());assert_eq!(rows[3].line,10);}
 #[test]fn empty_and_unnamed_derive_keep_the_original_nonsemantic_shape(){let lines=vec![(2,"\treturn list(derive(not_nameof, nameof(field)), ui_from(,nameof(x),), derive())".into())];let rows=entries(Procedure{owner:"/x",name:"derived",relative:"code/a.dm",args:")",lines:Lines::Owned(&lines)},1,&mut kc::Compatibility).unwrap();assert_eq!(rows.len(),3);assert_eq!(rows[0].name,None);assert!(rows[0].local.contains("field"));assert!(rows[1].local.contains("x"));assert_eq!(rows[2].name,None);}
}

#[cfg(test)]mod immutable_entry_oracle{use super::*;use crate::{pat,pat_match};struct Proc{rel:String,start:usize,body:Vec<(usize,String)>}
fn entry_kind(call: &str) -> &'static str {
    match call {
        "runs_while" => "runs",
        "drawn_from" => "drawn",
        "ui_from" => "ui",
        "rust_push" => "push",
        _ => "derive",
    }
}
fn split_args(text: &str) -> Vec<String> {
    let mut parts = Vec::new();
    let mut depth = 0i32;
    let mut cur = String::new();
    for ch in text.chars() {
        if "([{".contains(ch) {
            depth += 1;
        } else if ")]}".contains(ch) {
            depth -= 1;
        }
        if ch == ',' && depth == 0 {
            parts.push(std::mem::take(&mut cur));
        } else {
            cur.push(ch);
        }
    }
    if !py_strip(&cur).is_empty() {
        parts.push(cur);
    }
    parts.iter().map(|p| py_strip(p).to_string()).collect()
}

/// `call_args`: the text between the paren at `open` and its match, and the index after the match.
#[derive(Clone, Debug)]
struct Entry {
    rel: String,
    line: usize,
    kind: &'static str,
    name: Option<String>,
    local: BTreeSet<String>,
    remote: Vec<(Option<String>, String)>,
    hops: Vec<String>,
}

const NAMEOF: &str = r"nameof\(\s*(?:(/[\w/]+)::)?(\w+)\s*\)$";

/// `parse_entries`: the entries of one `derived()` body.
fn parse_entries(proc: &Proc) -> Vec<Entry> {
    let text = proc.body.iter().map(|(_, t)| t.as_str()).collect::<Vec<_>>().join("\n");
    let mut starts = Vec::new();
    let mut offset = 0usize;
    for (_, line) in &proc.body {
        starts.push(offset);
        offset += line.len() + 1;
    }
    let mut entries = Vec::new();
    let mut pos = 0usize;
    loop {
        let Some(m) = pat!(r"(?<![\w.])(runs_while|drawn_from|ui_from|rust_push|derive)\s*\(").captures_at(&text, pos) else { break };
        let (inner, end) = paren_args(&text, m.end(0) - 1);
        pos = end;
        let kind = entry_kind(m.s(1));
        let mut args = split_args(inner);
        let mut name = None;
        if kind == "derive" {
            let first = if args.is_empty() { None } else { pat_match!(NAMEOF).captures(&args[0]) };
            name = first.map(|f| f.s(2).to_string());
            if !args.is_empty() {
                args.remove(0);
            }
        }
        let mut local = BTreeSet::new();
        let mut remote = Vec::new();
        let mut hops = Vec::new();
        for arg in &args {
            if let Some(n) = pat_match!(NAMEOF).captures(arg) {
                local.insert(n.s(2).to_string());
                continue;
            }
            if let Some(h) = pat_match!(r"(?s)(rel|rel_each)\((.*)\)$").captures(arg) {
                let parts = split_args(h.s(2));
                let link = parts.first().and_then(|p| pat_match!(NAMEOF).captures(p));
                let far = parts.get(1).and_then(|p| pat_match!(NAMEOF).captures(p));
                if let Some(l) = link {
                    hops.push(l.s(2).to_string());
                    local.insert(l.s(2).to_string());
                }
                if let Some(f) = far {
                    remote.push((f.get(1).map(|s| s.to_string()), f.s(2).to_string()));
                }
            }
        }
        let idx = starts.partition_point(|&s| s <= m.start(0));
        let line = if proc.body.is_empty() { proc.start } else { proc.body[idx - 1].0 };
        entries.push(Entry { rel: proc.rel.clone(), line, kind, name, local, remote, hops });
    }
    entries
}


pub(super) fn observe(relative:&str,header:usize,body:&[(usize,String)])->Vec<(String,usize,&'static str,Option<String>,BTreeSet<String>,Vec<(Option<String>,String)>,Vec<String>)>{let proc=Proc{rel:relative.into(),start:header,body:body.to_vec()};parse_entries(&proc).into_iter().map(|row|(row.rel,row.line,row.kind,row.name,row.local,row.remote,row.hops)).collect()}
}
#[cfg(test)]mod whole_entry_controls{
 use super::*;use crate::reactive_reaction_policy::Lines;
 #[test]fn complete_original_entry_results_match_unique_borrowed_policy_for_inactive_unicode_remote_and_empty_shapes(){
  for body in[vec!["\treturn list()"],vec!["\treturn list(derive(nameof(total), nameof(a), rel_each(nameof(items), nameof(/obj/item::value))), ui_from(nameof(/ignored::b)))"],vec!["\t#if INACTIVE","\treturn list(draw_nothing(), drawn_from(), derive(not_nameof, nameof(α)))","\t#endif"],vec!["\treturn list(","\t ui_from(nameof(a),", "\t  rel(nameof(link), nameof(/datum/other::b))), runs_while(nameof(c)))"],vec!["\treturn list(derive(), derive(nameof(a),), ui_from(,nameof(x),))"]]{let lines=body.into_iter().enumerate().map(|(i,s)|(i+10,s.to_owned())).collect::<Vec<_>>();let want=immutable_entry_oracle::observe("code/sample.dm",9,&lines);let got=entries(Procedure{owner:"/obj/sample",name:"derived",relative:"code/sample.dm",args:")",lines:Lines::Owned(&lines)},9,&mut kc::Compatibility).unwrap().into_iter().map(|r|(r.rel,r.line,r.kind,r.name,r.local,r.remote,r.hops)).collect::<Vec<_>>();assert_eq!(got,want);}
 }
 struct Checked{remaining:usize,polls:usize,fail:Option<usize>}
 impl Control for Checked{type Error=std::io::Error;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Self::Error>{self.polls+=1;if self.fail==Some(self.polls){Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}}fn reserve(&mut self,n:usize)->Result<(),Self::Error>{self.remaining=self.remaining.checked_sub(n).ok_or(std::io::ErrorKind::OutOfMemory)?;Ok(())}fn overflow(&mut self)->Self::Error{std::io::ErrorKind::OutOfMemory.into()}fn allocation_failed(&mut self)->Self::Error{std::io::ErrorKind::OutOfMemory.into()}}
 #[test]fn actual_checked_entry_policy_keeps_first_io_quota_and_fresh_control_recovery(){let lines=vec![(2,"\treturn list(ui_from(nameof(x)), derive(nameof(total), nameof(x)))".into())];let run=|control:&mut Checked|entries(Procedure{owner:"/x",name:"derived",relative:"code/unit.dm",args:")",lines:Lines::Owned(&lines)},1,control);assert_eq!(run(&mut Checked{remaining:0,polls:0,fail:None}).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(run(&mut Checked{remaining:1<<20,polls:0,fail:Some(2)}).err().unwrap().raw_os_error(),Some(1450));assert_eq!(run(&mut Checked{remaining:1<<20,polls:0,fail:None}).unwrap().len(),2);}
}
