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


## VM
I had to up the VM CPU type from `KVM` to `host` in order to fix some errors I saw starting with the MinIO container.
