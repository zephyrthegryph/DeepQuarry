//! Metadata moved from the actual sys_sfx registration fields; no scanner.
use crate::lint::RuleMeta;
pub const RULES: &[RuleMeta] = &[
    RuleMeta {
        name: "literal_playsound",
        hint: "play_sfx(atom, SFX_ID) with a SOUND_SET row (code/game/sound_sets.dm), not a literal file",
    },
    RuleMeta { name: "literal_sound_var", hint: "hold a SOUND_SET id (SFX_*) in sound vars/lists fed to playsound, not a literal file" },
    RuleMeta { name: "sfx_string_key", hint: "pass the SFX_* id, not the bare string key" },
    RuleMeta { name: "spark_triple", hint: "fx_sparks(atom, amount, cardinals), not a spark_spread new/set_up/start" },
];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(RULES,&[],names,control)?;
 control.checkpoint()
}
