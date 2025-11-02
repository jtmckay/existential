// runtime: Bun (TypeScript)
import { connect } from "mqtt"; // Named import for direct access to connect()

type Mqtt = {
  broker: string;
  port: number;
  credentials?: {
    username?: string;
    password?: string;
  };
  // Add other fields like tls config if needed in your resource
};

type Priority = "min" | "low" | "default" | "high" | "max";

export async function main(
  message: string,
  title = "",
  queueSuffix?: string,
  priority: Priority = "default",
  mqtt: Mqtt // Pass your MQTT resource here (e.g., $res:u/username/rabbitmq_mqtt)
) {
  const queue = "notifications";
  const pathSuffix = queueSuffix ? `-${queueSuffix}` : undefined;

  // Build MQTT URL from resource
  let authPart = "";
  if (mqtt.credentials?.username && mqtt.credentials?.password) {
    authPart = `${encodeURIComponent(
      mqtt.credentials.username
    )}:${encodeURIComponent(mqtt.credentials.password)}@`;
  }
  const mqttUrl = `mqtt://${authPart}${mqtt.broker}:${mqtt.port}`;

  const client = connect(mqttUrl); // Use the imported connect directly

  try {
    // Wait for connection
    await new Promise<void>((resolve, reject) => {
      client.on("connect", () => resolve());
      client.on("error", reject);
    });

    const payloadObj = {
      body: message,
      headers: { title, priority },
      pathSuffix,
    };
    const topic = queue; // Publish to topic matching the queue name for direct routing

    // Publish with QoS 1 for at-least-once delivery (mimics persistent: true)
    const ok = await new Promise<boolean>((resolve) => {
      client.publish(
        topic,
        JSON.stringify(payloadObj),
        { qos: 1, retain: false },
        (err) => {
          resolve(err ? false : true);
        }
      );
    });

    return { ok, queue };
  } finally {
    // Always close the client
    client.end();
  }
}
