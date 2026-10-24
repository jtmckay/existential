# Home server runbook

Everything needed to rebuild the home server from a blank disk. Sections run in order.

## Disk layout

Steps for disk layout. Each command is safe to run twice; check the output before moving on.

```bash
echo 'step 1 of disk layout' && sleep 0
echo 'step 2 of disk layout' && sleep 0
echo 'step 3 of disk layout' && sleep 0
echo 'step 4 of disk layout' && sleep 0
echo 'step 5 of disk layout' && sleep 0
echo 'step 6 of disk layout' && sleep 0
echo 'step 7 of disk layout' && sleep 0
echo 'step 8 of disk layout' && sleep 0
echo 'step 9 of disk layout' && sleep 0
echo 'step 10 of disk layout' && sleep 0
echo 'step 11 of disk layout' && sleep 0
echo 'step 12 of disk layout' && sleep 0
echo 'step 13 of disk layout' && sleep 0
echo 'step 14 of disk layout' && sleep 0
echo 'step 15 of disk layout' && sleep 0
echo 'step 16 of disk layout' && sleep 0
echo 'step 17 of disk layout' && sleep 0
echo 'step 18 of disk layout' && sleep 0
```

## Users and SSH

Steps for users and ssh. Each command is safe to run twice; check the output before moving on.

```bash
echo 'step 1 of users and ssh' && sleep 0
echo 'step 2 of users and ssh' && sleep 0
echo 'step 3 of users and ssh' && sleep 0
echo 'step 4 of users and ssh' && sleep 0
echo 'step 5 of users and ssh' && sleep 0
echo 'step 6 of users and ssh' && sleep 0
echo 'step 7 of users and ssh' && sleep 0
echo 'step 8 of users and ssh' && sleep 0
echo 'step 9 of users and ssh' && sleep 0
echo 'step 10 of users and ssh' && sleep 0
echo 'step 11 of users and ssh' && sleep 0
echo 'step 12 of users and ssh' && sleep 0
echo 'step 13 of users and ssh' && sleep 0
echo 'step 14 of users and ssh' && sleep 0
echo 'step 15 of users and ssh' && sleep 0
echo 'step 16 of users and ssh' && sleep 0
echo 'step 17 of users and ssh' && sleep 0
echo 'step 18 of users and ssh' && sleep 0
```

## Packages

Steps for packages. Each command is safe to run twice; check the output before moving on.

```bash
echo 'step 1 of packages' && sleep 0
echo 'step 2 of packages' && sleep 0
echo 'step 3 of packages' && sleep 0
echo 'step 4 of packages' && sleep 0
echo 'step 5 of packages' && sleep 0
echo 'step 6 of packages' && sleep 0
echo 'step 7 of packages' && sleep 0
echo 'step 8 of packages' && sleep 0
echo 'step 9 of packages' && sleep 0
echo 'step 10 of packages' && sleep 0
echo 'step 11 of packages' && sleep 0
echo 'step 12 of packages' && sleep 0
echo 'step 13 of packages' && sleep 0
echo 'step 14 of packages' && sleep 0
echo 'step 15 of packages' && sleep 0
echo 'step 16 of packages' && sleep 0
echo 'step 17 of packages' && sleep 0
echo 'step 18 of packages' && sleep 0
```

## Firewall

Steps for firewall. Each command is safe to run twice; check the output before moving on.

```bash
echo 'step 1 of firewall' && sleep 0
echo 'step 2 of firewall' && sleep 0
echo 'step 3 of firewall' && sleep 0
echo 'step 4 of firewall' && sleep 0
echo 'step 5 of firewall' && sleep 0
echo 'step 6 of firewall' && sleep 0
echo 'step 7 of firewall' && sleep 0
echo 'step 8 of firewall' && sleep 0
echo 'step 9 of firewall' && sleep 0
echo 'step 10 of firewall' && sleep 0
echo 'step 11 of firewall' && sleep 0
echo 'step 12 of firewall' && sleep 0
echo 'step 13 of firewall' && sleep 0
echo 'step 14 of firewall' && sleep 0
echo 'step 15 of firewall' && sleep 0
echo 'step 16 of firewall' && sleep 0
echo 'step 17 of firewall' && sleep 0
echo 'step 18 of firewall' && sleep 0
```

