# TrueNAS
File storage
- RAID
- Scrubbing

## VM on Proxmox
- I am attempting this setup with 2 external 20TB USB drives.
- Added to the Proxmox VM through 2 USB ports (added hardware)

### Load the image into Proxmox
- Download the iso from TrueNAS.
- Open the proxmox console.
- Under the main server EG `m6`
- There should be a drive EG `local` 
- Click on ISO Images
- Upload

Then you can create a VM using the TrueNAS ISO

### Create a pool
Select all the drives you want. I did mirror, for full redundancy.

### Turn on NFS Share & Create dataset
- Load the TrueNAS UI
- Shares (on the left)
- Add a UNIX (NFS)
- Create dataset
- Add host (the docker host VM static IP address, otherwise anyone on the LAN can access)
- Expand the advanced options
- Set Maproot User to `root`
- Set Maproot Group to `root`
- Save
- Turn on NFS automatically

#### Configure dataset
- It likely changes with usecase, and hardware setups, but:
- Set compression level: `Inherit (ZSTD-FAST-10)`

#### Configure Data Protection
- Adjust a Scrub Task
  - Threshold days: 35 (will only attempt again after 35 days have lapsed since the last run)
  - Schedule: `(0 4 15 * *)`
- Periodic S.M.A.R.T. Tests
  - Add SHORT `(0 0 * * *)`
  - Add LONG `(0 1 1 * *)`

### Mount on docker host
In order for the docker host/containers to write to the TrueNAS share, you MUST update the access. Ensure Maproot User, and Maproot group are set to root.

#### Helpful manual mount to explore TrueNAS data
`sudo mount -t nfs -o rw,nolock 192.168.1.10:/path/in/nas /mnt/test`
