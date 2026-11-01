//! Existing unique global-entry-proc raw first-statement projection.
//! No general declaration/parser/model or semantic type lookup.
use crate::raw_marker_policy::{matching_paren, split_args};
pub const ENTRY_PROC: &str = "ENTRY_PROC";
pub(crate) const ENTRY_CALLS: &[&str] = &[
    "op(",
    "extend(",
    "interface(",
    "ui_shape(",
    "on_notice(",
    "on_change(",
    "without(",
    "configure(",
];
#[derive(Default)]
pub struct Head(Option<(String, u32)>);
impl Head {
    pub fn begin(&mut self, line: &str, ln: u32) {
        self.0 = crate::pat_match!(r"^/proc/(\w+)\([^)]*\)\s*$")
            .captures(line)
            .map(|m| (m.s(1).to_string(), ln));
    }
    pub fn begin_capability(&mut self,line:&str,ln:u32){
        self.0=crate::pat_match!(r"^(/datum/capability/[\w/]+?)/(?:proc/)?entries\(\)\s*$").captures(line).map(|m|(m.s(1).to_owned(),ln));
    }
    pub fn take(&mut self) -> Option<(String, u32)> {
        self.0.take()
    }
}
pub struct Projection {
    pub line: u32,
    pub args: Vec<String>,
    pub body: String,
    pub body_offset: usize,
}
pub fn project_first_return(
    stripped: &str,
    starts: &[u32],
    ln0: usize,
    line: &str,
    t: &str,
    name: String,
    head_line: u32,
) -> Option<Projection> {
    let result = project_first_return_admitted(stripped, starts, ln0, line, t, name, head_line,
        |_| Ok::<(), std::convert::Infallible>(()));
    match result { Ok(value) => value, Err(never) => match never {} }
}
/// The original first-statement projector, with admission before its actual
/// recognized body and argument allocations. Non-entry first statements reserve nothing.
pub fn project_first_return_admitted<E>(
    stripped: &str, starts: &[u32], ln0: usize, line: &str, t: &str,
    name: String, head_line: u32, mut admit: impl FnMut(usize)->Result<(), E>,
) -> Result<Option<Projection>, E> {
    project_list_return(stripped,starts,ln0,line,t,name,head_line,true,&mut admit)
}
/// Exact capability entries policy: unlike global bundles, any first return
/// list is retained, including empty/non-entry lists.
pub fn project_capability_return_admitted<E>(stripped:&str,starts:&[u32],ln0:usize,line:&str,t:&str,owner:String,head_line:u32,mut admit:impl FnMut(usize)->Result<(),E>)->Result<Option<Projection>,E>{
    project_list_return(stripped,starts,ln0,line,t,owner,head_line,false,&mut admit)
}
fn project_list_return<E>(stripped:&str,starts:&[u32],ln0:usize,line:&str,t:&str,name:String,head_line:u32,entry_only:bool,admit:&mut impl FnMut(usize)->Result<(),E>)->Result<Option<Projection>,E>{
    let Some(rest) = t.strip_prefix("return") else {
        return Ok(None);
    };
    let rest = rest.trim_start();
    let Some(after) = rest.strip_prefix("list") else {
        return Ok(None);
    };
    if !after.trim_start().starts_with('(') {
        return Ok(None);
    }
    let open = starts[ln0] as usize + (line.len() - rest.len()) + rest.find('(').unwrap();
    let Some(close) = matching_paren(stripped, open) else {
        return Ok(None);
    };
    let body = &stripped[open + 1..close];
    if entry_only && !ENTRY_CALLS.iter().any(|c| body.contains(c)) {
        return Ok(None);
    }
    admit(body.len())?;
    let mut args = vec![name];
    args.extend(split_args(body));
    Ok(Some(Projection {
        line: head_line,
        args,
        body: body.to_owned(),
        body_offset: open + 1,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn exact_old_first_return_list_projection_keeps_original_head_and_body() {
        let source = "/proc/p()\n    return list(interface(\"X\"), ui_shape(a))\n";
        let starts = vec![0, 10, source.len() as u32];
        let line = source.split('\n').nth(1).unwrap();
        let mut head = Head::default();
        head.begin("/proc/p()", 1);
        let (name, ln) = head.take().unwrap();
        let p =
            project_first_return(source, &starts, 1, line, line.trim_start(), name, ln).unwrap();
        assert_eq!(p.line, 1);
        assert_eq!(p.args, ["p", "interface(\"X\")", "ui_shape(a)"]);
        assert_eq!(&source[p.body_offset..p.body_offset + p.body.len()], p.body);
        assert!(head.take().is_none());
    }
    #[test]
    fn a_nonreturn_first_statement_and_nonentry_list_do_not_issue_a_bundle() {
        let source = "/proc/p()\n    value = 1\n    return list(1)\n";
        let line = "    value = 1";
        assert!(project_first_return(
            source,
            &[0, 10, 24],
            1,
            line,
            line.trim_start(),
            "p".into(),
            1
        )
        .is_none());
        let source = "/proc/p()\n    return list(1)\n";
        let line = "    return list(1)";
        assert!(
            project_first_return(source, &[0, 10], 1, line, line.trim_start(), "p".into(), 1)
                .is_none()
        );
    }
    #[test]
    fn admitted_projector_only_reserves_recognized_actual_body_and_keeps_io() {
        for body in ["value = 1", "return list(1)"] {
            let source=format!("/proc/p()\n    {body}\n");let line=source.lines().nth(1).unwrap();
            let out=project_first_return_admitted(&source,&[0,10],1,line,line.trim_start(),"p".into(),1,|_|->Result<(),()> {panic!("non-entry must not reserve")}).unwrap();assert!(out.is_none());
        }
        let source="/proc/p()\n    return list(op(\"x\"))\n";let line=source.lines().nth(1).unwrap();let mut width=0;
        let error=project_first_return_admitted(source,&[0,10],1,line,line.trim_start(),"p".into(),1,|n|{width=n;Err::<(),_>(std::io::Error::from_raw_os_error(1450))}).err().unwrap();
        assert_eq!(width,"op(\"x\")".len());assert_eq!(error.raw_os_error(),Some(1450));
    }

}

#[cfg(test)]mod capability_tests{
 use super::*;
 #[test]fn capability_first_list_keeps_empty_and_nonentry_lists_unlike_global_bundle(){for tail in ["return list()","return list(1, 2)","return list(TYPE_PROC_REF(/datum/probe, f))"]{let source=format!("/datum/capability/def/probe/entries()\n    {tail}\n");let first=source.lines().next().unwrap();let line=source.lines().nth(1).unwrap();let starts=[0,(first.len()+1)as u32];let mut head=Head::default();head.begin_capability(first,1);let(owner,ln)=head.take().unwrap();let mut width=0;let got=project_capability_return_admitted(&source,&starts,1,line,line.trim_start(),owner,ln,|n|{width=n;Ok::<(),()>(())}).unwrap().unwrap();assert_eq!(got.args[0],"/datum/capability/def/probe");assert_eq!(&source[got.body_offset..got.body_offset+got.body.len()],got.body);assert_eq!(width,got.body.len());assert_eq!(got.line,1);}}
 #[test]fn capability_nonreturn_never_reserves_and_actual_refusal_keeps_cause(){let source="/datum/capability/def/probe/entries()\n    return list()\n";let first=source.lines().next().unwrap();let line=source.lines().nth(1).unwrap();let starts=[0,(first.len()+1)as u32];assert!(project_capability_return_admitted(source,&starts,1,"    x=1","x=1","/datum/capability/def/probe".into(),1,|_|->Result<(),()>{panic!("nonreturn")}).unwrap().is_none());let error=project_capability_return_admitted(source,&starts,1,line,line.trim_start(),"/datum/capability/def/probe".into(),1,|_|Err::<(),_>(std::io::Error::from_raw_os_error(1450))).err().unwrap();assert_eq!(error.raw_os_error(),Some(1450));}
}
