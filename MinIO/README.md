# MinIO
Why use MinIO? It might be overkill, but maybe not.

#### Benefits of having an S3 interface
- Provides an interface to all files, that if replaced with something like Amazon S3 would replace the need for TrueNAS
- Hooks for automations. Has native integration with NSQ.

## Connect to Nextcloud
### Go to http://docker_host_ip:9001/login
### Create access key
#### Name: Nextcloud
### Save Access Key and Secret Key for use with Nextclout
### After connecting Nextcloud (which will create the bucket in MinIO)
#### In MinIO go to Buckets -> nextclout (whatever your bucket is named)

## Trigger n8n
#### Click on Events -> Subscribe to Event
##### ARN dropdown should have an n8n option (which comes from the .env through docker-compose)
##### Prefix: Input
##### Check PUT
##### Hit Save
This will subscribe to all PUT events for the Input directory, and POST to the n8n endpoint with the file metadata.

## Trigger n8n
#### Click on Events -> Subscribe to Event
##### ARN dropdown should have an n8n option (which comes from the .env through docker-compose)
##### Prefix: Input
##### Check PUT
##### Hit Save
This will subscribe to all PUT events for the Input directory, and POST to the n8n endpoint with the file metadata.
