"""Stream resolved shared variables; unsupported answers are not negative facts."""
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    schema = json.loads(next(stream))
    if schema.get("schema") != "dm-tree-analysis-v3":
        raise SystemExit("Unsupported analysis schema")
    for line in stream:
        row = json.loads(line)
        if row.get("row") != "resolved_query":
            continue
        if row.get("schema") != "dm-resolved-query-v1":
            raise SystemExit("Unsupported query schema")
        answer = row["answer"]
        if answer.get("status") == "known" and answer.get("kind") == "shared_slot":
            print(json.dumps({
                "declaration": row["subject"],
                "owner": answer["owner"],
                "name": answer["name"],
                "slot": answer["slot"],
            }))
