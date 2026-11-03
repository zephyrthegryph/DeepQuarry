//! Shared original raw marker acquisition for existing borrowed generators.
use crate::{captured_generator_budget::Budget, captured_raw_policy::CapturedRawPolicy};
use std::{collections::HashMap, sync::Arc};
pub(crate) struct OwnedMarker {
    pub(crate) name: String,
    pub(crate) rel: String,
    pub(crate) line: u32,
    pub(crate) body: String,
    pub(crate) args: Vec<String>,
    pub(crate) body_offset: usize,
    pub(crate) line_starts: Arc<Vec<u32>>,
}
pub(crate) struct Rows<'a> {
    pub(crate) markers: Vec<OwnedMarker>,
    pub(crate) engine_sources: Vec<(&'a str, &'a str)>,
}
pub(crate) fn collect<'a>(
    raw: &'a CapturedRawPolicy,
    order: &HashMap<String, usize>,
    budget: &Arc<Budget>,
    names: &[&str],
    include_entries: bool,
    checkpoint: &mut impl FnMut() -> Result<(), String>,
) -> Result<Rows<'a>, String> {
    collect_admitted(raw,order,budget,names,include_entries,checkpoint)
}
pub(crate) fn collect_admitted<'a,E>(
    raw: &'a CapturedRawPolicy,
    order: &HashMap<String, usize>,
    budget: &Arc<Budget>,
    names: &[&str],
    include_entries: bool,
    checkpoint: &mut impl FnMut() -> Result<(), E>,
) -> Result<Rows<'a>, E> where E:From<String>+for<'error>From<&'error str> {
    collect_full_admitted(raw,order,budget,names,include_entries,false,false,checkpoint)
}
pub(crate) fn collect_full_admitted<'a,E>(raw:&'a CapturedRawPolicy,order:&HashMap<String,usize>,budget:&Arc<Budget>,names:&[&str],include_entries:bool,include_capabilities:bool,include_runtime:bool,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<Rows<'a>,E>where E:From<String>+for<'error>From<&'error str>{
    budget.charge(
        raw.tree
            .files
            .len()
            .checked_mul(256)
            .and_then(|n| n.checked_add(4096))
            .ok_or_else(|| {
                budget.deny();
                "declare roster overflow"
            })?,
    )?;
    let mut files = raw.tree.select(&crate::tree::CODE_DM);
    files.sort_by(|a, b| {
        (order.get(&a.rel).copied().unwrap_or(usize::MAX), &a.rel)
            .cmp(&(order.get(&b.rel).copied().unwrap_or(usize::MAX), &b.rel))
    });
    let mut rows: Vec<OwnedMarker> = Vec::new();
    let mut engine_sources = Vec::new();
    budget.charge(files.len().checked_mul(128).ok_or_else(|| {
        budget.deny();
        "declare engine roster overflow"
    })?)?;
    engine_sources.try_reserve_exact(files.len()).map_err(|_| {
        budget.deny();
        "declare engine roster allocation"
    })?;
    let mut count = 0usize;
    for file in &files {
        checkpoint()?;
        budget.require()?;
        raw.tree.captured_violation().map_or(Ok(()), Err)?;
        if file.rel.starts_with("code/engine/") {
            engine_sources.push((file.rel.as_str(), file.text()));
        }
        let marker = file.marker();
        raw.tree.captured_violation().map_or(Ok(()), Err)?;
        if let Some(error)=file.captured_budget_error(){budget.deny();return Err(error.into())}
        collect_file_admitted(&file.rel,marker.as_str(),budget,names,include_entries,include_capabilities,include_runtime,&mut rows,&mut count,checkpoint)?;
        raw.tree.captured_violation().map_or(Ok(()), Err)?;
    }
    Ok(Rows {
        markers: rows,
        engine_sources,
    })
}

