//! Explicit preprocessing configuration, not a source/completion receipt.
//! The native compiler default is unchanged; the original-checker environment
//! is selected only by an admitted analysis purpose through the same pipeline.
use crate::Macro;
use std::collections::BTreeMap;
#[path="original_default_macro_data.rs"]mod original;
#[derive(Clone,Copy,Debug,Default,Eq,PartialEq)]
pub enum InitialEnvironment{#[default]Native5161687,OriginalChecker0290}
impl InitialEnvironment{
 pub fn profile(self)->u128{match self{Self::Native5161687=>0,Self::OriginalChecker0290=>{use sha2::Digest as _;let digest=sha2::Sha256::digest(include_bytes!("original_default_macro_data.rs"));u128::from_le_bytes(digest[..16].try_into().unwrap())}}}
 pub fn original_constants()->&'static[(&'static str,&'static str)]{original::ORIGINAL_DEFAULT_CONSTANTS}
 pub fn original_functions()->&'static[(&'static str,&'static[&'static str],&'static str)]{original::ORIGINAL_DEFAULT_FUNCTIONS}
}
/// A borrow of ONE actual final initial-environment configuration entry. Only
/// the existing configuration table walk issues this DATA. It is nonphysical:
/// no acquisition, lexical frame, CODE/IO/EOF or semantic role follows from it.
/// Actual Original token factory consumes this replacement ONCE at initial
/// issuance, using SAME native lexical/value kernels; lookup never relexes it.
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub(crate) enum OriginalInitialProvenance{FixedDefault,CallerDefinition}
pub(crate) struct OriginalInitialDefinition<'a>{name:&'a str,definition:&'a Macro,provenance:OriginalInitialProvenance}
impl<'a>OriginalInitialDefinition<'a>{
 pub(crate) fn name(&self)->&'a str{self.name}
 pub(crate) fn metadata(&self)->&'a Macro{self.definition}
 pub(crate) fn provenance(&self)->OriginalInitialProvenance{self.provenance}
 pub(crate) fn replacement_text(&self)->&'a str{&self.definition.replacement}
}
/// Preserve the current actual configuration precedence: install defaults,
/// apply caller -D into final_macros, then visit its final entries once. This
/// walk is neither a new macro dictionary nor an alternate initial table.
fn original_initial_provenance(name:&str,definition:&Macro,caller_defines:&BTreeMap<String,String>,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<OriginalInitialProvenance>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;Ok(if let Some(replacement)=caller_defines.get(name){if definition.parameters.is_some()||definition.variadic||&definition.replacement!=replacement{return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"actual caller definition metadata differs before token issuance"))}OriginalInitialProvenance::CallerDefinition}else{
   let constant=original::ORIGINAL_DEFAULT_CONSTANTS.iter().find(|(actual,_)|*actual==name).is_some_and(|(_,replacement)|definition.parameters.is_none()&&!definition.variadic&&definition.replacement==*replacement);
   let function=original::ORIGINAL_DEFAULT_FUNCTIONS.iter().find(|(actual,_,_)|*actual==name).is_some_and(|(_,parameters,replacement)|!definition.variadic&&definition.replacement==*replacement&&definition.parameters.as_ref().is_some_and(|actual|actual.len()==parameters.len()&&actual.iter().zip(parameters.iter()).all(|(a,b)|a.as_str()==*b)));
   if !constant&&!function{return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"unissued default or foreign initial binding before token issuance"))}OriginalInitialProvenance::FixedDefault
  })}
pub(crate) fn visit_original_bootstrap_using(environment:InitialEnvironment,final_macros:&BTreeMap<String,Macro>,caller_defines:&BTreeMap<String,String>,a:&dm_syntax::SettingAdmission<'_>,visit:&mut dyn FnMut(OriginalInitialDefinition<'_>)->std::io::Result<()>)->std::io::Result<()>{
 let poll=||a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e));
 if environment!=InitialEnvironment::OriginalChecker0290{return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"Original bootstrap issuance requires its actual initial environment"))}
 poll()?;
 // Authenticate the actual existing final-table recipe, including absence. A
 // missing default/caller binding is an error, never a silently empty product.
 for(name,_)in original::ORIGINAL_DEFAULT_CONSTANTS{poll()?;if !final_macros.contains_key(*name){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"actual Original default binding is missing before token issuance"))}}
 for(name,_,_)in original::ORIGINAL_DEFAULT_FUNCTIONS{poll()?;if !final_macros.contains_key(*name){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"actual Original function binding is missing before token issuance"))}}
 for name in caller_defines.keys(){poll()?;if !final_macros.contains_key(name){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"actual caller definition is missing before token issuance"))}}
 for(name,definition)in final_macros{original_initial_provenance(name,definition,caller_defines,a)?;}
 for(name,definition)in final_macros{poll()?;let provenance=original_initial_provenance(name,definition,caller_defines,a)?;visit(OriginalInitialDefinition{name,definition,provenance})?;}
 Ok(())
}

