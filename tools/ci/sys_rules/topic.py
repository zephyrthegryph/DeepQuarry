"""TOPIC_ACTION registry lint (doc/rewrite/systems.md §20).

The whole old pattern: Topic() overrides, raw href_list dispatch chains, raw ref lookups and
number parsing from href_list. Every href value reaches code through a TOPIC_ACTION row's
declared spec (TOPIC_REF / TOPIC_NUM / TOPIC_TEXT) instead.
"""
import re

RULES = {
    "topic_override": "declare TOPIC_ACTION(type, href_key, PROC_REF(handler), specs...) rows "
    "instead of overriding Topic() (doc/rewrite/systems.md §20)",
    "topic_raw_dispatch": "one TOPIC_ACTION row per href key (\"key=value\" rows for value "
    "switches) instead of if/switch on href_list[...]",
    "topic_raw_locate": "declare TOPIC_REF(name, type[, source]) and read args[name]; never "
    "locate() a ref straight from href_list",
    "topic_raw_num": "declare TOPIC_NUM(name) and read args[name] instead of text2num(href_list[...])",
}

OVERRIDE = re.compile(r"^/[\w/]*?/(?:proc/)?Topic\s*\(")
DISPATCH = re.compile(r"\b(?:if|switch)\s*\(\s*!?\s*href_list\s*\[|\bIF_VV_OPTION\s*\(")
LOCATE = re.compile(r"\blocate(?:_in_list)?\s*\([^)]*\bhref_list\s*\[")
NUM = re.compile(r"\btext2num\s*\(\s*href_list\s*\[")


def scan(files):
    out = {rule: [] for rule in RULES}
    for rel, lines in files:
        for number, line in enumerate(lines, 1):
            code = line.split("//", 1)[0]
            if OVERRIDE.match(line):
                out["topic_override"].append((rel, number))
            if DISPATCH.search(code):
                out["topic_raw_dispatch"].append((rel, number))
            if LOCATE.search(code):
                out["topic_raw_locate"].append((rel, number))
            if NUM.search(code):
                out["topic_raw_num"].append((rel, number))
    return out
