//! Borrowed final generated output only. The host still owns admission,
//! current source/configuration checks, staging and file installation.
use super::{Artifact,GeneratorName};
use serde::{Serialize,Serializer,ser::SerializeSeq};
struct Files<'a>(&'a Artifact);
impl Serialize for Files<'_>{
 fn serialize<S:Serializer>(&self,serializer:S)->Result<S::Ok,S::Error>{
  let artifact=self.0;
  let multiple=matches!(artifact.name,GeneratorName::UiTypes|GeneratorName::DerivedReads);
  let mut rows=serializer.serialize_seq(Some(if multiple{artifact.files.len()}else{1}))?;
  if multiple{for(path,text)in &artifact.files{rows.serialize_element(&(path.as_str(),text.as_str()))?;}}
  else{rows.serialize_element(&(artifact.name.path(),artifact.text.as_str()))?;}
  rows.end()
 }
}
#[derive(Serialize)]struct Output<'a>{generator:&'static str,files:Files<'a>,diagnostics:&'a[dq_analyze::sparse_slots_policy::Diagnostic]}
impl Artifact{
 /// A borrowed serializer, not a source receipt or a complete CLI result.
 /// It performs no file IO and owns no clone of generated text/diagnostics.
 /// Callers must fund serialization and validate the actual source frame.
 pub(crate) fn output_wire(&self)->impl Serialize+'_ {Output{generator:self.name(),files:Files(self),diagnostics:self.diagnostics()}}
}
#[cfg(test)]mod tests{
 use super::*;
 #[test]fn generated_output_wire_preserves_all_single_and_multifile_bytes_and_diagnostic_order(){
  for name in [GeneratorName::SparseSlots,GeneratorName::SystemAccessors,GeneratorName::Stats,GeneratorName::Actions,GeneratorName::DeclareIds,GeneratorName::Declare,GeneratorName::TrackedLists,GeneratorName::Deps,GeneratorName::AutoTracked,GeneratorName::Reads,GeneratorName::Plans,GeneratorName::UiTypes,GeneratorName::DerivedReads]{
   let multiple=matches!(name,GeneratorName::UiTypes|GeneratorName::DerivedReads);
   let artifact=Artifact{name,text:if multiple{String::new()}else{"generated α\n\0\"".into()},files:if multiple{vec![("first/path".into(),"first α\n".into()),("second/path".into(),"second\0".into())]}else{Vec::new()},diags:vec![dq_analyze::sparse_slots_policy::Diagnostic{rel:"z.dm".into(),line:7,msg:"first refusal".into()},dq_analyze::sparse_slots_policy::Diagnostic{rel:"a.dm".into(),line:2,msg:"second refusal".into()}]};
   let actual=serde_json::to_value(artifact.output_wire()).unwrap();
   let files=if multiple{serde_json::json!([["first/path","first α\n"],["second/path","second\0"]])}else{serde_json::json!([[name.path(),"generated α\n\0\""]])};
   assert_eq!(actual,serde_json::json!({"generator":name.name(),"files":files,"diagnostics":[{"rel":"z.dm","line":7,"msg":"first refusal"},{"rel":"a.dm","line":2,"msg":"second refusal"}]}));
  }
 }
 #[test]fn empty_multifile_output_stays_empty_instead_of_becoming_a_fake_single_path(){for name in[GeneratorName::UiTypes,GeneratorName::DerivedReads]{let value=Artifact{name,text:String::new(),files:Vec::new(),diags:Vec::new()};let actual=serde_json::to_value(value.output_wire()).unwrap();assert_eq!(actual["files"],serde_json::json!([]));assert_eq!(actual["diagnostics"],serde_json::json!([]));}}
}
