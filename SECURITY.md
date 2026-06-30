# Security Policy

Veil crosses the macOS host, a Windows guest, clipboard data, file sharing, and input injection. Security issues are expected to be subtle.

## Supported Versions

No released version is supported yet. The project is pre-alpha.

## Reporting a Vulnerability

Until a private disclosure channel is published, do not file public proof-of-concept exploits that expose user data. Contact the repository owner privately first.

## Security Boundaries

The intended trust model:

- The macOS host app is trusted by the local user.
- The Windows guest is treated as less trusted than the host.
- The guest agent is trusted only after explicit installation by the user.
- Clipboard and file bridge features must be opt-in or clearly visible.
- Host paths exposed to the guest must be narrow and user-controlled.

## High-Risk Areas

- Guest-to-host protocol parsing.
- Shared folder path mapping.
- Clipboard sync loops and hidden data types.
- Input injection and focus confusion.
- Window capture of sensitive guest content.
- Auto-start behavior.

Security-sensitive changes should include threat-model notes in the PR.
