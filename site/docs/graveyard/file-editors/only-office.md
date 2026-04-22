---
sidebar_position: 4
---

# OnlyOffice

- Source: https://github.com/ONLYOFFICE/DocumentServer
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Alternatives: Collabora, LibreOffice Online, Microsoft Office 365
- Status: RIP

Document editing suite — integrated with Nextcloud.

## Features

- **Full Office Suite**: Browser-based editing for documents, spreadsheets, and presentations
- **Real-Time Collaboration**: Multiple users edit simultaneously with track changes and comments
- **Format Compatibility**: Opens and saves .docx, .xlsx, .pptx, and ODF files
- **Nextcloud Integration**: Embeds as the default editor in Nextcloud Files via the official app
- **Plugin System**: Extend editor functionality with macros and custom plugins
- **JWT Security**: Token-based authentication for secure API communication

## Requirements

Requires HTTPS. Use a secure reverse proxy (e.g., Caddy).

## Setup with Nextcloud

1. Follow the [Nextcloud integration guide](https://helpcenter.onlyoffice.com/integration/nextcloud.aspx)
2. Install the OnlyOffice app in Nextcloud
3. Check the boxes for file types you want to open with OnlyOffice
