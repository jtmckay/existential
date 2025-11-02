# Windmill Script Conventions

This document defines the standard patterns and practices for Windmill scripts in this project.

## Directory Structure
All Windmill scripts must be placed in: `services/windmill/scripts/`

## Runtime
- **Always use Bun.js runtime** for TypeScript/JavaScript scripts
- Declare runtime in script comments: `// Runtime: Bun`

## Security and Sensitive Data

**NEVER hardcode user-specific or sensitive information in scripts.**

Always use:
- **Windmill Resources** for credentials and tokens (e.g., Gmail, GitHub, API keys)
- **Windmill Variables** for user-specific configuration (e.g., usernames, paths, URLs)
- **Script Parameters** with sensible defaults that can be overridden

### Examples:

❌ **Bad - Hardcoded values:**
```typescript
export async function main() {
  const apiKey = 'sk-1234567890abcdef';  // NEVER do this
  const username = 'john.doe';           // NEVER do this
  const email = 'user@example.com';      // NEVER do this
}
```

✅ **Good - Use resources and variables:**
```typescript
import * as wmill from 'windmill-client';

type ApiResource = { api_key: string };

export async function main(
  api_resource: ApiResource,                    // Windmill resource
  username_var: string = 'u/admin/username',    // Variable path
  rabbitmq_url: string = 'amqp://localhost'     // Configurable default
) {
  const username = await wmill.getVariable(username_var);
  const apiKey = api_resource.api_key;
}
```

## Variable Management

### Reading Variables
When **only reading** Windmill variables, use them directly as input parameters:
```typescript
export async function main(
  my_variable: string,  // Direct parameter
  another_var: number
) {
  // Use variables directly
}
```

### Reading and Updating Variables
When **both reading and updating** variables, take the variable name/path as a parameter and use the `windmill-client` package:

```typescript
import * as wmill from 'windmill-client';

export async function main(
  last_timestamp_key: string = 'u/username/my_timestamp'
) {
  // Read
  const value = await wmill.getVariable(last_timestamp_key) as string;
  
  // Update
  await wmill.setVariable(last_timestamp_key, newValue.toString());
}
```

## Workflow Decoupling with RabbitMQ

**Always use RabbitMQ to decouple workflows** when processing data that needs to be consumed by other services or workflows.

### Standard Pattern:
1. **Producer script** fetches/generates data and publishes to RabbitMQ queue (via AMQP)
2. **Consumer script(s)** consume messages via MQTT triggers (event-driven)
3. Use persistent messages for reliability
4. Implement proper error handling and connection cleanup

### Consumer Pattern: MQTT Triggers (PREFERRED)

**Always prefer MQTT triggers over active polling** for consuming RabbitMQ messages.

#### Producer → Consumer Flow:
```
Producer (AMQP) → RabbitMQ Queue → MQTT Plugin → MQTT Topic → Windmill Flow (MQTT trigger)
```

Benefits:
- Event-driven (no wasted polling cycles)
- Automatic message delivery via RabbitMQ MQTT plugin
- Built-in backpressure handling
- Simpler code (no connection management)
- RabbitMQ MQTT plugin enabled on port 1883

#### Producer Pattern (AMQP):
```typescript
// Producers publish to AMQP queues using amqplib
import * as amqp from 'amqplib';

const connection = await amqp.connect(rabbitmq_url);
const channel = await connection.createChannel();
await channel.assertQueue('my_queue', { durable: true });

// Publish with persistent messages
const message = JSON.stringify(data);
channel.sendToQueue('my_queue', Buffer.from(message), { persistent: true });
```

#### Consumer Pattern (MQTT):
```typescript
// Consumers use MQTT triggers in Windmill flows
// WINDMILL FLOW CONFIGURATION:
// 1. Set trigger type to "MQTT"
// 2. Configure MQTT: host (rabbitmq:1883), topic ("my_queue"), credentials
// 3. Set Preprocessor: Reference "preprocessor_mqtt.ts" (shared)
// 4. Add this script as first step

// Main function receives preprocessor output: { topic, message, contentType }
export async function main(
  topic: string,
  message: any,  // Your parsed data type
  contentType?: string
) {
  // Process the message
  console.log(`Processing message from ${topic}:`, message);
  return message;
}
```

**Note**: The shared `preprocessor_mqtt.ts` handles MQTT event parsing. Always reference it instead of duplicating preprocessor logic.

### Preprocessor Pattern

**Use preprocessors ONLY for webhook/event-triggered flows** (e.g., MQTT, HTTP webhooks).

**DO NOT use preprocessors for active polling scripts** (e.g., scripts that manually fetch from RabbitMQ queues, APIs, etc.).

