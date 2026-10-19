# Parser operational contract

Parser 0.4 keeps `ParseContractSnapshot` as the description of what a parser
produced. Schema 1 of
`ParseOperationalSnapshot` separately describes how an invocation was exposed:
which portable features and counters the engine supports, which positive limits
were requested, which limits were reached, and why execution stopped.

This separation prevents unlike algorithms from manufacturing comparable
internals. An Earley implementation may report chart items while a generalized
LR implementation reports configurations and packed families. Either may also
declare a generic `workItems` counter, but only when its adapter defines and
measures that counter consistently.

## Dispositions

- `completed` requires a semantic `ParseContractSnapshot`. An ordinary rejected
  sentence is still a completed invocation whose parse status is `rejected`.
- `limited` requires at least one requested counter in `reachedLimits` and may
  retain a partial semantic result.
- `unsupported`, `cancelled`, and `failed` remain distinct and cannot masquerade
  as rejected input.

## Provenance and executable validation

An engine that consumes Grammar's normal-form output declares
`normalizationProvenance` and its supported targets, then attaches the exact
`GrammarNormalizationReport` used for construction. Parser validates every
tree, forest, diagnostic, and replay production identity against that report's
output using the executable parser laws. This provides an unbroken path from
runtime evidence to the source production IDs without moving normalization into
Parser.

Observable measurements—forest nodes, ambiguity sites, replay events,
diagnostics, and recovery edits—must equal their serialized evidence. All other
counters are explicit engine observations. Duplicate declarations, undeclared
measurements, non-positive limits, mismatched engines, incomplete provenance,
and future schema versions fail closed.

The authoritative serialized shape is
`Schemas/ParserOperationalContract.schema.json`.
