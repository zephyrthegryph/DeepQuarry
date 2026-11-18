//! Original changed-files selection over real Git stdout. This is requested
//! path-filter DATA only; it never issues source or filesystem completeness.
use std::{collections::BTreeSet,io,path::Path,process::Command};use crate::report_work::Work;
use super::{bounded,capture_command,OUTER_WATCHDOG,MAX_STDERR};
fn lines(bytes:&[u8],work:&dyn Work)->io::Result<Vec<String>>{work.reserve(bytes.len().checked_mul(8).and_then(|n|n.checked_add(4096)).ok_or_else(||work.overflow())?)?;let text=String::from_utf8_lossy(bytes);let count=text.lines().count();work.reserve(count.checked_mul(4*std::mem::size_of::<String>()).ok_or_else(||work.overflow())?)?;Ok(text.lines().map(str::to_owned).collect())}
fn own(paths:&mut BTreeSet<String>,path:&str,work:&dyn Work)->io::Result<()>{work.checkpoint()?;work.reserve(path.len().checked_mul(4).and_then(|n|n.checked_add(4096)).ok_or_else(||work.overflow())?)?;paths.insert(path.replace('\\',"/"));Ok(())}
pub(super)fn collect_using(mut git:impl FnMut(&[&str])->io::Result<Option<Vec<u8>>>,work:&dyn Work)->io::Result<Vec<String>>{
 let output=git(&["merge-base","HEAD","origin/master"])?;let rows=lines(output.as_deref().unwrap_or_default(),work)?;let base=rows.first().map(String::as_str).unwrap_or("HEAD");let mut paths=BTreeSet::new();
 let output=git(&["diff","--name-only",base])?;for row in lines(output.as_deref().unwrap_or_default(),work)?{own(&mut paths,&row,work)?}
 let output=git(&["status","--porcelain"])?;for row in lines(output.as_deref().unwrap_or_default(),work)?{if row.len()>3{let path=row[3..].rsplit(" -> ").next().unwrap_or("").trim_matches('"');own(&mut paths,path,work)?}}
 work.reserve(paths.len().checked_mul(4*std::mem::size_of::<String>()).ok_or_else(||work.overflow())?)?;work.checkpoint()?;Ok(paths.into_iter().collect())
}
pub(super)fn collect(root:&Path,diagnostics:&mut impl io::Write,work:&dyn Work)->io::Result<Vec<String>>{
 collect_using(|args|{work.checkpoint()?;let mut command=Command::new("git");command.args(args).current_dir(root);let(status,out,err)=capture_command(command,OUTER_WATCHDOG,|r|bounded(r,MAX_STDERR),|r|bounded(r,MAX_STDERR))?;diagnostics.write_all(&err)?;if status.success(){Ok(Some(out))}else{Ok(None)}},work)
}
#[cfg(test)]mod controls{use super::*;struct Paid(std::cell::Cell<usize>);impl Work for Paid{fn checkpoint(&self)->io::Result<()>{Ok(())}fn reserve(&self,n:usize)->io::Result<()>{self.0.set(self.0.get().checked_add(n).ok_or_else(||self.overflow())?);Ok(())}fn overflow(&self)->io::Error{io::ErrorKind::OutOfMemory.into()}}
 #[test]fn actual_original_git_argument_sequence_fallback_rename_and_path_normalization_are_preserved(){let mut calls=Vec::new();let rows=collect_using(|args|{calls.push(args.iter().map(|s|s.to_string()).collect::<Vec<_>>());Ok(match calls.len(){1=>None,2=>Some(b"code/a.dm\ncode\\b.dm\n".to_vec()),3=>Some(b" M code/a.dm\nR  old -> code/new.dm\n?? \"code/quoted.dm\"\n".to_vec()),_=>panic!("unexpected Git call")})},&Paid(0.into())).unwrap();assert_eq!(calls,[vec!["merge-base","HEAD","origin/master"],vec!["diff","--name-only","HEAD"],vec!["status","--porcelain"]]);assert_eq!(rows,["code/a.dm","code/b.dm","code/new.dm","code/quoted.dm"]);}
 #[test]fn actual_git_transport_io_is_first_and_stops_before_later_commands(){let mut calls=0;let error=collect_using(|_|{calls+=1;Err(io::Error::from_raw_os_error(1450))},&Paid(0.into())).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(calls,1);}
}
