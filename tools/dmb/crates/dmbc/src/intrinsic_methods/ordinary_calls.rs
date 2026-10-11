//! Ordinary callable absence is a language-profile interpretation, not a claim
//! that the DMB physically contains every VM builtin. Native positives remain opaque.
// Reference: https://www.byond.com/members/?command=reference&path=proc
// Reviewed 2026-10-11. Combined with the pinned OpenDream 516.1687 bootstrap
// catalog, this conservatively excludes documented functions and compiler forms.
use super::*;
use std::collections::BTreeSet;

pub(crate) const POLICY: &[u8] = concat!(
    "ordinary-call-dispatch-5161687-v1\0",
    ". .. ASSERT CRASH abs addtext alert arccos arcsin arglist arguments ascii2text block break browse browse_rsc call ckey ckeyEx cmptext cmptextEx continue copytext cos del do fcopy fcopy_rsc fdel fexists file file2text findtext findtextEx flick flist for ftp get_dir get_dist get_step get_step_away get_step_rand get_step_to get_step_towards goto hascall hearers html_decode html_encode icon icon_states if image initial input isarea isfile isicon isloc ismob isnull isnum isobj ispath issaved istext isturf istype length lentext link list list2params locate log lowertext max md5 min missile new newlist num2text ohearers orange output oview oviewers params2list pick prob rand rand_seed range return rgb roll round run set shell shutdown sin sleep sorttext sorttextEx sound spawn sqrt startup stat statpanel step step_away step_rand step_to step_towards switch text text2ascii text2file text2num text2path time2text turn typesof uppertext url_decode url_encode var view viewers walk walk_away walk_rand walk_to walk_towards while winclone winexists winget winset winshow",
    // Additional 516 compiler forms and lexical pseudo-functions: these stay
    // excluded even when absent from the physical/bootstrap procedure roster.
    " filter generator matrix regex nameof issubtype json_encode json_decode load_ext call_ext ref replacetext replacetextEx copytext_char length_char text2ascii_char ascii2text_char nonspantext spantext findtext_char findtextEx_char findlasttext findlasttextEx trunc fract arctan animate gradient rgb2num text2num_radix database alist pixloc vector __PROC__ __TYPE__ __IMPLIED_TYPE__"
).as_bytes();
// Documented primitive/compiler-created paths remain opaque; this does not
// infer runtime aliases or their executable representation.
pub(crate) const TYPE_POLICY: &str = "ordinary-type-namespace-5161687-v1\0/icon /image /mutable_appearance /matrix /regex /filter /generator /sound /savefile /database /database/query /world /client /list /alist /pixloc /vector /callee /exception";

pub(super) fn exclusions(catalog: &serde_json::Value) -> Result<BTreeSet<SymbolId>, String> {
    let mut names: BTreeSet<_> = std::str::from_utf8(POLICY)
        .map_err(|_| "ordinary callable policy is not UTF8")?
        .split_once('\0')
        .ok_or("ordinary callable policy domain absent")?
        .1
        .split_whitespace()
        .map(SymbolId::of)
        .collect();
    for record in catalog["Procs"]
        .as_array()
        .ok_or("ordinary callable native exclusions absent")?
    {
        names.insert(SymbolId::of(
            record["Name"]
                .as_str()
                .ok_or("ordinary callable exclusion malformed")?,
        ));
    }
    Ok(names)
}
