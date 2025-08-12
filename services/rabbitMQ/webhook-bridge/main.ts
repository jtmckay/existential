// @deno-types are needed when editing in TypeScript-aware editors
// but the code runs fine in Deno without these declarations
import { parse, connect, delay } from "./deps.ts";
import type { Connection, Channel, ConsumeMessage } from "./deps.ts";

// Add Deno types for TypeScript validation
declare namespace Deno {
  export interface Env {
    toObject(): Record<string, string>;
  }
  export const env: Env;
  export function readTextFile(path: string): Promise<string>;
  export function exit(code: number): never;
  export type Signal = "SIGINT" | "SIGTERM";
  export function addSignalListener(signal: Signal, callback: () => void): void;
}

// Define interface for queue-webhooks
interface QueueWebhook {
  queue: string;
  url: string;
  auth?: string;
  headers?: Record<string, string>;
  format?: 'json' | 'plain';
}

// Define interface for configuration file
interface Config {
  rabbitmq: {
    url: string;
  };
  webhooks: QueueWebhook[];
}

// Load configuration from config.json
let config: Config;
try {
  const configText = await Deno.readTextFile("/app/config.json");
  config = JSON.parse(configText);
} catch (err) {
  console.error(`Failed to read or parse config.json: ${err.message}`);
  Deno.exit(1);
}

// Extract configuration values
const RABBITMQ_URL = config.rabbitmq.url;
const QUEUE_WEBHOOKS = config.webhooks;

// Validate required configuration
if (!RABBITMQ_URL) {
  console.error("rabbitmq.url is required in config.json");
  Deno.exit(1);
}

if (!Array.isArray(QUEUE_WEBHOOKS) || QUEUE_WEBHOOKS.length === 0) {
  console.error("webhooks array is required and must not be empty in config.json");
  Deno.exit(1);
}

// Validate webhook configurations
for (const webhook of QUEUE_WEBHOOKS) {
  if (!webhook.queue || !webhook.url) {
    console.error("Each webhook must have a 'queue' and 'url' property");
    Deno.exit(1);
  }
}

console.log("Starting RabbitMQ webhook bridge...");
console.log(`RabbitMQ URL: ${RABBITMQ_URL}`);
console.log(`Queue-Webhooks: ${QUEUE_WEBHOOKS.length}`);
for (const queueWebhook of QUEUE_WEBHOOKS) {
  console.log(`  - Queue: ${queueWebhook.queue} → Webhook: ${queueWebhook.url}${queueWebhook.auth ? ' (with auth)' : ''}`);
}

/**
 * Connect to RabbitMQ with retry logic
 */
async function connectWithRetry(): Promise<Connection> {
  const MAX_RETRIES = 10;
  const RETRY_DELAY_MS = 5000;
  let retries = 0;

  while (retries < MAX_RETRIES) {
    try {
      console.log(`Connecting to RabbitMQ (attempt ${retries + 1})...`);
      const connection = await connect(RABBITMQ_URL);
      console.log("Successfully connected to RabbitMQ!");
      return connection;
    } catch (error) {
      retries++;
      console.error(`Failed to connect to RabbitMQ: ${error.message}`);
      if (retries >= MAX_RETRIES) {
        console.error("Max retries reached, exiting...");
        throw error;
      }
      console.log(`Retrying in ${RETRY_DELAY_MS / 1000} seconds...`);
      await delay(RETRY_DELAY_MS);
    }
  }
  throw new Error("Failed to connect to RabbitMQ after max retries");
}

/**
 * Send message to webhook endpoint
 */
async function sendToWebhook(messageBody: string, config: QueueWebhook): Promise<boolean> {
  try {
    const url = new URL(config.url);

    if (url.protocol !== 'http:' && url.protocol !== 'https:') {
      console.error(`Unsupported URL scheme: ${url.protocol}. Only http: and https: are supported.`);
      return false;
    }

    return await sendToHttpWebhook(messageBody, config);
  } catch (error) {
    console.error(`Error sending to webhook ${config.url}: ${error.message}`);
    return false;
  }
}

/**
 * Send message to HTTP/HTTPS webhook
 */
