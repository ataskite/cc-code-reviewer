# Security design invariant model evaluation

These fixtures evaluate semantic recognition, not deterministic keyword matching.
Run each Maven project with the plugin in `security` mode and the same model
profile. Do not add project review rules.

## Cases

- `renamed-fail-open`: neutral class and method names; an absent decision and a
  successful decision collapse to the same state, which a later stage treats as
  permission to reach an external effect. Expected: one Default Deny /
  Fail-Closed finding with the complete cross-file evidence chain.
- `explicit-fail-closed`: the same structural shape uses an explicit state model
  and only one proven state can reach the external effect. Expected: no Default
  Deny finding.

## Repeatability target

Run each case five times. The fail-open case should be found at least four times;
the fail-closed control may produce at most one false positive. This is a model
quality target, not a deterministic test-suite assertion. Bash tests only verify
that neutral imports remain in one structural review unit.
