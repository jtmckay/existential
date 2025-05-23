# Active Pieces
https://github.com/activepieces/activepieces

### MinIO trigger
Pre-req: [AMQP MinIO queue](../RabbitMQ/README.md#connect-minio)
- In Active Pieces
- Create a new trigger
- Select Catch Webhook
- Copy the Live URL for use with the [RabbitMQ webhook-bridge](../RabbitMQ/README.md)
- Set Authentication (in active pieces) to Header Auth
- Header Name: `Authorization`
- Header Value: Create in webhook-bridge `.env` and copy here
- Publish

The built-in RabbitMQ trigger uses AMQP, and only allows for 5 minute interval checks. The webhook is realtime.

### Gmail trigger
- In Gmail add filter to automatically label specific emails
- In Active Pieces
- Create a new trigger
- Select (Gmail) New Email
- Add label filter
- Publish

Using "New Labeled Email" trigger does not work. It is only fired when you add a label to an email after it has arrived in your inbox (not with an automatic filter).
