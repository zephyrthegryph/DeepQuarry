//! Shared original UI fixture assertions over borrowed actual producer DATA.
//! No filesystem/source/completion or semantic-model authority lives here.
use crate::{derived_selftest_policy::{Failure,LegacyAssertions},key_policy_control::{self as kc,Control},ui_actions_normalizer::{DispatcherControl,Normaliser,normaliser_from_using},ui_actions_js::{RawCall,tsx_calls_using}};
impl DispatcherControl for LegacyAssertions{fn invalid_pattern(&mut self,pattern:&str,message:String)->Failure{panic!("bad pattern {:?}: {}",pattern,message)}}
#[cfg(feature="native-policy")]impl DispatcherControl for crate::derived_selftest_policy::NativeAssertions<'_>{fn invalid_pattern(&mut self,pattern:&str,message:String)->Failure{match kc::format(self,format_args!("original UI dispatcher pattern unavailable ({pattern:?}): {message}")){Ok(message)=>Failure::Operational(std::io::Error::new(std::io::ErrorKind::Unsupported,message)),Err(actual)=>actual}}}
fn assertion<C:Control<Error=Failure>>(c:&mut C,ok:bool,what:std::fmt::Arguments<'_>)->Result<(),Failure>{c.checkpoint()?;if ok{Ok(())}else{Err(Failure::Assertion(kc::format(c,what)?))}}
pub(crate) fn normalizer<C:DispatcherControl<Error=Failure>>(c:&mut C)->Result<Normaliser,Failure>{
 let norm=normaliser_from_using(DISPATCHER_FIXTURE,c)?.map_err(Failure::Assertion)?;
 let key=norm.key_using("bolt-toggle",c)?;let camel=norm.key_using("boltToggle",c)?;assertion(c,key.as_deref()==Some("bolt_toggle")&&camel.as_deref()==Some("bolt_toggle"),format_args!("{:?}",camel))?;
 let first=norm.key_using("setScreen",c)?;let second=norm.key_using("targetState",c)?;assertion(c,first.as_deref()==Some("set_screen")&&second.as_deref()==Some("target_state"),format_args!("camel"))?;
 let bad=norm.key_using("bad key",c)?;let long=norm.key_using("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",c)?;let empty=norm.key_using("",c)?;assertion(c,bad.is_none()&&long.is_none()&&empty.is_none(),format_args!("rejects"))?;
 let names=["user","src","usr","ui","state","holder"];assertion(c,norm.reserved.len()==names.len()&&names.iter().all(|name|norm.reserved.contains(*name)),format_args!("reserved {:?}",norm.reserved))?;
 let missing=normaliser_from_using("nothing here",c)?.is_err();assertion(c,missing,format_args!("a dispatcher without the regexes must fail"))?;
 Ok(norm)
}
pub(crate) fn live<C:DispatcherControl<Error=Failure>>(live:Option<&str>,c:&mut C)->Result<(),Failure>{
 if let Some(text)=live{let actual=normaliser_from_using(text,c)?.map_err(Failure::Assertion)?;let key=actual.key_using("bolt-toggle",c)?;assertion(c,key.as_deref()==Some("bolt_toggle"),format_args!("the live ui_action_key() no longer matches"))?;}
 Ok(())
}
pub(crate) fn calls<C:Control<Error=Failure>>(c:&mut C)->Result<Vec<RawCall>,Failure>{
 let calls=tsx_calls_using(TSX_FIXTURE,c)?;
 let is=|index:usize,action:&str,keys:Option<&[&str]>|calls.get(index).is_some_and(|call|call.action==action&&match(&call.keys,keys){(None,None)=>true,(Some(a),Some(b))=>a.iter().map(String::as_str).eq(b.iter().copied()),_=>false});
 assertion(c,calls.len()>=8,format_args!("UI fixture calls missing: {:?}",calls))?;
 assertion(c,is(0,"go",Some(&["speed"])),format_args!("{:?}",calls[0]))?;
 assertion(c,is(1,"pick",Some(&["mode","ref","flag"])),format_args!("{:?}",calls[1]))?;
 assertion(c,is(2,"raw",Some(&["amount","name","kind","when","extra"])),format_args!("{:?}",calls[2]))?;
 assertion(c,is(4,"bolt-toggle",Some(&["targetState"])),format_args!("{:?}",calls[4]))?;
 assertion(c,is(5,"pick",None)&&is(6,"modal_close",None),format_args!("{:?}",&calls[5..7]))?;
 assertion(c,is(7,"bogus",Some(&[])),format_args!("{:?}",calls[7]))?;
 Ok(calls)
}
pub(crate) fn problems<'a,C:Control<Error=Failure>>(problems:impl Iterator<Item=&'a str>,breaker:impl FnOnce()->bool,c:&mut C)->Result<(),Failure>{
 let mut msgs=Vec::new();for message in problems{kc::row(c,&mut msgs)?;msgs.push(message)}assertion(c,msgs.len()==5,format_args!("{:?}",msgs))?;assertion(c,breaker(),format_args!("breaker through the bundle"))?;
 assertion(c,msgs.first().is_some_and(|s|s.contains("act('bogus') has no act_bogus")),format_args!("{:?}",msgs))?;
 assertion(c,msgs.get(1).is_some_and(|s|s.contains("passes bogus"))&&msgs.get(2).is_some_and(|s|s.contains("reserved"))&&msgs.get(3).is_some_and(|s|s.contains("'bad key' is rejected")),format_args!("{:?}",msgs))?;
 assertion(c,msgs.get(4).is_some_and(|s|s.contains("rejects this action name")),format_args!("{:?}",msgs))?;
 Ok(())
}
pub(crate) fn dx_rows<C:Control<Error=Failure>>(unsent:impl Iterator<Item=usize>,unvalidated:impl Iterator<Item=usize>,c:&mut C)->Result<(),Failure>{
 let at=|snippet:&str|DM_FIXTURE.split('\n').position(|line|line.contains(snippet)).unwrap()+1;
 let mut got=Vec::new();for line in unsent{kc::row(c,&mut got)?;got.push(line)}kc::sort_data(&mut got,&mut|a,b|{c.checkpoint()?;Ok::<_,Failure>(a.cmp(b))})?;let mut want=[at("act_go("),at("act_breaker(")];want.sort();assertion(c,got==want,format_args!("C1 {:?} want {:?}",got,want))?;
 let mut got=Vec::new();for line in unvalidated{kc::row(c,&mut got)?;got.push(line)}kc::sort_data(&mut got,&mut|a,b|{c.checkpoint()?;Ok::<_,Failure>(a.cmp(b))})?;let mut want=[at("var/x = amount + 1"),at("to_chat(user, name)"),at("helper(when)"),at("src.helper(extra)"),at("world << level")];want.sort();assertion(c,got==want,format_args!("C2 {:?} want {:?}",got,want))?;Ok(())
}
pub(crate) fn rows<'a,C:Control<Error=Failure>>(messages:impl Iterator<Item=&'a str>,breaker:bool,unsent:impl Iterator<Item=usize>,unvalidated:impl Iterator<Item=usize>,c:&mut C)->Result<(),Failure>{problems(messages,||breaker,c)?;dx_rows(unsent,unvalidated,c)}
#[cfg(feature="native-policy")]
pub fn check_inputs(live:Option<&str>,c:&mut crate::derived_selftest_policy::NativeAssertions<'_>)->Result<(),Failure>{let _=normalizer(c)?;self::live(live,c)?;let _=calls(c)?;Ok(())}

pub const DISPATCHER_FIXTURE: &str = r#"
/proc/ui_action_key(raw)
	if(!istext(raw) || !length(raw) || length(raw) > 64 || !GLOB.ui_action_raw_regex.Find(raw))
		return null
	var/out = GLOB.ui_action_camel_regex.Replace(raw, "$1_$2")
	out = replacetext(lowertext(out), "-", "_")
	return out
GLOBAL_DATUM_INIT(ui_action_raw_regex, /regex, regex(@"^[A-Za-z0-9_-]+$"))
GLOBAL_DATUM_INIT(ui_action_camel_regex, /regex, regex(@"([a-z0-9])([A-Z])", "g"))
GLOBAL_LIST_INIT(ui_reserved_arg_names, list("user", "src", "usr", "ui", "state", "holder"))
"#;

pub const DM_FIXTURE: &str = "/datum/proc/act_modal_close(mob/user, id)
\treturn TRUE
/obj/thing
\ttgui_id = \"Thing\"
/obj/thing/proc/act_go(mob/user, speed, force)
\tspeed = ui_number(speed, 0, 10)
\tif(!speed)
\t\treturn
/obj/thing/proc/act_pick(mob/user, mode, ref, flag)
\tvar/datum/D = find_ref(user, ref)
\tif(!!flag)
\t\treturn
\tswitch(mode)
\t\tif(\"a\")
\t\t\treturn
/obj/thing/proc/find_ref(mob/user, ref)
\treturn ui_ref(ref, null, /datum)
/obj/thing/proc/act_raw(mob/user, amount, name, kind, when, extra)
\tif(!amount)
\t\treturn
\tvar/x = amount + 1
\tto_chat(user, name)
\tif(kind == MODE_FAST)
\t\treturn
\thelper(when)
\tsrc.helper(extra)
/obj/thing/proc/helper(value)
\tworld << value
/obj/thing/subtype/proc/act_sub(mob/user, level, list/items)
\tvar/obj/level/marker = null
\tlevel = ui_bool(level)
\tfor(var/i in islist(items) ? items : list())
\t\treturn
/obj/thing/proc/act_bolt_toggle(mob/user, target_state)
\treturn ui_bool(target_state)
/obj/old
\ttgui_id = \"Old\"
DECLARE_UI(/obj/old, UI_TITLE(\"Old\"))
/obj/old/proc/act_whatever(mob/user, anything)
\treturn anything
/datum/capability/breakers
/proc/cap_breakers()
\treturn new /datum/capability/breakers
/obj/thing/capabilities()
\t. = ..()
\t. += thing_bundle()
/datum/capability/breakers/proc/act_breaker(mob/user, atom/holder, channel, force)
\tchannel = ui_number(channel, 1, 3)
\tif(!channel)
\t\treturn
/datum/capability/unused/proc/act_unused(mob/user, atom/holder, level)
\tworld << level
";

pub const BUNDLE_FIXTURE: &str = "/proc/thing_bundle()
\t. = list(cap_breakers())
";

pub const TSX_FIXTURE: &str = "
      <Button onClick={() => act('go', { speed: 5 })} />
      <Button onClick={() => act(\"pick\", {mode: 'a', 'ref': x.ref, flag})} />
      act('raw', { amount: 1, name: `n`, kind, when: a ? b : c, extra: { nested: 1 } });
      act('sub', {level: true, items: [1, 2]});
      act('bolt-toggle', { targetState: true });
      act(dynamicName, { a: 1 });
      act('pick', { ...params });
      act('modal_close', params);
      act('bogus');
      act('go', { speed: 1, bogus: 2 });
      act('go', { user: 'x' });
      act('go', { 'bad key': 1 });
      act('bad name!');
      act('breaker', { channel: 2 });
    ";


/// Exact legacy fallback location; constructing this path performs no IO.
pub fn live_dispatcher_fallback()->std::path::PathBuf{std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..").join(crate::ui_actions_policy::DISPATCHER)}

#[cfg(test)]mod original_phase_order_controls{
 use super::*;
 #[test]fn original_ui_problem_count_refuses_before_host_lookup_or_dx_phase(){let called=std::cell::Cell::new(false);let error=problems(std::iter::empty(),||{called.set(true);true},&mut LegacyAssertions).unwrap_err();assert!(!called.get());assert!(matches!(error,Failure::Assertion(text)if text=="[]"));}
 #[test]fn original_ui_breaker_assertion_precedes_problem_text_assertions(){let error=problems(["wrong";5].into_iter(),||false,&mut LegacyAssertions).unwrap_err();assert!(matches!(error,Failure::Assertion(text)if text=="breaker through the bundle"));}
}

/// Native prelude runs the SAME original fixture and optional-live assertions
/// with its actual operation program/scratch owner, never an ambient matcher.
#[cfg(feature="native-policy")]
pub fn check_inputs_with_patterns(live:Option<&str>,c:&mut crate::derived_selftest_policy::NativeAssertions<'_>,patterns:&dyn crate::native_pattern::Provider)->Result<(),Failure>{
 struct Native<'a,'p,'w>{actual:&'a mut crate::derived_selftest_policy::NativeAssertions<'w>,patterns:&'p dyn crate::native_pattern::Provider}
 impl Control for Native<'_,'_,'_>{type Error=Failure;const CHECKED:bool=true;
  fn native_patterns(&self)->Option<&dyn crate::native_pattern::Provider>{Some(self.patterns)}fn native_pattern_failed(&mut self,actual:std::io::Error)->Failure{Failure::Operational(actual)}
  fn checkpoint(&mut self)->Result<(),Failure>{self.actual.checkpoint()}fn reserve(&mut self,n:usize)->Result<(),Failure>{self.actual.reserve(n)}fn temporary(&mut self,slot:usize,n:usize)->Result<(),Failure>{self.actual.temporary(slot,n)}fn overflow(&mut self)->Failure{self.actual.overflow()}fn allocation_failed(&mut self)->Failure{self.actual.allocation_failed()}
 }
 impl DispatcherControl for Native<'_,'_,'_>{fn invalid_pattern(&mut self,pattern:&str,message:String)->Failure{match kc::format(self,format_args!("original UI dispatcher pattern unavailable ({pattern:?}): {message}")){Ok(message)=>Failure::Operational(std::io::Error::new(std::io::ErrorKind::Unsupported,message)),Err(actual)=>actual}}}
 let mut native=Native{actual:c,patterns};let _=normalizer(&mut native)?;self::live(live,&mut native)?;let _=calls(&mut native)?;Ok(())
}
