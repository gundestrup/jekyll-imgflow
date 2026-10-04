# README TODO

## Shared contract fixtures — OPEN

This gem is the build-time source of truth for image behavior: image source
discovery, ImgFlow Liquid tag syntax, image paths, transformations, and
image-specific configuration. The VS Code companion extension
(`jekyll-imgflow-vscode`) mirrors that observable behavior in TypeScript for
authoring-time autocomplete.

To keep the two implementations from drifting without coupling them at
runtime, this gem should own a small, versioned contract fixture set for the
image behavior it defines, and the VS Code extension should pin/copy the
relevant fixtures for its own tests rather than live-linking a branch.

### Ownership model

```text
jekyll-imgflow (this repo)
  spec/fixtures/contracts/image-tags/v1/
    basic-images.yml
    nested-image-paths.yml
    preset-examples.yml
    tag-syntax.yml

jekyll-imgflow-vscode (separate repo)
  test/fixtures/jekyll-imgflow-contract/v1/   # pinned copy
  test/fixtures/jekyll-site/                  # combined ImgFlow + Documents integration site
```

This gem owns the canonical image-tag fixtures because it defines the
build-time behavior. The VS Code extension copies/pins them and tests that
its TypeScript interpretation produces the same observable results.

The combined `jekyll-site/` integration fixture is owned by the VS Code
extension, because it is the only project that exercises ImgFlow and
Documents together in one workspace.

### Fixture scope

Image-tag fixtures should cover only authoring-visible behavior:

- Image source discovery
- ImgFlow tag syntax
- Image path handling
- Preset names and parameter completions
- Image configuration

They should NOT duplicate image transformation internals, manifest cache
behavior, provider implementations, or Jekyll rendering. Those belong in
this gem's own internal test suite, not in the cross-repository contract.

### Versioning and consumption

- Each fixture set carries a version directory (`v1/`).
- The VS Code extension records the source commit/gem version it pins to.
- Fixtures are copied into the consumer's test tree so tests run offline and
  reproducibly — no network fetch during every CI run.
- A future sync script in the VS Code repo may automate copying, but is not
  required initially.
- Fixture/schema changes are treated as compatibility changes and updated
  through explicit pull requests in each consumer.

### Why not a single shared fixture repository now

A neutral `jekyll-contract-fixtures` repository would add another release
process, another versioning system, cross-repository coordination, and more
CI complexity. It becomes worthwhile only when multiple external consumers
actually need the same fixtures. Until then, this gem owns its contract and
consumers pin copies.

### Why not live-link fixtures

A live branch dependency or per-run network download would make tests
non-reproducible, dependent on GitHub/network availability, vulnerable to
unexpected fixture changes, and hard to correlate with a released gem version.