/// Issue one entry of the actual initial recipe, without first allocating a
/// duplicate final table. The coordination owner funds temporary metadata
/// before constructing it; this judge is shared with the existing table walk.
pub(crate) fn with_original_initial_definition_using<R>(environment:InitialEnvironment,name:&str,definition:&Macro,caller:&BTreeMap<String,String>,a:&dm_syntax::SettingAdmission<'_>,visit:impl FnOnce(OriginalInitialDefinition<'_>)->std::io::Result<R>)->std::io::Result<R>{
 if environment!=InitialEnvironment::OriginalChecker0290{return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"Original bootstrap issuance requires its actual initial environment"))}
 let provenance=original_initial_provenance(name,definition,caller,a)?;
 visit(OriginalInitialDefinition{name,definition,provenance})
}

pub(crate) fn install(environment:InitialEnvironment,macros:&mut BTreeMap<String,Macro>){match environment{
 InitialEnvironment::Native5161687=>{
    for (name, replacement) in [
        ("EXCEPTION", "new /exception(message, __FILE__, __LINE__)"),
        ("REGEX_QUOTE", "regex(message, 1)"),
        ("REGEX_QUOTE_REPLACEMENT", "regex(message, 2)"),
    ] {
        macros.insert(
            name.into(),
            Macro {
                parameters: Some(vec!["message".into()]),
                variadic: false,
                replacement: replacement.into(),
            },
        );
    }
    // Pinned native spellings are initial object macros. Undef removes only
    // substitution; any remaining runtime/global meaning belongs to the resolver.
    // Install them before caller definitions; source define/undef effects then
    // apply through the same ordered environment as every other macro.
    for (name, replacement) in [
        // Exact native516.1687 #ifdef and root/datum values: native_sdk_macros/receipt.json.
        ("ANIMATION_CONTINUE", "512"),
        ("ANIMATION_END_LOOP", "16"),
        ("ANIMATION_END_NOW", "1"),
        ("ANIMATION_LINEAR_TRANSFORM", "2"),
        ("ANIMATION_PARALLEL", "4"),
        ("ANIMATION_RELATIVE", "256"),
        ("ANIMATION_SLICE", "8"),
        ("AREA_LAYER", "1"),
        ("BACKGROUND_LAYER", "20000"),
        ("BACK_EASING", "6"),
        ("BLEND_ADD", "2"),
        ("BLEND_DEFAULT", "0"),
        ("BLEND_INSET_OVERLAY", "5"),
        ("BLEND_MULTIPLY", "4"),
        ("BLEND_OVERLAY", "1"),
        ("BLEND_SUBTRACT", "3"),
        ("BOUNCE_EASING", "4"),
        ("CIRCULAR_EASING", "2"),
        ("COLORSPACE_HCY", "3"),
        ("COLORSPACE_HSL", "2"),
        ("COLORSPACE_HSV", "1"),
        ("COLORSPACE_RGB", "0"),
        ("CONTROL_FREAK_ALL", "1"),
        ("CONTROL_FREAK_MACROS", "4"),
        ("CONTROL_FREAK_SKIN", "2"),
        ("CUBIC_EASING", "3"),
        ("DM_BUILD", "1687"),
        ("DOWN", "32"),
        ("EASE_IN", "64"),
        ("EASE_OUT", "128"),
        ("EAST", "4"),
        ("EDGE_PERSPECTIVE", "2"),
        ("EFFECTS_LAYER", "5000"),
        ("ELASTIC_EASING", "5"),
        ("EYE_PERSPECTIVE", "1"),
        ("FALSE", "0"),
        ("FEMALE", "\"female\""),
        ("FILTER_COLOR_HCY", "3"),
        ("FILTER_COLOR_HSL", "2"),
        ("FILTER_COLOR_HSV", "1"),
        ("FILTER_COLOR_RGB", "0"),
        ("FILTER_OVERLAY", "1"),
        ("FILTER_UNDERLAY", "2"),
        ("FLOAT_LAYER", "(-1)"),
        ("FLOAT_PLANE", "(-32767)"),
        ("FLY_LAYER", "5"),
        ("FORWARD_STEPS", "1"),
        ("ICON_ADD", "0"),
        ("ICON_AND", "4"),
        ("ICON_MULTIPLY", "2"),
        ("ICON_OR", "5"),
        ("ICON_OVERLAY", "3"),
        ("ICON_SUBTRACT", "1"),
        ("ICON_UNDERLAY", "6"),
        ("ISOMETRIC_MAP", "1"),
        ("JSON_ALLOW_COMMENTS", "2"),
        ("JSON_PRETTY_PRINT", "1"),
        ("JSON_STRICT", "1"),
        ("JUMP_EASING", "8"),
        ("KEEP_APART", "64"),
        ("KEEP_TOGETHER", "32"),
        ("LEGACY_MOVEMENT_MODE", "0"),
        ("LINEAR_EASING", "0"),
        ("LINEAR_RAND", "2"),
        ("LONG_GLIDE", "1"),
        ("MALE", "\"male\""),
        ("MASK_INVERSE", "1"),
        ("MASK_SWAP", "2"),
        ("MATRIX_ROTATE", "5"),
        ("MATRIX_SCALE", "6"),
        ("MATRIX_TRANSLATE", "7"),
        ("MOB_LAYER", "4"),
        ("MOB_PERSPECTIVE", "0"),
        ("MOUSE_ACTIVE_POINTER", "1"),
        ("MOUSE_ARROW_POINTER", "5"),
        ("MOUSE_CROSSHAIRS_POINTER", "6"),
        ("MOUSE_DRAG_POINTER", "3"),
        ("MOUSE_DROP_POINTER", "4"),
        ("MOUSE_HAND_POINTER", "7"),
        ("MOUSE_INACTIVE_POINTER", "0"),
        ("MS_WINDOWS", "\"MS Windows\""),
        ("NEUTER", "\"neuter\""),
        ("NORMAL_RAND", "1"),
        ("NORTH", "1"),
        ("NORTHEAST", "5"),
        ("NORTHWEST", "9"),
        ("NO_CLIENT_COLOR", "16"),
        ("NO_STEPS", "0"),
        ("OBJ_LAYER", "3"),
        ("OUTLINE_SHARP", "1"),
        ("OUTLINE_SQUARE", "2"),
        ("PASS_MOUSE", "1024"),
        ("PIXEL_MOVEMENT_MODE", "2"),
        ("PIXEL_SCALE", "512"),
        ("PLANE_MASTER", "128"),
        ("PLURAL", "\"plural\""),
        ("PROFILE_AVERAGE", "4"),
        ("PROFILE_CLEAR", "2"),
        ("PROFILE_REFRESH", "0"),
        ("PROFILE_RESTART", "2"),
        ("PROFILE_START", "0"),
        ("PROFILE_STOP", "1"),
        ("QUAD_EASING", "7"),
        ("RESET_ALPHA", "4"),
        ("RESET_COLOR", "2"),
        ("RESET_TRANSFORM", "8"),
        ("SEE_BLACKNESS", "1024"),
        ("SEE_INFRA", "64"),
        ("SEE_MOBS", "4"),
        ("SEE_OBJS", "8"),
        ("SEE_PIXELS", "256"),
        ("SEE_SELF", "32"),
        ("SEE_THRU", "512"),
        ("SEE_TURFS", "16"),
        ("SIDE_MAP", "2"),
        ("SINE_EASING", "1"),
        ("SLIDE_STEPS", "2"),
        ("SOUND_MUTE", "1"),
        ("SOUND_PAUSED", "2"),
        ("SOUND_STREAM", "4"),
        ("SOUND_UPDATE", "16"),
        ("SOUTH", "2"),
        ("SOUTHEAST", "6"),
        ("SOUTHWEST", "10"),
        ("SQUARE_RAND", "3"),
        ("SYNC_STEPS", "3"),
        ("TILED_ICON_MAP", "32768"),
        ("TILE_BOUND", "256"),
        ("TILE_MOVEMENT_MODE", "1"),
        ("TILE_MOVER", "2048"),
        ("TOPDOWN_LAYER", "10000"),
        ("TOPDOWN_MAP", "0"),
        ("TRUE", "1"),
        ("TURF_LAYER", "2"),
        ("UNIFORM_RAND", "0"),
        ("UNIX", "\"UNIX\""),
        ("UP", "16"),
        ("VIS_HIDE", "128"),
        ("VIS_INHERIT_DIR", "4"),
        ("VIS_INHERIT_ICON", "1"),
        ("VIS_INHERIT_ICON_STATE", "2"),
        ("VIS_INHERIT_ID", "32"),
        ("VIS_INHERIT_LAYER", "8"),
        ("VIS_INHERIT_PLANE", "16"),
        ("VIS_UNDERLAY", "64"),
        ("WAVE_BOUNDED", "2"),
        ("WAVE_SIDEWAYS", "1"),
        ("WEST", "8"),
    ] {
        macros.insert(
            name.into(),
            Macro {
                parameters: None,
                variadic: false,
                replacement: replacement.into(),
            },
        );
    }

 },
 InitialEnvironment::OriginalChecker0290=>original_each(|name,definition|{macros.insert(name.into(),definition);}),
}}

