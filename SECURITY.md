# Security Policy

## Supported versions

Only the latest release on the App Store and the `main` branch receive fixes.

## Reporting a vulnerability

Please do not open a public issue for security problems. Instead, use one of these private channels:

- GitHub private vulnerability reporting: [Report a vulnerability](https://github.com/Silvester969/JawAtlas/security/advisories/new)
- Email: jawatlas@icloud.com

Include the affected version, steps to reproduce, and, if possible, a minimal file that triggers the problem. Do not attach real patient data.

You can expect an acknowledgement within 5 days. Fixes are released as soon as practical, and reporters are credited unless they ask not to be.

## Scope

Areas of particular interest:

- DICOM parsing and decompression (malformed or hostile files)
- ZIP import (path traversal, zip bombs)
- Any path by which a patient identifier could reach app storage, exports or shared case files

JawAtlas has no servers, accounts or network code, so server-side issues are out of scope.
