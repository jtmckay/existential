# Ngrok
https://ngrok.com/docs/what-is-ngrok/

Punches a whole to the internet, allowing you to access a specific port on your machine from anywhere on the internet, without setting up port forwarding on your router.

### Run
`ngrok http 80`

#### Generate the run command using env variables
`source .env && echo "ngrok http --url=$NGROK_URL $N8N_PORT"`
