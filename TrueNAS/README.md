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
- Add host (the proxmox static IP address, otherwise anyone on the LAN can access)
- Save
- Turn on NFS automatically

### Mount in proxmox
- Make dir on proxmox server `sudo mkdir -p /mnt/minio-data`
- Mount NFS share `sudo mount -t nfs <TrueNAS_IP>:/path/to/dataset /mnt/minio_data`
	- Make sure to give the TrueNAS server a static IP
	- /path/to/dataset is the path listed under UNIX (NFS) Shares in TrueNAS gui
