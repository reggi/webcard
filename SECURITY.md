# Security

Report suspected vulnerabilities privately through GitHub Security Advisories for the repository. Do not include sensitive exploit details in a public issue before a fix is available.

Webcard files are untrusted ZIP archives. Implementations must validate paths, entry types, duplicate names, entry count, expanded size, metadata size, asset size, declared byte lengths, digests, media types, and cross file references before rendering content. Opening a file must not initiate network access.

The reference application uses a 20 MiB compressed archive limit, a 64 MiB expanded limit, a 1,024 entry limit, a 64 KiB JSON document limit, and a 15 MiB per image limit. These are application safety limits rather than universal format limits.
