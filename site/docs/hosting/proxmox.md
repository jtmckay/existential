---
sidebar_position: 2
---

# Proxmox

- Source: https://github.com/proxmox/pve-manager
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Alternatives: XCP-ng, VMware ESXi, oVirt, Hyper-V

Running the stack in a Proxmox VM works like any Linux host. What differs:

- **GPU passthrough:** add the card as a PCI device with **All Functions** checked and
  **Primary GPU** unchecked. Inside the VM, install the driver and the
  [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html);
  `nvidia-smi` should list the card.
- **CPU type:** if a container fails to start (illegal instruction, or it exits at once with no
  log), set the VM's CPU type to `host`. The default `KVM` hides CPU features some images need.
- **DNS:** don't give the host `127.0.0.1` as its DNS server; use your router's address.