/// SAME unique marker/entry/runtime scanner for ONE borrowed original file.
/// This function consumes policy text only and does not mint coverage/source proof.
pub(crate) fn collect_file_admitted<E>(relative:&str,marker:&str,budget:&Arc<Budget>,names:&[&str],include_entries:bool,include_capabilities:bool,include_runtime:bool,rows:&mut Vec<OwnedMarker>,count:&mut usize,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<(),E> where E:From<String>+for<'error>From<&'error str>{
    collect_file_using(relative,marker,budget,names,include_entries,include_capabilities,include_runtime,rows,count,Some(crate::captured_raw_policy::MAX_FIXTURE_SITES),None,checkpoint)
}

/// Source-neutral actual-growth collection; no fixture count becomes coverage.
pub(crate) fn collect_file_funded<E>(relative:&str,marker:&str,budget:&Budget,temporary:&Budget,names:&[&str],include_entries:bool,include_capabilities:bool,include_runtime:bool,rows:&mut Vec<OwnedMarker>,count:&mut usize,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<(),E> where E:From<String>+for<'error>From<&'error str>{
    collect_file_using(relative,marker,budget,names,include_entries,include_capabilities,include_runtime,rows,count,None,Some(temporary),checkpoint)
}

fn collect_file_using<E>(relative:&str,marker:&str,budget:&Budget,names:&[&str],include_entries:bool,include_capabilities:bool,include_runtime:bool,rows:&mut Vec<OwnedMarker>,count:&mut usize,ceiling:Option<usize>,temporary:Option<&Budget>,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<(),E> where E:From<String>+for<'error>From<&'error str>{
        let line_budget=temporary.unwrap_or(budget);let initial_rows=rows.len();
        let line_count = marker.bytes().filter(|b| *b == b'\n').count();
        line_budget.charge(
            line_count
                .checked_add(1)
                .and_then(|n| n.checked_mul(if ceiling.is_none(){16}else{4}))
                .and_then(|n| n.checked_add(128))
                .ok_or_else(|| {
                    line_budget.deny();
                    "declare line roster overflow"
                })?,
        )?;
        let mut line_starts = Vec::new();
        line_starts
            .try_reserve_exact(line_count + 1)
            .map_err(|_| {
                line_budget.deny();
                "declare line roster allocation"
            })?;
        if ceiling.is_none()&&line_starts.capacity()>line_count.checked_add(1).and_then(|n|n.checked_mul(4)).ok_or("marker line capacity overflow")?{line_budget.deny();return Err("marker line capacity exceeds admission".into())}
        line_starts.push(0);
        for (i, b) in marker.bytes().enumerate() {
            if b == b'\n' {
                line_starts.push(u32::try_from(i + 1).map_err(|_| "declare source line offset")?);
            }
        }
        let line_starts = Arc::new(line_starts);
        let mut head = crate::raw_entry_proc_policy::Head::default();
        let mut capability=crate::raw_entry_proc_policy::Head::default();
        let mut offset = 0usize;
        for (line, text) in marker.split('\n').enumerate() {
            checkpoint()?;
            budget.require()?;
            if include_entries||include_capabilities {
                line_budget.charge(
                    text.len()
                        .checked_add(128)
                        .and_then(|n| n.checked_mul(8))
                        .ok_or_else(|| {
                            line_budget.deny();
                            "entry head bound overflow"
                        })?,
                )?;
                let t = text.trim_start();
                if !text.is_empty() && !text.starts_with(char::is_whitespace) {
                    if include_entries{head.begin(text, u32::try_from(line + 1).map_err(|_| "entry line")?);}
                    if include_capabilities{capability.begin_capability(text,u32::try_from(line+1).map_err(|_|"capability entry line")?);}
                } else if !t.is_empty() && !t.starts_with('#') {
                    if let Some((name, head_line)) = head.take() {
                        let head_name_capacity=name.capacity();
                        if let Some(m) = crate::raw_entry_proc_policy::project_first_return_admitted(
                            marker,
                            &line_starts,
                            line,
                            text,
                            t,
                            name,
                            head_line,
                            |width| -> Result<(), E> {
                                checkpoint()?;
                                budget.split_args(width)?;
                                budget.charge(width.checked_mul(8)
                                    .and_then(|n|n.checked_add(relative.len()+1024))
                                    .ok_or("entry projection overflow")?)?;
                                Ok(())
                            },
                        )? {
                            if temporary.is_some(){budget.charge(head_name_capacity)?;}
                            *count=count.checked_add(1).ok_or("marker count overflow")?;
                            if ceiling.is_some_and(|limit|*count>limit) {
                                return Err(
                                    "entry projection marker count exceeds captured scope".into()
                                );
                            }
                            if !marker_row_using::<E>(budget,rows,ceiling.is_none())? {
                                return Err("entry projection row allocation denied".into());
                            }
                            rows.push(OwnedMarker {
                                name: crate::raw_entry_proc_policy::ENTRY_PROC.to_owned(),
                                rel: relative.to_owned(),
                                line: m.line,
                                body: m.body,
                                args: m.args,
                                body_offset: m.body_offset,
                                line_starts: line_starts.clone(),
                            });
                        }
                    }
                    if let Some((owner,head_line))=capability.take(){
                        let owner_capacity=owner.capacity();
                        if let Some(m)=crate::raw_entry_proc_policy::project_capability_return_admitted(marker,&line_starts,line,text,t,owner,head_line,|width|->Result<(),E>{checkpoint()?;budget.split_args(width)?;budget.charge(width.checked_mul(8).and_then(|n|n.checked_add(relative.len())).and_then(|n|n.checked_add(1024)).ok_or_else(||{budget.deny();"capability entry projection overflow"})?)?;Ok(())})?{
                            if temporary.is_some(){budget.charge(owner_capacity)?;}
                            *count=count.checked_add(1).ok_or("marker count overflow")?;if ceiling.is_some_and(|limit|*count>limit){return Err("capability entry marker count exceeds captured scope".into())}
                            if !marker_row_using::<E>(budget,rows,ceiling.is_none())?{return Err("capability entry row allocation denied".into())}
                            rows.push(OwnedMarker{name:"CAP_ENTRIES".to_owned(),rel:relative.to_owned(),line:m.line,body:m.body,args:m.args,body_offset:m.body_offset,line_starts:line_starts.clone()});
                        }
                    }

                }
            }
            if let Some(m) =
                crate::raw_marker_policy::statement_marker(marker, offset, text, names)
            {
                *count=count.checked_add(1).ok_or("marker count overflow")?;
                if ceiling.is_some_and(|limit|*count>limit) {
                    return Err("declare marker count exceeds captured scope".into());
                }
                let block_end = if !text.starts_with(char::is_whitespace)
                    && ["CAPABILITIES", "CAPABILITY_DEF", "STATE_GRAPH"].contains(&m.name)
                {
                    crate::raw_marker_policy::block_extent(marker, m.close)
                } else {
                    None
                };
                let end = block_end.unwrap_or(m.close);
                let width = end.checked_sub(m.open).ok_or_else(|| {
                    budget.deny();
                    "declare marker range overflow"
                })?;
                // Original block_body owns one width-sized Vec/String, split_args owns its
                // documented3N slots+4L temporary. Admit both before either construction.
                budget.charge(
                    width
                        .checked_mul(4)
                        .and_then(|n| n.checked_add(256))
                        .ok_or_else(|| {
                            budget.deny();
                            "declare block temporary overflow"
                        })?,
                )?;
                budget.split_args(width)?;
                let body = match block_end {
                    Some(end) => crate::raw_marker_policy::block_body(
                        marker,
                        m.open + 1,
                        m.close,
                        end,
                    ),
                    None => marker[m.open + 1..m.close].to_owned(),
                };
                let args = crate::raw_marker_policy::split_args(&body);
                budget.charge(
                    width
                        .checked_add(relative.len())
                        .and_then(|n| n.checked_add(m.name.len()))
                        .and_then(|n| n.checked_add(512))
                        .ok_or_else(|| {
                            budget.deny();
                            "declare marker row overflow"
                        })?,
                )?;
                if ceiling.is_none(){marker_row_using::<E>(budget,rows,true)?;}else{
                if rows.len() == rows.capacity() {
                    let cap = rows.len().max(4).checked_mul(2).ok_or_else(|| {
                        budget.deny();
                        "declare row capacity overflow"
                    })?;
                    budget.charge(
                        cap.checked_mul(std::mem::size_of::<OwnedMarker>())
                            .ok_or_else(|| {
                                budget.deny();
                                "declare row allocation overflow"
                            })?,
                    )?;
                    rows.try_reserve_exact(cap - rows.len()).map_err(|_| {
                        budget.deny();
                        "declare row allocation"
                    })?;
                }
                }
                rows.push(OwnedMarker {
                    name: m.name.to_owned(),
                    rel: relative.to_owned(),
                    line: u32::try_from(line + 1).map_err(|_| "declare source line")?,
                    body,
                    args,
                    body_offset: m.open + 1,
                    line_starts: line_starts.clone(),
                });
            }
            offset = offset.checked_add(text.len() + 1).ok_or_else(|| {
                budget.deny();
                "declare marker offset overflow"
            })?;
        }

        if include_runtime{
            struct RuntimeControl<'b,E,F>{budget:&'b Budget,poll:&'b mut F,_error:std::marker::PhantomData<E>}
            impl<E,F> crate::key_policy_control::Control for RuntimeControl<'_,E,F> where E:From<String>+for<'e>From<&'e str>,F:FnMut()->Result<(),E>{
                type Error=E;const CHECKED:bool=true;
                fn checkpoint(&mut self)->Result<(),E>{(self.poll)()?;self.budget.require().map_err(E::from)}
                fn reserve(&mut self,n:usize)->Result<(),E>{self.budget.charge(n).map_err(E::from)}
                fn overflow(&mut self)->E{self.budget.deny();"runtime observer allocation overflow".into()}
                fn allocation_failed(&mut self)->E{self.budget.deny();"runtime observer allocation refused".into()}
            }
            let mut control=RuntimeControl{budget,poll:checkpoint,_error:std::marker::PhantomData};
            crate::raw_runtime_observer_policy::visit(marker,&line_starts,&mut control,&mut|control,p|{
                *count=count.checked_add(1).ok_or("marker count overflow")?;if ceiling.is_some_and(|limit|*count>limit){return Err("runtime observer marker count exceeds captured scope".into())}
                crate::key_policy_control::reserve(control,||relative.len().checked_add(512))?;
                if !marker_row_using::<E>(budget,rows,ceiling.is_none())?{return Err("runtime observer row allocation denied".into())}
                rows.push(OwnedMarker{name:crate::raw_runtime_observer_policy::RUNTIME_OBSERVE.to_owned(),rel:relative.to_owned(),line:p.line,args:p.args,body:p.body,body_offset:p.body_offset,line_starts:line_starts.clone()});Ok(())
            })?;
        }
    if temporary.is_some()&&rows.len()>initial_rows{budget.charge(line_starts.capacity().checked_mul(std::mem::size_of::<u32>()).and_then(|n|n.checked_add(std::mem::size_of::<Vec<u32>>()+2*std::mem::size_of::<usize>())).ok_or("retained marker line storage overflow")?)?;}
    Ok(())
}

fn marker_row_using<E>(budget:&Budget,rows:&mut Vec<OwnedMarker>,funded:bool)->Result<bool,E>where E:From<String>+for<'error>From<&'error str>{
 if !funded{return Ok(budget.row(rows))}
 budget.require()?;
 if rows.len()==rows.capacity(){
  let capacity=rows.capacity().checked_mul(2).map(|n|n.max(4)).ok_or("funded marker row capacity overflow")?;
  let bound=capacity.checked_mul(4).ok_or("funded marker capacity envelope overflow")?;
  budget.charge(bound.checked_mul(std::mem::size_of::<OwnedMarker>()).and_then(|n|n.checked_add(128)).ok_or("funded marker row storage overflow")?)?;
  rows.try_reserve_exact(capacity.checked_sub(rows.len()).ok_or("funded marker reserve overflow")?).map_err(|_|{budget.deny();"funded marker allocation refused"})?;
  if rows.capacity()>bound{budget.deny();return Err("funded marker actual capacity exceeds preadmission".into())}
 }
 Ok(true)
}
