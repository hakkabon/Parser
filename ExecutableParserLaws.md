# Executable parser laws

Parser 0.3.1 turns the portable parse contract into executable invariants. It
does not invoke an engine. It validates an engine's exported observation and
compares two observations produced from a Grammar-owned metamorphic witness.

`ParseLawVerifier.validate` checks:

- production-identified tree spans, nesting, sibling order, and left-hand-side
  agreement;
- forest identity, extents, pivots, references, production identities, and
  ambiguity markers;
- contiguous replay, valid token/production/forest references, and a terminal
  event consistent with parse status.

`ParseLawVerifier.evaluate` checks the baseline and candidate separately before
comparing status, tree, forest topology, diagnostics, recovery, and portable
replay. Alpha-renamed observations are canonicalized through the witness's
inverse mapping; engine descriptors and presentation-only diagnostic messages
are not treated as language evidence.

A failed evaluation can become a `ParseLawDiscrepancy`. The schema-1 artifact
contains the grammar witness, input, both complete parse contracts, positioned
violations, and an FNV-1a semantic fingerprint. Passing evaluations deliberately
produce no discrepancy.

The JSON shape is published in
`Schemas/ParseLawDiscrepancy.schema.json`. Parser engines remain responsible for
execution, while Grammar-REPL may later add generation and minimization around
this stable artifact.
