#!/usr/bin/env python3
"""Persist only reference candidates proved by a Simulator registration probe."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path


event_path = Path(sys.argv[1])
candidate_path = Path(sys.argv[2])
output_path = Path(sys.argv[3])

events = event_path.read_text(encoding="utf-8")
candidates = json.loads(candidate_path.read_text(encoding="utf-8"))["candidates"]
by_key = {
    (item["source"], str(item["product_id"]), item["target_category"], item["target_detail"]): item
    for item in candidates
}

selected: dict[tuple[str, str], dict] = {}
for source, product_id, category, detail in re.findall(
    r"_REGISTERED source=(\S+) id=(\S+) target=([^/\s]+)/([^\s]+)", events
):
    candidate = by_key.get((source, product_id, category, detail))
    if candidate:
        selected.setdefault((category, detail), candidate)

all_targets = sorted({(item["target_category"], item["target_detail"]) for item in candidates})
selected_candidates = [selected[key] for key in sorted(selected)]
output_path.write_text(json.dumps({
    "selection_policy": "Simulator registration probe passed; official numeric table required",
    "candidates": selected_candidates,
    "unvalidated_targets_in_candidate_pool": [
        {"target_category": category, "target_detail": detail}
        for category, detail in all_targets if (category, detail) not in selected
    ],
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({
    "validated": len(selected_candidates),
    "unvalidated": len(all_targets) - len(selected_candidates),
}, ensure_ascii=False))
