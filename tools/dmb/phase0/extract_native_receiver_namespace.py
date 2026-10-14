"""Read-only extraction of pinned local BYOND documented receiver namespaces."""
import argparse
import hashlib
import json
import re
from pathlib import Path

COMPILER_SHA = "8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0"
DOC_SHA = {
    "contents.html": "69b6fec3b1e292f4a719f61d6ffe838dac0ab891ad1c829268231da4123d863d",
    "info.html": "5d428076e32d78713c2fe358b6710451788216604fe0e00ccd7be630454217dd",
}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if sha(args.compiler) != COMPILER_SHA:
        raise ValueError("compiler does not match pinned 516.1687")
    for name, expected in DOC_SHA.items():
        path = args.reference / name
        if path.stat().st_size > 2 * 1024 * 1024 or sha(path) != expected:
            raise ValueError("native reference does not match pinned documentation: " + name)
    owners = {}
    for owner, name in re.findall(r'href=info\.html#(/[^\s<>"#]+?)/proc/([^\s<>"#]+)',
                                  (args.reference / "contents.html").read_text(encoding="utf-8")):
        owners.setdefault(owner, set()).add(name)
    catalog = json.loads(args.catalog.read_text(encoding="utf-8"))
    inventory = {}
    for record in catalog["Procs"]:
        index = record.get("OwningTypeId")
        if isinstance(index, int):
            inventory.setdefault(catalog["Types"][index]["Path"], set()).add(record["Name"])
    if owners.get("/datum") != inventory.get("/datum"):
        raise ValueError("reviewed datum namespace and pinned conservative catalog differ")
    result = {
        "schema": 1, "compiler_sha256": COMPILER_SHA, "compiler_version": "516.1687",
        "reference": {name: {"path": str(args.reference / name), "sha256": digest}
                      for name, digest in DOC_SHA.items()},
        "closed_owners": ["/datum"],
        "member_name_union_closed": True,
        "member_name_union_limits": "Documented native receiver procedure-name union is available for explicit colon dispatch; native catalog-only names remain unsupported. Root global procedure names are excluded. Native verbs and unissued source rosters remain unsupported.",
        "limits": "Only reviewed documented /datum proc namespace and its source-defined descendants are closed. Other native owner namespaces and global procedures remain open. Known positive names are never converted to negative by omitted executable/ABI evidence.",
        "owners": {owner: {"documented_procs": sorted(names),
                           "catalog_only": sorted(inventory.get(owner, set()) - names),
                           "documented_missing_from_catalog": sorted(names - inventory.get(owner, set()))}
                   for owner, names in sorted(owners.items())},
        "native_catalog_sha256": sha(args.catalog),
    }
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")

if __name__ == "__main__":
    main()
