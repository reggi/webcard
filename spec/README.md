# Webcard Format

Webcard Format is an open, ZIP based container for portable web bookmarks, link previews, capture history, and optional interoperable extensions.

The first public specification is [Webcard Format 1.0.0](1.0.0/README.md). Archive formats identified by integer versions `1` and `2` were private application prototypes and are documented only for migration.

## Versioning

The specification uses Semantic Versioning. Patch releases clarify text without changing conformance. Minor releases add backward compatible capabilities. Major releases may introduce incompatible requirements. Published specification directories and schema identifiers are immutable.

## Implementations

A conforming core consumer reads the required container and metadata defined by the specification. A preserving consumer also retains extension entries it does not interpret. The Webcard macOS application is the reference preserving consumer and producer.