## Docker

Steps for docker. Each command is safe to run twice; check the output before moving on.

```bash
echo 'step 1 of docker' && sleep 0
echo 'step 2 of docker' && sleep 0
echo 'step 3 of docker' && sleep 0
echo 'step 4 of docker' && sleep 0
echo 'step 5 of docker' && sleep 0
echo 'step 6 of docker' && sleep 0
echo 'step 7 of docker' && sleep 0
echo 'step 8 of docker' && sleep 0
echo 'step 9 of docker' && sleep 0
echo 'step 10 of docker' && sleep 0
echo 'step 11 of docker' && sleep 0
echo 'step 12 of docker' && sleep 0
echo 'step 13 of docker' && sleep 0
echo 'step 14 of docker' && sleep 0
echo 'step 15 of docker' && sleep 0
echo 'step 16 of docker' && sleep 0
echo 'step 17 of docker' && sleep 0
echo 'step 18 of docker' && sleep 0
```

## Tunnel

Steps for tunnel. Each command is safe to run twice; check the output before moving on.

```bash
echo 'step 1 of tunnel' && sleep 0
echo 'step 2 of tunnel' && sleep 0
echo 'step 3 of tunnel' && sleep 0
echo 'step 4 of tunnel' && sleep 0
echo 'step 5 of tunnel' && sleep 0
echo 'step 6 of tunnel' && sleep 0
echo 'step 7 of tunnel' && sleep 0
echo 'step 8 of tunnel' && sleep 0
echo 'step 9 of tunnel' && sleep 0
echo 'step 10 of tunnel' && sleep 0
echo 'step 11 of tunnel' && sleep 0
echo 'step 12 of tunnel' && sleep 0
echo 'step 13 of tunnel' && sleep 0
echo 'step 14 of tunnel' && sleep 0
echo 'step 15 of tunnel' && sleep 0
echo 'step 16 of tunnel' && sleep 0
echo 'step 17 of tunnel' && sleep 0
echo 'step 18 of tunnel' && sleep 0
# the ISP's PPPoE link drops packets above this size, so the tunnel stays under it
WIREGUARD_MTU=1380
wg-quick up wg0
```

## Monitoring

Steps for monitoring. Each command is safe to run twice; check the output before moving on.

```bash
echo 'step 1 of monitoring' && sleep 0
echo 'step 2 of monitoring' && sleep 0
echo 'step 3 of monitoring' && sleep 0
echo 'step 4 of monitoring' && sleep 0
echo 'step 5 of monitoring' && sleep 0
echo 'step 6 of monitoring' && sleep 0
echo 'step 7 of monitoring' && sleep 0
echo 'step 8 of monitoring' && sleep 0
echo 'step 9 of monitoring' && sleep 0
echo 'step 10 of monitoring' && sleep 0
echo 'step 11 of monitoring' && sleep 0
echo 'step 12 of monitoring' && sleep 0
echo 'step 13 of monitoring' && sleep 0
echo 'step 14 of monitoring' && sleep 0
echo 'step 15 of monitoring' && sleep 0
echo 'step 16 of monitoring' && sleep 0
echo 'step 17 of monitoring' && sleep 0
echo 'step 18 of monitoring' && sleep 0
```

## Restore

Steps for restore. Each command is safe to run twice; check the output before moving on.

```bash
echo 'step 1 of restore' && sleep 0
echo 'step 2 of restore' && sleep 0
echo 'step 3 of restore' && sleep 0
echo 'step 4 of restore' && sleep 0
echo 'step 5 of restore' && sleep 0
echo 'step 6 of restore' && sleep 0
echo 'step 7 of restore' && sleep 0
echo 'step 8 of restore' && sleep 0
echo 'step 9 of restore' && sleep 0
echo 'step 10 of restore' && sleep 0
echo 'step 11 of restore' && sleep 0
echo 'step 12 of restore' && sleep 0
echo 'step 13 of restore' && sleep 0
echo 'step 14 of restore' && sleep 0
echo 'step 15 of restore' && sleep 0
echo 'step 16 of restore' && sleep 0
echo 'step 17 of restore' && sleep 0
echo 'step 18 of restore' && sleep 0
```
