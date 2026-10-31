//! Frozen original complete raw handler policy versus the shared producer.
pub use dq_analyze::{sem,pat};
mod decls{pub use dq_analyze::sem::decls::*;}
#[path="support/reactive_hooks_original/producer.rs"]mod original;
use dq_analyze::tree::{Tree,SourceFile};
fn main()->Result<(),Box<dyn std::error::Error>>{
 let text=r#"CAPABILITIES(/obj/probe)
    op("use", ui_act("use", arg("amount")), needs(req(PROC_REF(reason)), req_bool(PROC_REF(boolean))), then(PROC_REF(apply)))
    when(PROC_REF(condition))
    on_change(all_of(PROC_REF(value), PROC_REF(other)), ANY, then(PROC_REF(deliver)))
    on_notice(/datum/notice/ended, then(PROC_REF(heard)))
CAPABILITY_TYPE(powered, CAP_POWERED, /datum/capability/powered, holder = /obj/probe, contributes(STAT_POWER, CAP_PROC(scale)))
/proc/install()
    observe(source, /datum/act/strike, listener, instead(when(TYPE_PROC_REF(/obj/probe, block))), needs(req(TYPE_PROC_REF(/obj/probe, admit)))))
    observe(source, /datum/act, listener, then(TYPE_PROC_REF(/obj/probe, notification)))
    // observe(source, /datum/act/strike, listener, then(PROC_REF(comment_fake)))
    var/text = "PROC_REF(string_fake)"
"#;
 let tree=Tree::from_files(vec![SourceFile::from_text("code/content/probe.dm",text)]);
 let decls=decls::Decls::get(&tree);
 let old=original::discover(&decls);let actual=sem::hooks::discover(&decls);
 macro_rules! rows{($rows:expr)=>{$rows.iter().map(|h|(h.owner.clone(),h.cap_proc,h.cap_type.clone(),h.proc.clone(),h.form,format!("{:?}",h.ctx),format!("{:?}",h.role),h.rel.clone(),h.line,h.notice.clone(),h.ui_args.clone())).collect::<Vec<_>>()}}
 let expected=rows!(old);let observed=rows!(actual);
 if expected!=observed{return Err(format!("whole ordered raw handler policy mismatch\nold={expected:#?}\nshared={observed:#?}").into());}
 for name in ["reason","boolean","apply","condition","value","other","deliver","heard","scale","block","admit","notification"]{
  if !old.iter().any(|h|h.proc==name){return Err(format!("independent original fixture lacks {name}").into());}
 }
 let scale=old.iter().find(|h|h.proc=="scale").ok_or("independent old scale fixture missing")?;
 if !scale.cap_proc||scale.cap_type!="/datum/capability/powered"||scale.owner!="/obj/probe"||scale.form!="contributes"{return Err(format!("independent old CAP_PROC binding differs: {scale:?}").into());}
 if old.iter().any(|h|matches!(h.proc.as_str(),"comment_fake"|"string_fake")){return Err("independent old raw selector incorrectly selected string/comment control".into());}
 println!("whole original/shared handler rows exact: {} ordered rows",old.len());Ok(())
}
