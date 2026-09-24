# Webcard Format 1.0.0

## Status

This document defines Webcard Format 1.0.0. The key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT, RECOMMENDED, NOT RECOMMENDED, MAY, and OPTIONAL are interpreted as described by RFC 2119 and RFC 8174 when they appear in uppercase.

## Scope

Webcard is a portable container for a web resource and one or more dated metadata captures. The core format is intentionally small. Offline page archives, annotations, provenance records, signatures, and application specific data are extensions rather than requirements for a basic bookmark.

## Media type and extension

The filename extension is `.webcard`. Until an IANA registration is completed, implementations SHOULD use `application/vnd.everything.webcard+zip` as a provisional media type and MUST NOT claim that it is registered.

## Container

A Webcard file MUST be a ZIP archive compatible with ISO/IEC 21320-1. Version 1.0.0 producers MUST store entries without ZIP compression for maximum extractor compatibility and because WebP and WACZ assets are already compressed. It MUST NOT use encryption. It MUST NOT contain absolute paths, `.` or `..` path segments, backslashes, NUL characters, symlinks, hard links, duplicate entry names, or entries whose normalized names collide. Entry names MUST be UTF-8 and use `/` separators.

The first local file entry MUST be `mimetype`. It MUST be stored without compression and its exact UTF-8 contents MUST be `application/vnd.everything.webcard+zip` with no byte order mark or trailing newline.

Unpacked source examples may store a final newline in `mimetype` for text file compatibility. A producer packaging those examples MUST remove it from the ZIP entry.

The archive MUST contain `webcard.json`, one or more capture documents under `captures/`, and every asset referenced by those documents. Core producers MUST place content addressed assets under `assets/sha256/`. Extension entries MUST be placed under `extensions/<namespace>/` or `signatures/`.

Consumers MUST enforce implementation appropriate limits for archive size, expanded size, entry count, compression ratio, metadata size, and asset size before allocating unbounded resources. These limits are implementation profiles and are not universal format limits.

## Root document

`webcard.json` MUST be UTF-8 JSON conforming to `schemas/webcard.schema.json`. It MUST contain:

| Field | Meaning |
|---|---|
| `formatVersion` | Exact specification version, `1.0.0` |
| `sourceURL` | Absolute HTTP or HTTPS URL originally saved |
| `currentCapture` | Relative path of the selected capture document |
| `captures` | Ordered, nonempty array of unique capture document paths |
| `lastRefreshedAt` | Optional RFC 3339 timestamp of the latest refresh attempt |

Capture ordering is chronological from oldest to newest. `currentCapture` MUST occur in `captures`. Consumers MUST ignore unknown root properties from compatible minor versions, but preserving consumers MUST retain them when rewriting an archive.

## Capture documents

Each capture document MUST be stored directly under `captures/` and MUST use a portable UTC timestamp filename matching `YYYYMMDDTHHMMSS.sssZ.json`. Producers MUST add a deterministic numeric suffix before `.json` if multiple captures would otherwise have the same filename.

A capture document MUST conform to `schemas/capture.schema.json`. Its `id` MUST equal its filename without `.json`. Its `capturedAt` value MUST represent the same instant encoded by the filename. A capture contains the canonical URL observed at capture time, display metadata, a required image asset, and optional icon and source metadata.

Text is Unicode. Producers SHOULD normalize newly generated text to NFC, but consumers MUST NOT alter preserved text solely to normalize it. JSON object member order is insignificant. Duplicate JSON object names are invalid.

## URLs

`sourceURL` and `canonicalURL` MUST be absolute HTTP or HTTPS URLs and MUST NOT include user information. Producers MUST preserve the requested source URL separately from the canonical URL reported by the captured page. Consumers MUST compare URLs as identifiers unless an application explicitly applies RFC 3986 normalization for a documented purpose.

## Time

JSON timestamps MUST be RFC 3339 date time strings in UTC with a `Z` suffix. Producers MUST emit millisecond precision. Consumers MAY accept additional RFC 3339 fractional precision but MUST preserve the represented instant.

