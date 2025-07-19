# Unnecessary as of yet (just use GUI workflow solution)
# RabbitMQ
https://github.com/rabbitmq/rabbitmq-server

- Copy `.env.example` to `.env`
- Update env variables
- Create and save secure passwords

## Connect Minio
This can be automated by using `defs.json`
- In RabbitMQ
- Add a user for active pieces
- Go to Queues and Streams
- Add a queue named "minio"
- Click into it, and aa a record "From exchange:" `amq.topic` with "Routing key:" `minio`

## Webhook bridge
Post to a webhook URL for every message received in an AMQP queue.

- Copy `./webhook-bridge/.env.example` to `./webhook-bridge/.env`
- Enter a new queue/webhook pair for each subscription you need. EG in `.env.example`
- Run `docker-compose restart rabbitmq-webhook-bridge` anytime you change `.env` variables.

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
