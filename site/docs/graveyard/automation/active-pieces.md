---
sidebar_position: 2
---

# ActivePieces

- Source: https://github.com/activepieces/activepieces
- License: [MIT](https://opensource.org/licenses/MIT) (self-hosted edition)
- Alternatives: n8n, Decree, Zapier, Make
- Status: RIP — closed source licensing practices

## MinIO Trigger

Pre-req: AMQP MinIO queue via RabbitMQ.

1. In ActivePieces, create a new trigger → Catch Webhook
2. Copy the Live URL for use with the RabbitMQ webhook-bridge
3. Set Authentication to Header Auth
   - Header Name: `Authorization`
   - Header Value: create in webhook-bridge `.env`
4. Publish

The built-in RabbitMQ trigger uses AMQP with only 5-minute interval checks. The webhook approach is realtime.

## Gmail Trigger

1. In Gmail, add a filter to automatically label specific emails
2. In ActivePieces, create a new trigger → Gmail → New Email
3. Add label filter
4. Publish

Note: "New Labeled Email" trigger does not work — it only fires when you manually add a label after the email arrives, not with automatic filters.