async function sendToHttpWebhook(messageBody: string, config: QueueWebhook): Promise<boolean> {
  let url = new URL(config.url);
  const headers: HeadersInit = {
    "Content-Type": "application/json",
  };

  // Use per-endpoint auth only
  if (config.auth) {
    headers["Authorization"] = config.auth;
  }

  // Add custom headers if provided
  if (config.headers) {
    Object.assign(headers, config.headers);
  }

  let body = JSON.stringify({ payload: messageBody });

  // Check if message is JSON with body property
  try {
    const parsed = JSON.parse(messageBody);
    if (typeof parsed === 'object' && parsed !== null && parsed.body !== undefined) {
      // Use the body property as the request body
      body = JSON.stringify(parsed.body);

      // If message has headers property, spread them into the request headers
      if (parsed.headers && typeof parsed.headers === 'object' && parsed.headers !== null) {
        Object.assign(headers, parsed.headers);
      }

      // If message has pathSuffix property, append them onto the URL
      if (parsed.pathSuffix && typeof parsed.pathSuffix === 'string') {
        url.pathname += parsed.pathSuffix;
      }
    }
  } catch {
    // If JSON parsing fails, use the original message format
  }

  const response = await fetch(url.toString(), {
    method: "POST",
    headers,
    body,
  });

  if (!response.ok) {
    const errorText = await response.text();
    console.error(`Webhook request failed with status ${response.status}: ${errorText}`);
    return false;
  }

  if (response.status !== 200) {
    console.log(`Webhook responded with status ${response.status} (non-200 but successful)`);
  } else {
    console.log(`Successfully sent message to webhook ${config.url}`);
  }

  return true;
}

/**
 * Process incoming messages and forward to webhook for a specific queue-webhook
 */
async function processQueueMessages(channel: Channel, config: QueueWebhook): Promise<void> {
  console.log(`Starting to consume messages from queue: ${config.queue}`);

  // Make sure the queue exists
  await channel.assertQueue(config.queue, { durable: true });

  await channel.consume(
    config.queue,
    async (message: ConsumeMessage | null) => {
      if (message === null) {
        console.warn(`Received null message from queue ${config.queue}, consumer cancelled by server?`);
        return;
      }

      const content = message.content.toString();
      console.log(`Received message from ${config.queue}: ${content}`);

      const success = await sendToWebhook(content, config);

      // Always acknowledge the message to prevent requeuing
      // even if webhook fails - we don't want to create an infinite loop of failures
      channel.ack(message);

      if (success) {
        console.log(`Message from ${config.queue} processed successfully`);
      } else {
        console.warn(`Message from ${config.queue} acknowledged despite webhook failure to prevent requeue loops`);
      }
    },
    { noAck: false }
  );

  console.log(`Message consumer for queue ${config.queue} set up successfully!`);
}

/**
 * Process messages for all queue-webhooks
 */
async function processAllQueues(channel: Channel): Promise<void> {
  const processingPromises = QUEUE_WEBHOOKS.map(queueWebhook =>
    processQueueMessages(channel, queueWebhook)
  );

  await Promise.all(processingPromises);
  console.log("All queue consumers set up successfully!");
}

/**
 * Main function
 */
async function main() {
  let connection: Connection | null = null;

  try {
    // Connect to RabbitMQ
    connection = await connectWithRetry();

    // Create channel
    console.log("Creating channel...");
    const channel = await connection.createChannel();
    console.log("Channel created successfully!");

    // Process messages for all queue-webhooks
    await processAllQueues(channel);

    // Keep the process running
    console.log("Webhook bridge is now running and waiting for messages...");

    // Set up a signal handler for graceful shutdown
    const signals = ["SIGINT", "SIGTERM"];
    for (const signal of signals) {
      Deno.addSignalListener(signal as Deno.Signal, () => {
        console.log(`Received ${signal}, closing connection...`);
        if (connection) {
          connection.close();
        }
        Deno.exit(0);
      });
    }

    // Wait indefinitely
    await new Promise(() => { });

  } catch (error) {
    console.error(`Unhandled error: ${error.message}`);
    if (connection) {
      try {
        await connection.close();
      } catch (closeError) {
        console.error(`Error closing connection: ${closeError.message}`);
      }
    }
    Deno.exit(1);
  }
}

// Start the application
main().catch((error) => {
  console.error(`Fatal error: ${error.message}`);
  Deno.exit(1);
});