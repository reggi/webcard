# Webcard Format Governance

## Releases

Webcard Format uses Semantic Versioning. Published version directories, schema files, schema identifiers, examples, and normative text are immutable. Corrections that change conformance require a new specification release.

Patch releases clarify wording without changing valid or invalid documents. Minor releases add backward compatible optional capabilities. Major releases may change required behavior or representation.

The macOS application version is independent from the format version. An application release may support multiple format versions and must document which versions it reads and writes.

## Changes

Every proposed format change must include its interoperability goal, compatibility impact, security impact, migration behavior, schema changes, valid examples, invalid examples, and reference implementation tests. Changes should reuse established standards instead of defining Webcard specific equivalents.

Core fields are reserved for broadly interoperable concepts. Experimental and application specific work belongs in a namespaced extension until multiple independent implementations demonstrate that it belongs in the core.

## Extensions

An extension identifier is an absolute HTTPS URL controlled by its publisher. Extension documentation must define ownership, versioning, JSON values, files, integrity rules, preservation requirements, and failure behavior. Extensions may not redefine core fields or weaken core validation.

## Compatibility

Readers reject unsupported major versions. Readers may accept a later minor version only when they understand its required capabilities. Writers never silently downgrade files. Preserving consumers retain unknown namespaced extension metadata and files or refuse to rewrite the archive.

Legacy integer formats `1` and `2` are unsupported private prototypes. The reference application reads and writes only Webcard Format 1.0.0.
