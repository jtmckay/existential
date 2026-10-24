# ntfy alerts

Alerts go to the topic `exist-alerts`. To test from a shell:

```bash
curl -d "backup failed on nas" https://ntfy.example.ts.net:8443/exist-alerts
```

The phone app subscribes with the username from `.env.shared` (`EXIST_USERNAME`).
