// Standard library dependencies
export { parse } from "https://deno.land/std@0.214.0/dotenv/mod.ts";
export { delay } from "https://deno.land/std@0.214.0/async/delay.ts";

// RabbitMQ client - using npm:amqplib
export { connect } from "npm:amqplib";

// TypeScript type definitions for amqplib
export type { Connection, Channel, Message, ConsumeMessage } from "npm:@types/amqplib";