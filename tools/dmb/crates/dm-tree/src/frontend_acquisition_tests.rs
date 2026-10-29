use super::*;
use dm_preprocess::{AcquiredSource, SourceProvider};
struct Provider(AcquiredSource);
impl SourceProvider for Provider {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Err("issued source must be used".into())
    }
    fn acquired_source(&self, _: &std::path::Path) -> Result<Option<AcquiredSource>, String> {
        Ok(Some(self.0.clone()))
    }
    fn source_acquisition(
        &self,
        _: &std::path::Path,
        text: &dm_preprocess::SourceText,
    ) -> Option<AcquiredSource> {
        self.0
            .prepared()
            .original()
            .same_view(text)
            .then(|| self.0.clone())
    }
}
#[test]
fn archive_borrows_exact_current_acquisition_and_foreign_normal_binding_rejects() {
    let bytes = b"/datum/probe/proc/run()\n    return\n";
    let provider = Provider(AcquiredSource::from_original_bytes(bytes.to_vec(), 1u64));
    let mut frontend = crate::frontend::build(
        std::path::Path::new("code/probe.dm"),
        &provider,
        &Default::default(),
        1,
    )
    .unwrap();
    let archive = frontend.body_archive().unwrap();
    let occurrence = archive.occurrences()[0].source.include_occurrence;
    assert!(archive
        .source_acquisition(occurrence)
        .unwrap()
        .same_binding(&provider.0));
    let foreign = AcquiredSource::from_original_bytes(bytes.to_vec(), 2u64);
    assert!(std::sync::Arc::ptr_eq(
        foreign.prepared(),
        provider.0.prepared()
    ));
    frontend
        .plan
        .source_acquisitions
        .insert(occurrence, foreign);
    assert!(frontend.source_export_mapping().is_none());
    assert!(frontend.body_archive().is_none());
    assert!(archive
        .source_acquisition(occurrence)
        .unwrap()
        .same_binding(&provider.0));
}

#[test]
fn capture_wrapper_preserves_every_issued_source_and_lease_across_includes(){
 struct Multi{project:AcquiredSource,a:AcquiredSource,b:AcquiredSource}
 impl Multi{fn get(&self,path:&std::path::Path)->Option<&AcquiredSource>{match path.file_name()?.to_str()?{"project.dme"=>Some(&self.project),"a.dm"=>Some(&self.a),"b.dm"=>Some(&self.b),_=>None}}}
 impl SourceProvider for Multi{
  fn read(&self,_:&std::path::Path)->Result<String,String>{Err("include must use issued primary source".into())}
  fn acquired_source(&self,path:&std::path::Path)->Result<Option<AcquiredSource>,String>{Ok(self.get(path).cloned())}
  fn source_acquisition(&self,path:&std::path::Path,text:&dm_preprocess::SourceText)->Option<AcquiredSource>{self.get(path).filter(|value|value.prepared().original().same_view(text)).cloned()}
 }
 let provider=Multi{
  project:AcquiredSource::from_original_bytes(b"#include \"code/a.dm\"\n#include \"code/b.dm\"\n".to_vec(),0u64),
  a:AcquiredSource::from_original_bytes(b"/datum/a/proc/run()\n    return\n".to_vec(),1u64),
  b:AcquiredSource::from_original_bytes(b"/datum/b/proc/run()\n    return\n".to_vec(),2u64),
 };
 let frontend=crate::frontend::build(std::path::Path::new("project.dme"),&provider,&Default::default(),1).unwrap();
 assert_eq!(frontend.files.iter().filter(|file|file.captured).count(),3);
 let archive=frontend.body_archive().unwrap();assert_eq!(archive.len(),2);
 for (id,include) in frontend.plan.occurrences.iter().enumerate(){
  let expected=provider.get(include.path.as_ref()).unwrap();
  assert!(archive.source_acquisition(id).unwrap().same_binding(expected));
  let file=frontend.files.iter().find(|file|file.path==include.path).unwrap();
  assert!(file.text.same_view(expected.prepared().original()),"captured file must retain issued source owner");
 }
}
