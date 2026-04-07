// Use this whenever triggering on an MQTT event to decode the payload
// and return a consistent object structure to the main function.
// Example usage in consume_gmail_queue.ts:
//
// 0. Pre-req: add an MQTT resource in Windmill (e.g., "mqtt_resource")
// 1. Create a new flow in Windmill
// 2. Add this as a "Preprocessor Script" step (name it e.g., "preprocessor_mqtt")
// 3. Set the main INPUT to the output of this preprocessor step:
//    - topic: string
//    - message: object
//    - contentType: string
// 4. NOT IN THE FLOW EDITOR: go to MQTT resource settings and add a new trigger
//    ONLY for a FLOW with the desired topic (e.g., "gmail/emails")

export async function preprocessor(event: {
  kind: string;
  payload: string;
  topic: string;
  v5?: any;
}) {
  if (event.kind !== "mqtt") {
    throw new Error(`Unexpected trigger type: ${event.kind}`);
  }
  const payloadAsString = atob(event.payload);
  let message = payloadAsString;
  try {
    const payloadAsJson = JSON.parse(payloadAsString);
    message = payloadAsJson;
  } catch (err) {
    return;
  }
  return {
    topic: event.topic,
    message,
    contentType: event.v5?.content_type,
  };
}
