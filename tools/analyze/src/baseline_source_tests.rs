use super::*;
use crate::tree::SourceFile;
#[path="../../dmb/shared/test_scratch.rs"]mod test_scratch;
struct Frozen(Vec<(String,usize,String)>);
impl SiteText for Frozen{fn site_text(&self,rel:&str,line:usize)->String{self.0.iter().find(|(r,n,_)|r==rel&&*n==line).map(|(_,_,s)|s.clone()).unwrap_or_default()}}
fn site(rule:&str,line:u32)->Site{Site{rule:rule.into(),rel:"code/a.dm".into(),line,msg:String::new(),key:String::new(),ident:String::new()}}
#[test]fn report_source_fingerprints_and_full_reports_equal_original_tree_without_a_model(){
 let tree=Tree::from_files(vec![SourceFile::from_text("code/a.dm","  set_power(5)  \n\tspawn(2) // retained original comment\n")]);
 let sites=[site("init_lines",1),site("spawn",2)];let refs=sites.iter().collect::<Vec<_>>();
 let frozen=Frozen(sites.iter().map(|s|(s.rel.clone(),s.line as usize,tree.site_text(&s.rel,s.line as usize))).collect());
 let old=fingerprints(&tree,&refs);let actual=fingerprints(&frozen,&refs);
 assert_eq!(old.iter().map(|f|(&f.text,&f.fp)).collect::<Vec<_>>(),actual.iter().map(|f|(&f.text,&f.fp)).collect::<Vec<_>>());assert_eq!(actual[0].fp,"power = 5");
 let rules=vec![("init_lines",vec![&sites[0]]),("spawn",vec![&sites[1]])];let mut a=String::new();let mut z=String::new();
 assert_eq!(check_sites("probe",&tree,&rules,&|_|"use native forms".into(),Path::new(""),&[],&mut a),check_sites("probe",&frozen,&rules,&|_|"use native forms".into(),Path::new(""),&[],&mut z));assert_eq!(a,z);assert!(z.contains("retained original comment"));
 let newer=Tree::from_files(vec![SourceFile::from_text("code/a.dm","changed(99)\nchanged(88)\n")]);assert_ne!(frozen.site_text("code/a.dm",1),newer.site_text("code/a.dm",1));
 assert_eq!(fingerprints(&frozen,&refs)[0].fp,"power = 5","report stays as-of supplied evidence instead of reading newer source");
}
#[test]fn report_source_update_still_only_shrinks_and_preserves_declaration_identity(){
 let root=test_scratch::dir("report-source-baseline");let path=root.join("baseline.txt");std::fs::write(&path,"rule\tcode/a.dm\t@/obj/a::value\nrule\tcode/gone.dm\told\n").unwrap();
 let mut s=site("rule",7);s.ident="/obj/a::value".into();s.msg="actual declaration explanation".into();let frozen=Frozen(vec![("code/a.dm".into(),7,"var/value = 3".into())]);
 let refs=vec![("rule",vec![&s])];assert_eq!(write_sites(&path,&["original header"],&frozen,&refs,&["rule"],Mode::Update).unwrap(),1);
 assert_eq!(std::fs::read_to_string(&path).unwrap(),"# original header\nrule\tcode/a.dm\t@/obj/a::value\n");
 let mut text=String::new();assert!(!check_sites("probe",&frozen,&refs,&|_|String::new(),&path,&[],&mut text));
 let other=site("rule",8);assert_eq!(write_sites(&path,&[],&frozen,&[("rule",vec![&s,&other])],&["rule"],Mode::Update).unwrap(),1,"new report rows cannot raise a baseline");
}
