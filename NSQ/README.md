# [NSQ](https://nsq.io/)
Queue service

### Why?
This will allow us to respond to events in a distributed way. Publishers, like MinIO, don't need to know about anything else, so we can create N number of subscribers that respond to file events without changing MinIO (or NSQ) at all.