pub(crate) fn original_each(mut emit:impl FnMut(&'static str,Macro)){
 for &(name,replacement)in original::ORIGINAL_DEFAULT_CONSTANTS{emit(name,Macro{parameters:None,variadic:false,replacement:replacement.into()});}
 for &(name,parameters,replacement)in original::ORIGINAL_DEFAULT_FUNCTIONS{emit(name,Macro{parameters:Some(parameters.iter().map(|name|(*name).to_owned()).collect()),variadic:false,replacement:replacement.into()});}
}

/// Borrows the current macro environment; it does not own macros or source.
pub(crate) struct ContextLookup<'a> {
    pub inner: &'a dyn crate::MacroLookup,
    pub environment: InitialEnvironment,
}
impl crate::MacroLookup for ContextLookup<'_> {
    fn initial_environment(&self) -> InitialEnvironment { self.environment }
    fn get_key_value(&self, name: &str) -> Option<(&str, &crate::Macro)> { self.inner.get_key_value(name) }
    fn contains_key(&self, name: &str) -> bool { self.inner.contains_key(name) }
    fn location_read(&self, file: bool) { self.inner.location_read(file) }
}

#[cfg(test)]mod tests{
 use super::*;
 use crate::{SourceProvider,regions::{plan_regions,expand_regions_text}};
 use std::path::{Path,PathBuf};
 struct Files{environment:InitialEnvironment,files:BTreeMap<PathBuf,String>}
 impl SourceProvider for Files{
  fn initial_environment(&self)->InitialEnvironment{self.environment}
  fn read(&self,path:&Path)->Result<String,String>{self.files.get(path).cloned().ok_or_else(||format!("missing actual fixture {}",path.display()))}
 }
 fn issue_plan(environment:InitialEnvironment,rows:&[(&str,&str)])->crate::regions::DirectivePlan{
  let source=Files{environment,files:rows.iter().map(|(p,t)|(PathBuf::from(p),t.to_string())).collect()};
  plan_regions(Path::new("project.dme"),&source,&BTreeMap::new())
 }
 #[test]fn original_environment_installs_all_and_only_the_pinned_104_default_macros(){
  let mut actual=BTreeMap::new();install(InitialEnvironment::OriginalChecker0290,&mut actual);
  assert_eq!(actual.len(),104);assert_eq!(original::ORIGINAL_DEFAULT_CONSTANTS.len(),102);
  for(name,value)in original::ORIGINAL_DEFAULT_CONSTANTS{let row=&actual[*name];assert!(row.parameters.is_none());assert!(!row.variadic);assert_eq!(&row.replacement,value);}
  for(name,args,value)in original::ORIGINAL_DEFAULT_FUNCTIONS{let row=&actual[*name];assert_eq!(row.parameters.as_deref(),Some(args.iter().map(|a|a.to_string()).collect::<Vec<_>>().as_slice()));assert!(!row.variadic);assert_eq!(&row.replacement,value);}
  assert_eq!(actual["DM_BUILD"].replacement,"1666");assert_eq!(actual["SPACEMAN_DMM"].replacement,"1");
  assert!(!actual.contains_key("REGEX_QUOTE"));assert!(!actual.contains_key("__MAIN__"));
 }
 #[test]fn original_undef_restores_the_actual_definition_stack_while_native_keeps_its_existing_remove_semantics(){
  let source="#define TRUE 2\n#define TRUE 3\nvar/a = TRUE\n#undef TRUE\nvar/b = TRUE\n#undef TRUE\nvar/c = TRUE\n#undef TRUE\n#ifdef TRUE\n#error original final undef must exhaust the initial binding\n#endif\n";
  let plan=issue_plan(InitialEnvironment::OriginalChecker0290,&[("project.dme",source)]);assert!(plan.diagnostics.is_empty(),"{:?}",plan.diagnostics);let out=expand_regions_text(&plan,1);assert!(out.text.contains("var/a = 3"));assert!(out.text.contains("var/b = 2"));assert!(out.text.contains("var/c = 1"));assert!(!plan.final_macros.contains_key("TRUE"));
  let native=issue_plan(InitialEnvironment::Native5161687,&[("project.dme","#define TRUE 2\n#define TRUE 3\n#undef TRUE\nvar/native = TRUE\n")]);assert!(!native.final_macros.contains_key("TRUE"));assert!(expand_regions_text(&native,1).text.contains("var/native = TRUE"));
 }
 #[test]fn original_main_ifdef_uses_actual_file_but_defined_uses_only_the_define_table(){
  let plan=issue_plan(InitialEnvironment::OriginalChecker0290,&[("project.dme","#ifdef __MAIN__\nvar/root_yes = DM_BUILD\n#endif\n#if defined(__MAIN__)\n#error original defined must not synthesize MAIN\n#endif\n#include \"child.dm\"\n"),("child.dm","#ifdef __MAIN__\n#error original child must not be MAIN\n#endif\nvar/child_yes = SPACEMAN_DMM\n")]);
  assert!(plan.diagnostics.is_empty(),"{:?}",plan.diagnostics);let output=expand_regions_text(&plan,1);
  assert!(output.diagnostics.is_empty(),"{:?}",output.diagnostics);assert!(output.text.contains("var/root_yes = 1666"));assert!(output.text.contains("var/child_yes = 1"));
 }
 #[test]fn original_body_defined_is_an_ordinary_call_and_dynamic_conditional_arguments_are_not_names(){
  let plan=issue_plan(InitialEnvironment::OriginalChecker0290,&[("project.dme","#define ARG 7\n/proc/defined_probe()\n    return defined(ARG)\n")]);
  assert!(plan.diagnostics.is_empty());let output=expand_regions_text(&plan,1);assert!(output.text.contains("return defined(7)"),"{}",&*output.text);
  for operand in["__FILE__","__LINE__"]{let source=format!("#if defined({operand})\nvar/invalid = 1\n#endif\n");let plan=issue_plan(InitialEnvironment::OriginalChecker0290,&[("project.dme",&source)]);assert!(plan.diagnostics.iter().any(|d|d.message.contains("malformed defined()")));}
 }
 #[test]fn original_unexpanded_condition_identifiers_refuse_but_null_and_native_zero_remain_distinct(){
  for name in ["missing_condition_variable","EXCEPTION"] {let source=format!("#if {name}\nvar/no = 1\n#endif\n");let plan=issue_plan(InitialEnvironment::OriginalChecker0290,&[("project.dme",&source)]);assert!(plan.diagnostics.iter().any(|d|d.message.contains("cannot reference variable")),"{:?}",plan.diagnostics);}
  let source="#if null\n#error null must be false\n#endif\n";let plan=issue_plan(InitialEnvironment::OriginalChecker0290,&[("project.dme",source)]);assert!(plan.diagnostics.is_empty(),"{:?}",plan.diagnostics);
  let plan=issue_plan(InitialEnvironment::Native5161687,&[("project.dme","#if missing_condition_variable\n#error native zero behavior changed\n#endif\n")]);assert!(plan.diagnostics.is_empty(),"{:?}",plan.diagnostics);
 }
 #[test]fn original_conditional_numeric_domain_matches_the_pinned_float_null_and_mask_rules(){
  let source=include_str!("../../../../analyze/fixtures/native-analysis-context/basic/code/numeric.dm");
  let plan=issue_plan(InitialEnvironment::OriginalChecker0290,&[("project.dme",source)]);assert!(plan.diagnostics.is_empty(),"{:?}",plan.diagnostics);
 }
 #[test]fn original_multiline_macro_keeps_invocation_line_but_following_source_uses_its_actual_line(){
  let source="#define PASS(value) value\nvar/a=PASS(\n__LINE__\n)+__LINE__\n#undef PASS\n";
  let plan=issue_plan(InitialEnvironment::OriginalChecker0290,&[("project.dme",source)]);assert!(plan.diagnostics.is_empty(),"{:?}",plan.diagnostics);let out=expand_regions_text(&plan,1);assert!(out.diagnostics.is_empty(),"{:?}",out.diagnostics);let tokens:Vec<_>=dm_syntax::lex(&out.text).tokens.into_iter().filter(|token|!matches!(token.kind,dm_syntax::TokenKind::Whitespace|dm_syntax::TokenKind::Newline|dm_syntax::TokenKind::Comment)).map(|token|token.text).collect();assert!(tokens.windows(3).any(|tokens|tokens==["2","+","4"]),"{tokens:?}");
 }
 #[test]fn original_function_defined_uses_real_conditional_context_while_body_operands_expand(){
  let text="#define VALUE 7\n#define HAS(name) defined(name)\n#if HAS(VALUE)\n/datum/conditional_name_is_preserved\n#else\n#error actual defined argument name was expanded\n#endif\n/proc/body_defined()\n    return defined(VALUE) + HAS(VALUE)\n";let plan=issue_plan(InitialEnvironment::OriginalChecker0290,&[("project.dme",text)]);assert!(plan.diagnostics.is_empty(),"{:?}",plan.diagnostics);let out=expand_regions_text(&plan,1);assert!(out.diagnostics.is_empty(),"{:?}",out.diagnostics);assert!(out.text.contains("/datum/conditional_name_is_preserved"));assert!(out.text.contains("return defined(7) + defined(7)"),"{}",&*out.text);
  let native=issue_plan(InitialEnvironment::Native5161687,&[("project.dme","#define VALUE 7\n/proc/body_defined()\n    return defined(VALUE)\n")]);assert!(expand_regions_text(&native,1).text.contains("return defined(VALUE)"));
 }

}

