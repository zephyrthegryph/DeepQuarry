//! Marker prelude over actual current CODE_DM raw-page loans.
use crate::{captured_generator_budget::Budget,captured_reactive_reads::Failure};

use std::{io,sync::Arc};

/// Count the exact legacy CODE_DM marker domain from the existing current host
/// file loans. Semantic children intentionally lack AnalyzeRaw; no view is
/// synthesized and a stopped/unavailable traversal cannot become zero markers.
pub fn marker_count_pages(pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<usize,Failure>{
 let mut count=0usize;let completed=pages.for_each(&mut|_,views|{
  poll()?;let file=views.source_file()?;
  let actual=crate::declaration_markers::captured_marker_count(&[file],budget,poll)?;
  count=count.checked_add(actual).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"utility actual marker total overflow")))?;Ok(true)
 })?;
 if !completed{return Err(Failure::Unsupported("utility actual raw marker traversal incomplete".into()))}
 poll()?;budget.require().map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;Ok(count)
}

#[cfg(test)]mod raw_marker_page_controls{
 use super::*;use crate::{captured_raw_file::{File,RawPolicyViews},reactive_raw_policy_pages::RawPolicyPages};
 struct Pages{file:File,mode:u8}
 impl RawPolicyPages for Pages{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{match self.mode{1=>Err(Failure::Operational(io::Error::new(io::ErrorKind::NotConnected,"actual raw page unavailable"))),2=>Ok(false),_=>self.file.with_policy_views(visit)}}}
 fn pages()->Pages{let root=std::env::current_dir().unwrap();Pages{file:File::capture(&root,&root.join("code/utility-marker.dm"),"CAPABILITIES(/datum/probe)\nSTAT(/datum/probe, value)\n".into()).unwrap(),mode:0}}
 #[test]fn actual_utility_marker_raw_pages_count_shared_rows_and_refuse_missing_or_stopped_source(){let p=pages();let budget=Budget::new(4<<20).unwrap();assert_eq!(marker_count_pages(&p,&budget,&||Ok(())).unwrap(),2);let mut p=pages();p.mode=1;assert!(matches!(marker_count_pages(&p,&Budget::new(4<<20).unwrap(),&||Ok(())),Err(Failure::Operational(e))if e.kind()==io::ErrorKind::NotConnected));p.mode=2;assert!(matches!(marker_count_pages(&p,&Budget::new(4<<20).unwrap(),&||Ok(())),Err(Failure::Unsupported(_))));}
 #[test]fn actual_utility_marker_raw_page_first_1450_is_preserved_and_new_operation_recovers(){let p=pages();let error=marker_count_pages(&p,&Budget::new(4<<20).unwrap(),&||Err(io::Error::from_raw_os_error(1450))).unwrap_err();assert!(matches!(error,Failure::Operational(e)if e.raw_os_error()==Some(1450)));assert_eq!(marker_count_pages(&p,&Budget::new(4<<20).unwrap(),&||Ok(())).unwrap(),2);}
}
