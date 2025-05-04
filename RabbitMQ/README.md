# RabbitMQ
https://github.com/rabbitmq/rabbitmq-server

Run this command to generate an ssl cert for RabbitMQ
```
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout ./ssl/server_key.pem \
  -out  ./ssl/server_cert.pem \
  -days 3650 \
  -subj "/CN=192.168.44.191"
```

Copy the cert for Home Assistant etc.
`cp ./ssl/server_cert.pem ./ssl/ca.pem`


openssl s_client -connect 192.168.44.191:8883 -CAfile ./ssl/ca.pem -verify_return_error

openssl s_client -connect 192.168.44.191:8883 \
                 -CAfile ./ssl/ca.pem -verify_return_error