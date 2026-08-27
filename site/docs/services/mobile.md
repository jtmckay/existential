---
sidebar_position: 3
---

# On your phone

Three of the services here ship Android apps, so the parts of the stack you reach for most
come with you. None of this is deployed by Existential — they're clients you install.

| App | What it gives you |
|---|---|
| [Home Assistant](./homeassistant) | House controls and automations, plus presence detection from the phone itself |
| [Obsidian](./obsidian) | The vault, editable offline; changes reconcile when the folder next syncs |
| [Nextcloud](../storage/nextcloud) | Files on demand, and automatic camera-roll upload |

## Camera roll

The Nextcloud app's auto-upload is the simplest way to get photos off the phone and onto your
own disks. Point it at the directory [Immich](./immich) watches and new photos land in the
library without a manual import step.

## Keeping the vault in step

Nextcloud syncs the vault directory, and Obsidian opens it in place — on most devices that is
all you need.

Android's scoped storage can get in the way: depending on the version and where the Nextcloud
app keeps its local copy, Obsidian may not be able to open that directory directly. Where that
happens, [FolderSync](https://foldersync.io/) mirrors the two folders on a schedule and
Obsidian points at the local copy instead.

Obsidian also offers its own first-party sync service, which handles this case (and end-to-end
encryption) without the extra moving part. Either approach works; see
[Obsidian](./obsidian#sync-to-your-phone) for the setup steps.
