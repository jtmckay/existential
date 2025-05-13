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

// Define interface for queue-webhook pairs
interface QueueWebhookPair {
  queueName: string;
  webhookUrl: string;
}

// Load environment variables
const env = Deno.env.toObject();
try {
  const config = await parse(await Deno.readTextFile(".env"));
  for (const [key, value] of Object.entries(config)) {
    if (!(key in env)) {
      env[key] = String(value);
    }
  }
} catch (err) {
  console.log("No .env file found or error reading it, using only environment variables");
}

// Required configuration
const RABBITMQ_URL = env.RABBITMQ_URL;
const WEBHOOK_AUTH_TOKEN = env.WEBHOOK_AUTH_TOKEN;

// Parse the queue-webhook pairs from environment
const QUEUE_WEBHOOK_PAIRS: QueueWebhookPair[] = [];

// Handle both new format and legacy format for backward compatibility
if (env.QUEUE_WEBHOOK_PAIRS) {
  try {
    // New format: JSON array of pairs
    const pairs = JSON.parse(env.QUEUE_WEBHOOK_PAIRS);
    if (Array.isArray(pairs)) {
      for (const pair of pairs) {
        if (Array.isArray(pair) && pair.length === 2) {
          QUEUE_WEBHOOK_PAIRS.push({
            queueName: pair[0],
            webhookUrl: pair[1]
          });
        }
      }
    }
  } catch (err) {
    console.error(`Failed to parse QUEUE_WEBHOOK_PAIRS: ${err.message}`);
  }
} else if (env.QUEUE_NAME && env.WEBHOOK_URL) {
  // Legacy format: separate variables
  QUEUE_WEBHOOK_PAIRS.push({
    queueName: env.QUEUE_NAME,
    webhookUrl: env.WEBHOOK_URL
  });
}

// Validate required environment variables
if (!RABBITMQ_URL) {
  console.error("RABBITMQ_URL environment variable is required");
  Deno.exit(1);
}

if (QUEUE_WEBHOOK_PAIRS.length === 0) {
  console.error("QUEUE_WEBHOOK_PAIRS environment variable is required or legacy QUEUE_NAME and WEBHOOK_URL");
  Deno.exit(1);
}

console.log("Starting RabbitMQ webhook bridge...");
console.log(`RabbitMQ URL: ${RABBITMQ_URL}`);
console.log(`Queue-Webhook Pairs: ${QUEUE_WEBHOOK_PAIRS.length}`);
for (const pair of QUEUE_WEBHOOK_PAIRS) {
  console.log(`  - Queue: ${pair.queueName} → Webhook: ${pair.webhookUrl}`);
}
console.log(`Auth token: ${WEBHOOK_AUTH_TOKEN ? "configured" : "not configured"}`);

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
async function sendToWebhook(messageBody: string, webhookUrl: string): Promise<boolean> {
  try {
    const headers: HeadersInit = {
      "Content-Type": "application/json",
    };
    
    if (WEBHOOK_AUTH_TOKEN) {
      headers["Authorization"] = WEBHOOK_AUTH_TOKEN;
    }
    
    const response = await fetch(webhookUrl, {
      method: "POST",
      headers,
      body: JSON.stringify({ payload: messageBody }),
    });
    
    if (!response.ok) {
      const errorText = await response.text();
      console.error(`Webhook request failed with status ${response.status}: ${errorText}`);
      return false;
    }
    
    console.log(`Successfully sent message to webhook ${webhookUrl}`);
    return true;
  } catch (error) {
    console.error(`Error sending to webhook ${webhookUrl}: ${error.message}`);
    return false;
  }
}

/**
 * Process incoming messages and forward to webhook for a specific queue-webhook pair
 */
async function processQueueMessages(channel: Channel, queueName: string, webhookUrl: string): Promise<void> {
  console.log(`Starting to consume messages from queue: ${queueName}`);
  
  // Make sure the queue exists
  await channel.assertQueue(queueName, { durable: true });
  
  await channel.consume(
    queueName,
    async (message: ConsumeMessage | null) => {
      if (message === null) {
        console.warn(`Received null message from queue ${queueName}, consumer cancelled by server?`);
        return;
      }
      
      const content = message.content.toString();
      console.log(`Received message from ${queueName}: ${content}`);
      
      const success = await sendToWebhook(content, webhookUrl);
      
      // Always acknowledge the message to prevent requeuing
      // even if webhook fails - we don't want to create an infinite loop of failures
      channel.ack(message);
      
      if (success) {
        console.log(`Message from ${queueName} processed successfully`);
      } else {
        console.warn(`Message from ${queueName} acknowledged despite webhook failure to prevent requeue loops`);
      }
    },
    { noAck: false }
  );
  
  console.log(`Message consumer for queue ${queueName} set up successfully!`);
}

/**
 * Process messages for all queue-webhook pairs
 */
async function processAllQueues(channel: Channel): Promise<void> {
  const processingPromises = QUEUE_WEBHOOK_PAIRS.map(pair => 
    processQueueMessages(channel, pair.queueName, pair.webhookUrl)
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
    
    // Process messages for all queue-webhook pairs
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
    await new Promise(() => {});
    
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