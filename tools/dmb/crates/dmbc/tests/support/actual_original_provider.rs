//! Shared genuine OS provider behavior only; never constructs source authority.
use std::path::Path;
use dmbc::input_snapshot::{SnapshotProvider,FileSystemInputs,Stamp,FolderListing,PolicyDirectoryListing,CapturedInputRead,OriginalOpenedRead};
use dm_preprocess::{OriginalRawOpenDecision,source_arena_credit::SourceArenaWork};
use std::{io,sync::atomic::{AtomicUsize,Ordering}};
pub struct ActualInput { delete_root:bool, marker:AtomicUsize, second:AtomicUsize }
impl SnapshotProvider for ActualInput {
 fn original_open_status(&self,p:&Path)->io::Result<dmbc::input_snapshot::OriginalReadOpenStatus>{FileSystemInputs.original_open_status(p)}
 fn path_presence(&self,p:&Path)->io::Result<bool>{FileSystemInputs.path_presence(p)}
 fn path_presence_admitted(&self,p:&Path,w:&dyn SourceArenaWork)->io::Result<bool>{FileSystemInputs.path_presence_admitted(p,w)}
 fn stamp(&self,p:&Path)->io::Result<Stamp>{FileSystemInputs.stamp(p)}
 fn read(&self,p:&Path)->io::Result<(Stamp,Vec<u8>)>{FileSystemInputs.read(p)}
 fn list(&self,p:&Path)->io::Result<FolderListing>{FileSystemInputs.list(p)}
 fn source_alias(&self,p:&Path,c:&dmbc::input_snapshot::SourceAliasChallenge)->io::Result<Option<dmbc::input_snapshot::SourceAliasProof>>{FileSystemInputs.source_alias(p,c)}
 fn policy_directory(&self,p:&Path,f:bool,n:usize)->io::Result<Option<PolicyDirectoryListing>>{FileSystemInputs.policy_directory(p,f,n)}
 fn read_policy_bounded(&self,p:&Path,n:usize)->io::Result<Option<CapturedInputRead>>{if p.file_name().is_some_and(|n|n=="deepquarry.dme"){self.marker.fetch_add(1,Ordering::AcqRel);}FileSystemInputs.read_policy_bounded(p,n)}
 fn read_policy_bounded_admitted(&self,p:&Path,n:usize,b:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<Option<CapturedInputRead>>{if p.file_name().is_some_and(|n|n=="deepquarry.dme"){self.marker.fetch_add(1,Ordering::AcqRel);}FileSystemInputs.read_policy_bounded_admitted(p,n,b)}
 fn read_original_open_admitted(&self,p:&Path,n:usize,w:&dyn SourceArenaWork,o:&mut dyn FnMut()->io::Result<OriginalRawOpenDecision>,b:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<OriginalOpenedRead>{if p.file_name().is_some_and(|n|n=="deepquarry.dme"){let previous=self.second.fetch_add(1,Ordering::AcqRel);assert!(self.marker.load(Ordering::Acquire)>0,"genuine marker must precede actual root open");if self.delete_root&&previous==0{std::fs::remove_file(p)?}}FileSystemInputs.read_original_open_admitted(p,n,w,o,b)}
 // No filesystem watch token is claimed by this wrapper.
}
pub fn source(delete_root:bool)->ActualInput{ActualInput{delete_root,marker:0.into(),second:0.into()}}

impl ActualInput{pub fn second_reads(&self)->usize{self.second.load(Ordering::Acquire)}}
