# RabbitMQ & universal webhook bridge

## RabbitMQ
- Source: https://github.com/rabbitmq/rabbitmq-server
- License: [MPL 2.0](https://www.mozilla.org/MPL/2.0/) / [Apache License 2.0](http://www.apache.org/licenses/LICENSE-2.0)


This service provides RabbitMQ message broker with a universal webhook bridge that can forward queue messages to various webhook endpoints, including HTTP/HTTPS webhooks and ntfy notifications.

## Features

- **RabbitMQ Message Broker**: Full-featured AMQP message broker with SSL/TLS and MQTT support
- **Universal Webhook Bridge**: Forward messages from queues to multiple webhook types
- **Multi-Protocol Support**: HTTP/HTTPS webhooks and ntfy notifications
- **Per-Endpoint Authentication**: Different auth tokens per endpoint
- **Custom Headers**: Add custom headers per endpoint
- **Message Parsing**: Intelligent parsing for different message formats

## Quick Setup

1. Copy `.env.example` to `.env` and update variables
2. Copy `./webhook-bridge/.env.example` to `./webhook-bridge/.env`
3. Configure webhook endpoints in the webhook bridge `.env`
4. Run `docker-compose up -d`

## Webhook Bridge Configuration

The webhook bridge is configured via the `./bridge.config.json` file. See [webhook-bridge README.md](./webhook-bridge/README.md)

## Message Examples

### Send to ntfy
```bash
curl -u rabbitmq:super-secret-password -H "Content-Type: application/json" -X POST \
  http://localhost:5672/api/exchanges/%2F/amq.default/publish -d \
  '{"properties":{},"routing_key":"notifications","payload":"{\"pathSuffix\":\"-test\",\"body\":\"High CPU usage\",\"headers\":{\"title\":\"System Alert\",\"priority\":\"urgent\"}}","payload_encoding":"string"}'
```

### Send to webhook
```bash
curl -u guest:guest -H "Content-Type: application/json" -X POST \
  http://localhost:15672/api/exchanges/%2F/amq.default/publish \
  -d '{"properties":{},"routing_key":"minio","payload":"{\"event\":\"file_uploaded\",\"filename\":\"backup.tar.gz\"}","payload_encoding":"string"}'

```

## Ports & Services

- **AMQP**: 5672 (plain), 5671 (SSL)
- **MQTT**: 1883 (plain), 8883 (SSL)  
- **Management UI**: 15672 (http://192.168.44.191:15672)

## Monitoring

```bash
# View bridge logs
docker logs rabbitmq-webhook-bridge -f

# View RabbitMQ logs  
docker logs rabbitmq -f
```

TODO: look at certs/ssl/etc.
<!-- ### Certificates
#### Configure SANs (subjectAltName)
Update the `./openssl-san.cnf` with your specific configuration.

#### Run this command to generate an ssl cert for RabbitMQ
```
openssl req -x509 -nodes -newkey rsa:4096 \
  -days 3650 \
  -keyout ./ssl/server_key.pem \
  -out  ./ssl/server_cert.pem \
  -config openssl-san.cnf \
  -extensions v3_req
```
#### Combine crt and key into pem by running this:
`
cat ./ssl/server_key.pem ./ssl/server_cert.pem > ./ssl/ca.pem
`
`
#### chmod 644 ./ssl/*.pem
`

#### Create client cert
```
openssl genrsa -out ./ssl/client_key.pem 2048
openssl req -new -key ./ssl/client_key.pem -out ./ssl/client_req.pem

openssl x509 -req -in ./ssl/client_req.pem -CA ./ssl/server_cert.pem \
  -CAkey ./ssl/server_key.pem -CAcreateserial -out ./ssl/client_cert.pem

cat ./ssl/client_cert.pem ./ssl/client_key.pem > ./ssl/client.pem
```

Copy the cert for Home Assistant etc.
`cp ./ssl/server_cert.pem ./ssl/ca.pem` -->


# Third-party licenses & attribution
## RabbitMQ
Copyright (c) 2007-2025 VMware, Inc. or its affiliates.

This product includes software developed at VMware, Inc. and its contributors.
Licensed under the Mozilla Public License, version 2.0.

You may obtain a copy of the License at:
https://www.mozilla.org/MPL/2.0/

Source code:
https://github.com/rabbitmq/rabbitmq-server

## Erlang/OTP
Copyright (c) 1999-2025 Ericsson AB.

Licensed under the Apache License, Version 2.0.

You may obtain a copy of the License at:
http://www.apache.org/licenses/LICENSE-2.0

Source code:
https://github.com/erlang/otp
