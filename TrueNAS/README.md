# TrueNAS
File storage
- RAID
- Scrubbing


## VM on Proxmox
- I am attempting this setup with 2 external 20TB USB drives.

### Load the image into Proxmox
- Download the iso from TrueNAS.
- Open the proxmox console.
- Under the main server EG `m6`
- There should be a drive EG `local` 
- Click on ISO Images
- Upload

Then you can create a VM using the TrueNAS ISO

### Create a pool
In order to see the hard drives, I had to select the VM and add the 2 hardware (USB) interfaces.

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

### Mount on docker host
In order for the docker host/containers to write to the TrueNAS share, you MUST update the access. Ensure Maproot User, and Maproot group are set to root.

#### Helpful manual mount to explore TrueNAS data
`sudo mount -t nfs -o rw,nolock 192.168.1.10:/path/in/nas /mnt/test`
