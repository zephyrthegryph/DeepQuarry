"""sys_lint module: the forms the DX framework replaces (doc/rewrite/dx_conventions.md).

Each rule counts one family of old forms. The baseline (tools/ci/sys_baseline/dx_old_forms.txt) is
the tree before the migration waves; it only shrinks, and each wave drives its rules to 0. A new
use of an old form fails CI immediately.
"""
import re

RULES = {
    "old_interaction_decl": "capabilities() with hand()/tool()/use_on()/insert() or a library capability (dx_conventions.md §2)",
    "old_tool_act": "a tool() entry or a library capability instead of a *_act tool proc (§2)",
    "old_emag": "the emag(say =, effect =) capability (§2)",
    "old_requirement": "needs = PROC_REF(x), else_say = \"...\" (§2)",
    "old_appearance": "draw(datum/look/look) (§3)",
    "old_manual_refresh": "nothing: changed() / dispatchers refresh automatically (§1, §3)",
    "old_ui": "tgui_data() plus ui_<action>(mob/user, named args) procs (§5)",
    "old_prompt": "ask_text/ask_number/ask_list/ask_yes_no/ask_color/ask_mob (§6)",
    "old_expiry": "timed_set(src, nameof(var), value, for_time =) (§7)",
    "old_field": "a plain var, or TRACKED(type, var, channel) (§1)",
    "old_verb_decl": "a native verb plus hidden_verbs() (§4)",
    "old_periodic": "periodic_cadence plus should_run()/periodic_step(dt) (§4)",
    "manual_fingerprint": "nothing: the dispatcher fingerprints (§2, §8)",
}

PATTERNS = {
    "old_interaction_decl": re.compile(r"\b(DECLARE_INTERACTIONS|EXTEND_INTERACTIONS|INTERACT_[A-Z_]+|dq_interaction_from_spec)\s*\(|/declare_interactions\(|^/datum/interaction/(machine_hand|machine_item|machine_alt)/"),
    "old_tool_act": re.compile(r"^/[\w/]+/(crowbar|screwdriver|wirecutter|wrench|welder|multitool|analyzer)_act\s*\("),
    "old_emag": re.compile(r"\b(DECLARE_EMAG\w*)\s*\(|/emag_act\s*\("),
    "old_requirement": re.compile(r"\bREQ_[A-Z_]+\b"),
    "old_appearance": re.compile(r"\b(APPEARANCE_(TEMPLATE|LEVEL|EMISSIVE|SLOT|WATCH|NONE)|DECLARE_APPEARANCE\w*)\s*\(|^/[\w/]+/update_icon\s*\("),
    "old_manual_refresh": re.compile(r"(^|[^\w/])(update_icon|queue_icon_update)\s*\(\s*\)"),
    "old_ui": re.compile(r"\b(DECLARE_UI\w*|UI_ACT\w*|UI_DATA\w*|UI_ARG_\w+|UI_SUBACT\w*)\s*\("),
    "old_prompt": re.compile(r"\b(act_ask|topic_ask|rerun_ask|rerun_ask_on|verb_ask|client_ask|flow_ask|om_ask|om_ask_sequence)\s*\("),
    "old_expiry": re.compile(r"\bEXPIRY_\w+\s*\("),
    "old_field": re.compile(r"\b(OM_FIELD|OM_FLAG_FIELD\w*|OM_DERIVE_FIELD|OM_FIELD_SETTER)\s*\("),
    "old_verb_decl": re.compile(r"\bDECLARE_VERB\w*\s*\("),
    "old_periodic": re.compile(r"\b(DECLARE_PERIODIC\w*|DECLARE_REPEAT)\s*\(|/machine_step\s*\("),
    "manual_fingerprint": re.compile(r"\badd_fingerprint\s*\("),
}

# The framework's own files define or bridge the old forms until they are deleted.
EXEMPT_PREFIXES = (
    "code/__defines/",
    "code/datums/capabilities/",
    "code/datums/sys/",
    "code/datums/interactions/",
    "code/datums/om/",
    "code/modules/detectivework/",
)


def scan(files):
    out = {rule: [] for rule in RULES}
    for rel, lines in files:
        if rel.startswith(EXEMPT_PREFIXES):
            continue
        for number, line in enumerate(lines, 1):
            code = line.split("//", 1)[0]
            if not code.strip():
                continue
            for rule, pattern in PATTERNS.items():
                if pattern.search(code):
                    out[rule].append((rel, number))
    return out