#### When to Use Preprocessors:
- Flow is triggered by an external event (webhook, MQTT message, etc.)
- Need to validate the trigger type
- Need to decode/transform the incoming payload
- Event data needs parsing (base64, JSON, etc.)

#### Shared MQTT Preprocessor:

**Always reference `preprocessor_mqtt.ts`** instead of creating inline preprocessors.

Location: `services/windmill/scripts/preprocessor_mqtt.ts`

Returns:
```typescript
{
  topic: string;      // The MQTT topic
  message: any;       // Parsed JSON or raw string
  contentType?: string; // MQTT v5 content type if available
}
```

Usage in your scripts:
```typescript
// In Windmill flow configuration:
// 1. Set Preprocessor to reference: preprocessor_mqtt.ts
// 2. Your main function receives the preprocessed data:

export async function main(
  topic: string,
  message: YourDataType,
  contentType?: string
) {
  // message is already parsed from MQTT payload
  console.log(`Received from ${topic}:`, message);
}
```

#### Active Polling Pattern (No Preprocessor):
```typescript
// For scripts that actively poll queues/APIs
// WINDMILL FLOW CONFIGURATION:
// 1. Create a new flow
// 2. Add this script as the first step
// 3. Enable "Early Stop/Break if predicate met" with: result == null
// 4. Enable "While loop" to continuously process
// 5. Add processing logic in subsequent steps

export async function main(): Promise<DataType | null> {
  // Fetch one item from queue/API
  const item = await fetchOneItem();
  
  // Return null when no more items (stops flow loop)
  if (!item) return null;
  
  return item;  // Flow continues with this data
}
```

### Example Producer Pattern:
```typescript
import * as amqp from 'amqplib';

export async function main(
  rabbitmq_url: string = 'amqp://localhost',
  queue_name: string = 'my_queue'
) {
  let connection: amqp.Connection | null = null;
  let channel: amqp.Channel | null = null;
  
  try {
    connection = await amqp.connect(rabbitmq_url);
    channel = await connection.createChannel();
    await channel.assertQueue(queue_name, { durable: true });
    
    // Publish messages
    const message = JSON.stringify(data);
    const sent = channel.sendToQueue(queue_name, Buffer.from(message), { 
      persistent: true 
    });
    
    if (!sent) {
      await new Promise(resolve => channel.once('drain', resolve));
      channel.sendToQueue(queue_name, Buffer.from(message), { persistent: true });
    }
    
  } finally {
    if (channel) await channel.close();
    if (connection) await connection.close();
  }
}
```

## Common Dependencies
- `windmill-client` - For variable management
- `amqplib` - For RabbitMQ integration
- Service-specific packages as needed (e.g., `googleapis`, `@octokit/rest`)

## Script Structure Template

```typescript
// Windmill Bun/TypeScript script: [Brief description]
// Dependencies: [list packages]
// Parameters:
//   - param_name (type: description)
//   - another_param (type: description, default: value)

import * as wmill from 'windmill-client';
import * as amqp from 'amqplib';

type ResourceType = { /* resource shape */ };

export async function main(
  resource: ResourceType,
  variable_key: string = 'u/username/var_name',
  rabbitmq_url: string = 'amqp://localhost',
  queue_name: string = 'queue_name'
): Promise<string> {
  let connection: amqp.Connection | null = null;
  let channel: amqp.Channel | null = null;
  
  try {
    // 1. Setup connections
    // 2. Read variables if needed
    // 3. Process data
    // 4. Publish to RabbitMQ
    // 5. Update variables if needed
    
    return JSON.stringify({ success: true, /* results */ });
  } catch (error) {
    console.error('Error:', error);
    return JSON.stringify({ success: false, error: error.message });
  } finally {
    // Cleanup connections
    try {
      if (channel) await channel.close();
      if (connection) await connection.close();
    } catch (cleanupError) {
      console.warn('Cleanup error:', cleanupError);
    }
  }
}
```

## Long-Running Scripts Pattern

For scripts that need to run close to the 10-minute timeout:
- Target ~9 minutes 55 seconds (595 seconds) max runtime
- Implement polling loops with regular intervals
- Save progress incrementally (update variables after each batch)
- Track processed items to avoid duplicates
- Provide detailed logging for each cycle

## Error Handling
- Always wrap main logic in try-catch
- Return structured JSON responses with success/error status
- Log errors with context
- Clean up resources in finally blocks
- Handle partial failures gracefully (process what you can)

## Return Values
Return JSON stringified objects with consistent structure:
```typescript
// Success
return JSON.stringify({
  success: true,
  processed: count,
  // ... other relevant metrics
});

// Error
return JSON.stringify({
  success: false,
  error: error.message,
  processed: partialCount  // What was completed before error
});
```