#[cfg(test)]mod original_bootstrap_tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 #[test]fn actual_final_table_recipe_authenticates_all_defaults_and_caller_provenance_before_factory_demand(){
  let used=Arc::new(AtomicUsize::new(0));let a=dm_syntax::SettingAdmission::new(&used,1<<20,&||Ok(()));let mut finals=BTreeMap::new();install(InitialEnvironment::OriginalChecker0290,&mut finals);let caller=BTreeMap::from([("TRUE".to_owned(),"7".to_owned()),("FROM_CALLER".to_owned(),"1e3".to_owned())]);for(name,replacement)in &caller{finals.insert(name.clone(),Macro{parameters:None,variadic:false,replacement:replacement.clone()});}
  let mut count=0;visit_original_bootstrap_using(InitialEnvironment::OriginalChecker0290,&finals,&caller,&a,&mut|input|{count+=1;assert_eq!(input.provenance(),if caller.contains_key(input.name()){OriginalInitialProvenance::CallerDefinition}else{OriginalInitialProvenance::FixedDefault});Ok(())}).unwrap();assert_eq!(count,105);
  for mode in 0..4{let mut bad=finals.clone();match mode{0=>{bad.remove("FALSE");},1=>{bad.get_mut("FALSE").unwrap().replacement="2".into();},2=>{bad.get_mut("TRUE").unwrap().replacement="1".into();},_=>{bad.insert("FOREIGN".into(),Macro{parameters:None,variadic:false,replacement:"1".into()});}}let mut demanded=0;assert_eq!(visit_original_bootstrap_using(InitialEnvironment::OriginalChecker0290,&bad,&caller,&a,&mut|_|{demanded+=1;Ok(())}).unwrap_err().kind(),std::io::ErrorKind::InvalidInput);assert_eq!(demanded,0,"invalid actual recipe must not begin lexical issuance");}
  assert_eq!(used.load(Ordering::Acquire),0);
 }
}
