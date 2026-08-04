# Final classification report

Generated: 2026-08-03T03:31:45.049Z

## Counts

- Source nodes: 4008
- Navigation only: 582
- Confirmed: 1089
- Review required: 894
- Rejected: 1403
- Unsupported: 40
- Activity unknown (overlapping activity axis): 4008
- Remaining C/D/E sampled/terminated: 598/598
- Official product evidence rows: 4,044

## Existing and new decisions

- Existing DB-corresponding snapshot nodes: 2,032 (2,031 DB rows; N:N identity retained)
- Existing decisions retained at snapshot-node level: 1,767
- Existing decisions with a status-change recommendation: 265 (principally non-leaf nodes normalized to `navigation_only`)
- New nodes: 1,976 = navigation_only 317 + confirmed 178 + review_required 514 + rejected 927 + unsupported 40

## App and comparison mapping

- Direct app mappings: 1,075
- Transform-required app mappings: 14
- Unsupported by current app: 40
- App taxonomy/policy extension required: 54
- New comparison policy required: 54
- Category-level comparison eligible: 1,089
- Category-level app mapping withheld by design: 2,919

## Promotion readiness

- Canonical source category rows ready: 4,008
- Canonical decision rows ready: 4,008
- Confirmed category-level app mapping rows ready: 1,089
- Canonical migration executed: no
- Promotion approval recorded: no

## Validation

```json
{
  "source_nodes": 4008,
  "hierarchy_edges": 3978,
  "unclassified": 0,
  "identity_unresolved": 0,
  "unsupported_as_rejected": 0,
  "navigation_as_rejected": 0,
  "rejected_with_comparison_policy": 0,
  "confirmed_missing_semantic": 0,
  "confirmed_missing_family": 0,
  "status_total": 4008,
  "duplicate_source_key_conflicts": 0,
  "app_mapping_conflicts": 0
}
```

Independent integrity checks: orphan parents 0, duplicate source-key groups 0, conflicting source-key groups 0.

All observed nodes are preserved. Only confirmed decisions receive category-level app mappings. Review-required uses product fallback; unsupported keeps semantic meaning; rejected and navigation nodes have no comparison policy. No canonical migration or app source change was performed.
