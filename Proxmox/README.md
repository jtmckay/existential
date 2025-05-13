# Proxmox
https://www.proxmox.com/en/downloads/proxmox-virtual-environment/documentation/proxmox-ve-admin-guide-for-7-x

### Notes on install
- If your clock is wrong, check that you can `ping google.com` or resolve anything from the internet before trying anything else.
- Don't use 127.0.0.1 as DNS, use the same IP as your gateway (router).
- Qualified domain name: the first part (subdomain or domain if no sub) will be the machine's name.

## Setup laptop
### Disable closing the lid action
https://ubuntuhandbook.org/index.php/2020/05/lid-close-behavior-ubuntu-20-04/
`sudo nano /etc/systemd/logind.conf`

uncomment HandleLidSwitch
Set to "ignore" **HandleLidSwitch=ignore**
Options: ignore, lock, poweroff, hibernate

## GPU
Verify graphics card is available: `lspci | grep -i nvidia`
Should return something like `00:10.0 VGA compatible controller: NVIDIA Corporation GA106M [GeForce RTX 3060 Mobile / Max-Q] (rev a1)`

Check if it's all working: `nvidia-smi`

### Debug: wipe drivers
1) Drop to a text console so nothing is using the driver
`sudo systemctl isolate multi-user.target`

2) Remove all Debian packages that start with nvidia-*, cuda-* or related libs/tooling
```
sudo apt-get --purge remove '^nvidia-.*' 'cuda-*' \
  '*cublas*' '*cufft*' '*cufile*' '*curand*' '*cusolver*' \
  '*cusparse*' '*nvjpeg*' 'nsight-*' 'libnvidia-*' 'nvidia-container*'
```

3) Clean up anything left over
```
sudo apt-get autoremove --purge -y
sudo apt-get clean
```

4) Delete any previous NVIDIA/CUDA repo lists & keys (safe if they don’t exist)
```
sudo rm -f /etc/apt/sources.list.d/cuda*.list \
           /etc/apt/sources.list.d/nvidia*.list \
           /usr/share/keyrings/nvidia-*-keyring.gpg \
           /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
```

5) Remove orphaned driver/toolkit folders that were placed outside the package manager
`sudo rm -rf /usr/local/cuda-*`

6) Re-enable the graphical target and reboot to start fresh
```
sudo systemctl isolate graphical.target
sudo reboot
```

### Install drivers
`sudo ubuntu-drivers install --gpgpu`

```
sudo add-apt-repository restricted multiverse  # in case they’re not enabled
sudo apt-get update

# list the open-kernel driver options Ubuntu has tested
apt-cache search '^nvidia-driver-.*-open$'
```

#### Install whichever version is recommended for your GPU, e.g.
`sudo apt-get install -y nvidia-driver-XXXXX-open   # or 535-open, 560-open …`

### Using Proxmox
- Add PCI device
- Select GPU
- Check All Functions
- Do not check Primary GPU

### Docker
`sudo ubuntu-drivers install --gpgpu`


Install using https://docs.docker.com/engine/install/ubuntu/
(NOT SNAP)

### CUDA
https://developer.nvidia.com/cuda-downloads?target_os=Linux&target_arch=x86_64&Distribution=Ubuntu&target_version=24.04&target_type=deb_local

I had to run `sudo apt --fix-broken install` post CUDA Toolkit Install



Follow the NVIDIA Container Toolkit guide if you want to use an NVIDIA GPU
https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html

## CPU
I had to up the VM CPU type from `KVM` to `host` in order to fix some errors I saw starting with the MinIO container.

## Update main VM
If you can't run `apt-get update` comment out (add `#` at the beginning of the lines) for the files in: `/etc/apt/sources.list.d`
