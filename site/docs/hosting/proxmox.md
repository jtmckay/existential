---
sidebar_position: 2
---

# Proxmox

- Source: https://github.com/proxmox/pve-manager
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Alternatives: XCP-ng, VMware ESXi, oVirt, Hyper-V

## Features

- **KVM Virtualization**: Full virtual machines with hardware-level isolation and PCI passthrough
- **LXC Containers**: Lightweight Linux containers for services that don't need full VMs
- **Web Management Console**: Manage all VMs, containers, and storage from a browser
- **ZFS Storage**: Built-in ZFS with snapshots, clones, and replication for reliable storage
- **Clustering**: Manage multiple Proxmox nodes as a single unified cluster
- **Live Migration**: Move running VMs between hosts with minimal downtime

## Install Notes

- If your clock is wrong, check that you can `ping google.com` before trying anything else.
- Don't use `127.0.0.1` as DNS — use the same IP as your gateway (router).
- Qualified domain name: the first part (subdomain or domain if no sub) will be the machine's name.

## Setup Laptop as Server

### Disable lid-close action

```bash
sudo nano /etc/systemd/logind.conf
# Uncomment HandleLidSwitch and set to: HandleLidSwitch=ignore
```

Options: `ignore`, `lock`, `poweroff`, `hibernate`

## GPU

### Verify card is available

```bash
lspci | grep -i nvidia
# Should return e.g.: 00:10.0 VGA compatible controller: NVIDIA Corporation GA106M [GeForce RTX 3060 Mobile]
```

### Check it's working

```bash
nvidia-smi
```

### Proxmox PCI Passthrough

- Add PCI device
- Select GPU
- Check **All Functions**
- Do **not** check Primary GPU

### Install Drivers (Ubuntu)

```bash
sudo ubuntu-drivers install --gpgpu
sudo add-apt-repository restricted multiverse
sudo apt-get update
sudo apt-get install -y nvidia-driver-XXXXX-open
```

### CUDA

Follow the [NVIDIA CUDA install guide](https://developer.nvidia.com/cuda-downloads?target_os=Linux&target_arch=x86_64&Distribution=Ubuntu&target_version=24.04&target_type=deb_local).

Run `sudo apt --fix-broken install` if needed post-install.

Follow the [NVIDIA Container Toolkit guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) to use GPU in containers.

### Debug: Wipe Drivers

```bash
# 1. Drop to text console
sudo systemctl isolate multi-user.target

# 2. Remove all NVIDIA/CUDA packages
sudo apt-get --purge remove '^nvidia-.*' 'cuda-*' \
  '*cublas*' '*cufft*' '*cufile*' '*curand*' '*cusolver*' \
  '*cusparse*' '*nvjpeg*' 'nsight-*' 'libnvidia-*' 'nvidia-container*'

# 3. Clean up
sudo apt-get autoremove --purge -y && sudo apt-get clean

# 4. Remove repo lists
sudo rm -f /etc/apt/sources.list.d/cuda*.list \
           /etc/apt/sources.list.d/nvidia*.list \
           /usr/share/keyrings/nvidia-*-keyring.gpg \
           /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

# 5. Remove orphaned folders
sudo rm -rf /usr/local/cuda-*

# 6. Reboot
sudo systemctl isolate graphical.target && sudo reboot
```

## CPU

If you see errors starting MinIO, try changing the VM CPU type from `KVM` to `host`.

## Update Main VM

If `apt-get update` fails, comment out lines in `/etc/apt/sources.list.d/`.