## Assets and integrity

An asset reference contains `path`, `mediaType`, `sha256`, and `byteLength`. `sha256` is the lowercase hexadecimal SHA-256 digest of the exact stored bytes. `byteLength` is the uncompressed byte length. The path MUST be `assets/sha256/<sha256>.<extension>`, where the extension is consistent with the declared media type. Two references with the same digest MUST resolve to identical bytes.

Core 1.0.0 producers use WebP for generated card images and icons. Consumers MUST use the declared media type rather than infer type only from the extension. Future compatible versions may allow additional registered media types.

Every referenced asset MUST exist and pass digest and length validation. Core entries that are not referenced by a root or capture document are invalid. Extension entries are governed by their extension specification.

## Source metadata and provenance

`sourceMetadata` records values extracted from the source page. The defined keys preserve common Open Graph, article, and Twitter values without making those vocabularies part of the core display model. An extension that needs detailed provenance SHOULD record the source vocabulary, source property, extraction time, extraction software, and original value under a namespaced extension.

## Extensions

Extension identifiers MUST be absolute HTTPS URLs controlled by the extension publisher. Root and capture documents MAY contain an `extensions` object whose keys are extension identifiers. Implementations MUST ignore extension values they do not understand. Preserving consumers MUST retain unknown extension JSON values and files byte for byte when a rewrite does not explicitly replace that extension.

Files belonging to an extension MUST be stored under `extensions/<namespace>/`, where `<namespace>` is a stable collision resistant identifier documented by the extension. Extensions MUST NOT redefine core fields or weaken core validation.

Offline page snapshots SHOULD be represented by a WACZ asset through an extension instead of embedding an undocumented site archive. Annotations SHOULD reuse the W3C Web Annotation Data Model through an extension.

## Signatures

Signatures are OPTIONAL. A signature profile MUST identify the signed specification version, canonicalization algorithm, digest algorithm, signature algorithm, signer material, and exact inventory of signed paths. A signature MUST NOT sign its own entry. Signature profiles SHOULD use RFC 8785 JSON Canonicalization and an established signature envelope such as JWS or COSE. Core 1.0.0 does not require consumers to verify signatures.

Changing a signed entry invalidates the signature over that entry. Selecting a different current capture, adding an annotation, or refreshing metadata has signature consequences determined by the signed inventory and MUST NOT be presented as preserving a signature when signed bytes changed.

## Forward compatibility

A 1.0.x consumer MUST reject an unsupported major version. It MAY read a later minor version only when all required capabilities are understood. Unknown optional JSON properties and extension entries MUST NOT cause rejection. Unknown files outside defined extension locations MUST cause rejection.

Writers MUST NOT silently downgrade a later format. A preserving consumer MUST either retain unknown compatible data or refuse to rewrite the file.

## Security

Webcards are untrusted input. Consumers MUST defend against path traversal, duplicate paths, decompression bombs, oversized entries, malformed JSON, duplicate JSON keys, invalid Unicode, digest substitution, misleading media types, and archive entries that attempt to masquerade as directories or links. Opening a Webcard MUST NOT contact the network. Network refresh is a separate explicit application action.

## Deterministic production

Producers SHOULD generate reproducible archives by sorting entries lexically after the required first `mimetype` entry, storing every entry without compression, emitting sorted JSON keys, and assigning a stable ZIP timestamp. Semantic conformance never depends on ZIP entry order except for `mimetype`, but deterministic production is strongly recommended for verification and signatures.

## Conformance

A core producer MUST emit a valid container, root document, capture documents, and verified assets. A core consumer MUST validate all core requirements before presenting data as trusted. A preserving consumer additionally retains unknown compatible JSON properties and extension entries. The schemas are necessary but not sufficient for conformance because ZIP structure, cross file references, digests, ordering, and security rules require procedural validation.

## Legacy prototypes

The Webcard macOS application previously emitted integer archive versions `1` and `2` using `manifest.json`. Those layouts are not public Webcard Format versions. Reference implementations MAY read them for migration but MUST write Webcard Format 1.0.0.
