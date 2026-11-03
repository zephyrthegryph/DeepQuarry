//! Fixture-only source provider. The compiler and Analyze raw views come from
//! the SAME initial bytes/read, never decoded-text relabelling or a reread.
use std::{collections::BTreeMap,path::{Path,PathBuf},sync::Mutex};
struct Captured{source:dm_preprocess::AcquiredSource,raw:dm_preprocess::SourceText}
pub struct Provider{rows:Mutex<BTreeMap<PathBuf,Captured>>}
impl Provider{
 pub fn new()->Self{Self{rows:Mutex::new(BTreeMap::new())}}
 pub fn analyze_raw(&self,path:&Path,decoded:&dm_preprocess::SourceText)->dm_preprocess::SourceText{
  let rows=self.rows.lock().unwrap();let actual=rows.get(path).expect("compiled file must retain its actual original acquisition");
  assert!(actual.source.lease().source_text().same_view(decoded),"raw policy view must come from the SAME original captured file");actual.raw.clone()
 }
}
impl dm_preprocess::SourceProvider for Provider{
 fn initial_environment(&self)->dm_preprocess::InitialEnvironment{dm_preprocess::InitialEnvironment::OriginalChecker0290}
 fn read(&self,_:&Path)->Result<String,String>{Err("actual Original acquisition required".into())}
 fn acquired_source(&self,path:&Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{
  let mut rows=self.rows.lock().unwrap();if let Some(actual)=rows.get(path){return Ok(Some(actual.source.clone()))}
  let bytes=std::fs::read(path).map_err(|e|e.to_string())?;
  let raw=crate::util::universal_newlines(String::from_utf8_lossy(&bytes).into_owned()).into();
  let source=dm_preprocess::AcquiredSource::from_original_bytes(bytes,());rows.insert(path.to_path_buf(),Captured{source:source.clone(),raw});Ok(Some(source))
 }
 fn source_acquisition(&self,path:&Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{self.rows.lock().unwrap().get(path).filter(|actual|actual.source.lease().source_text().same_view(text)).map(|actual|actual.source.clone())}
}
