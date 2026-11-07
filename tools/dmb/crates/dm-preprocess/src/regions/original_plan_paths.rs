//! Ordered physical paths of one actual Original traversal. Ordinary directive
//! plans retain their existing maps. This index carries only borrowed DATA;
//! include occurrence and current acquisition authority remain independent.
use crate::{macro_expansion::OriginalMacroRows as Rows, SourceText};
use dm_syntax::{SettingAdmission, SettingRootLease};
use std::{collections::BTreeMap, io, path::{Path,PathBuf}, sync::Arc};

struct PathRow {
    dependency: Arc<PathBuf>,
    text: Option<SourceText>,
    // Path::Ord may equate distinct OS spellings. If a dependency spelling
    // was already issued before this path was opened, the old maps preserve
    // the first key of EACH role. Keep a second alias only in that case.
    opened_spelling: Option<Arc<PathBuf>>,
}
impl PathRow {
    fn source(&self)->Option<(&PathBuf,&SourceText)> {
        let text=self.text.as_ref()?;
        Some((self.opened_spelling.as_deref().unwrap_or(&self.dependency),text))
    }
}

pub(super) struct OriginalPlanPaths {
    rows:Rows<PathRow>,
    domain:SettingRootLease,
}
impl OriginalPlanPaths {
    pub(super) fn new(a:&SettingAdmission<'_>)->io::Result<Self>{
        Ok(Self{rows:Rows::new(a)?,domain:a.reserve(0).map_err(|e|a.take_operational_error().unwrap_or(e))?})
    }
    pub(super) fn admitted_by(&self,a:&SettingAdmission<'_>)->bool{a.matches_lease_domain(&self.domain)}
    fn find(&self,path:&Path)->Result<usize,usize>{
        self.rows.as_slice().binary_search_by(|row|row.dependency.as_path().cmp(path))
    }
    pub(super) fn contains_dependency(&self,path:&Path)->bool{self.find(path).is_ok()}
    pub(super) fn note(&mut self,path:Arc<PathBuf>,text:Option<SourceText>,a:&SettingAdmission<'_>)->io::Result<()>{
        a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;
        if !self.admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}
        match self.find(&path) {
            Ok(index)=>{
                let row=&mut self.rows.as_mut_slice()[index];
                if let Some(text)=text {
                    if let Some(old)=&row.text{
                        if old.as_str()!=text.as_str(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"same captured source path changed during actual traversal"))}
                    } else {
                        if row.dependency.as_os_str()!=path.as_os_str(){row.opened_spelling=Some(path);}
                        row.text=Some(text);
                    }
                }
                Ok(())
            }
            Err(at)=>self.rows.insert(at,PathRow{dependency:path,text,opened_spelling:None},a),
        }
    }
    pub(super) fn sources(&self)->SourceTexts<'_>{SourceTexts(SourceTextsKind::Original(self))}
    pub(super) fn dependencies(&self)->impl Iterator<Item=&PathBuf>{
        self.rows.as_slice().iter().map(|row|row.dependency.as_ref())
    }
    #[cfg(debug_assertions)]
    pub(super) fn row_capacity_bytes(&self)->usize{self.rows.capacity()*std::mem::size_of::<PathRow>()}
    pub(super) fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){
        self.rows.visit_allocation(|address,capacity|visit(address,self.rows.len()*std::mem::size_of::<PathRow>(),capacity));
        for row in self.rows.as_slice(){
            for path in std::iter::once(&row.dependency).chain(row.opened_spelling.iter()){
                // Match HeapCensus::arc_path's identity and object size. The
                // role iterators already report each PathBuf's byte buffer.
                let bytes=std::mem::size_of::<PathBuf>();
                visit(Arc::as_ptr(path) as usize,bytes,bytes);
            }
        }
    }
}

/// Read-only map-like projection of the same physical text owners, sorted by
/// the legacy Path comparator. This does not materialize a compatibility map.
#[derive(Clone,Copy)]
pub struct SourceTexts<'a>(SourceTextsKind<'a>);
#[derive(Clone,Copy)]
enum SourceTextsKind<'a>{Ordinary(&'a BTreeMap<PathBuf,SourceText>),Original(&'a OriginalPlanPaths)}
impl<'a> SourceTexts<'a>{
    pub fn ordinary(rows:&'a BTreeMap<PathBuf,SourceText>)->Self{Self(SourceTextsKind::Ordinary(rows))}
    pub fn get(self,path:&Path)->Option<&'a SourceText>{
        match self.0 {
            SourceTextsKind::Ordinary(rows)=>rows.get(path),
            SourceTextsKind::Original(paths)=>paths.find(path).ok()
                .and_then(|index|paths.rows.as_slice()[index].text.as_ref()),
        }
    }
    pub fn contains_key(self,path:&Path)->bool{self.get(path).is_some()}
    pub fn iter(self)->impl Iterator<Item=(&'a PathBuf,&'a SourceText)>+'a{
        let(ordinary,original)=match self.0{
            SourceTextsKind::Ordinary(rows)=>(Some(rows.iter()),None),
            SourceTextsKind::Original(paths)=>(None,Some(paths.rows.as_slice().iter())),
        };
        ordinary.into_iter().flatten().chain(original.into_iter().flatten().filter_map(PathRow::source))
    }
}

#[cfg(test)]
mod tests{
    use super::*;
    use std::sync::atomic::{Ordering};
    #[test]
    fn exact_original_path_index_preserves_legacy_order_and_distinct_first_spellings(){
        let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a=SettingAdmission::new(&used,1<<20,&||Ok(()));
        let mut paths=OriginalPlanPaths::new(&a).unwrap();
        let first=Arc::new(PathBuf::from("parent/./file.dm"));
        let opened=Arc::new(PathBuf::from("parent/file.dm"));
        assert_eq!(first,opened);
        assert_ne!(first.as_os_str(),opened.as_os_str());
        let text:SourceText="/datum/example".into();
        paths.note(Arc::new(PathBuf::from("z.dmm")),None,&a).unwrap();
        paths.note(first.clone(),None,&a).unwrap();
        paths.note(Arc::new(PathBuf::from("a.dm")),Some(text.clone()),&a).unwrap();
        paths.note(opened.clone(),Some(text.clone()),&a).unwrap();
        let deps=paths.dependencies().collect::<Vec<_>>();
        assert_eq!(deps.iter().map(|path|path.as_os_str()).collect::<Vec<_>>(),
            ["a.dm","parent/./file.dm","z.dmm"].map(std::ffi::OsStr::new));
        assert!(std::ptr::eq(deps[1],first.as_ref()));
        let sources=paths.sources().iter().collect::<Vec<_>>();
        assert_eq!(sources.len(),2);
        assert!(std::ptr::eq(sources[1].0,opened.as_ref()));
        assert!(sources[1].1.same_view(&text));
        let old=used.load(Ordering::Acquire);
        assert!(paths.note(opened.clone(),Some("changed".into()),&a).is_err());
        assert_eq!(used.load(Ordering::Acquire),old);
        assert!(paths.sources().get(&first).unwrap().same_view(&text));
        let other=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let foreign=SettingAdmission::new(&other,1<<20,&||Ok(()));
        assert_eq!(paths.note(opened,None,&foreign).unwrap_err().kind(),io::ErrorKind::InvalidInput);
        drop(paths);
        assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
    }
}
