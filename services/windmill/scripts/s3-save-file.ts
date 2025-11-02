import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { getResource } from "windmill-client";

type WindmillS3 = {
  accessKey?: string;
  secretKey?: string;
  region?: string;
  endPoint?: string;
  useSSL?: boolean;
  pathStyle?: boolean;
  port: number;
};

function normalizeS3(res: WindmillS3) {
  const accessKeyId = res.accessKey;
  const secretAccessKey = res.secretKey;
  if (!accessKeyId || !secretAccessKey) {
    throw new Error("Windmill S3 resource is missing access key/secret key");
  }

  // Windmill uses `endPoint` and a separate `useSSL` flag
  let endpoint = `${res.endPoint}:${res.port}`;
  if (endpoint && !/^https?:\/\//i.test(endpoint)) {
    endpoint = (res.useSSL === false ? "http://" : "https://") + endpoint;
  }

  return {
    region: res.region || "us-east-1",
    endpoint,
    forcePathStyle: res.pathStyle ?? Boolean(endpoint),
    credentials: { accessKeyId, secretAccessKey },
  };
}

/**
 * Save a string to S3/MinIO as an object.
 */
export async function main(
  bucket: string = "nextcloud",
  filepath: string,
  data: string,
  contentType: string = "text/plain; charset=utf-8",
  cacheControl?: string
): Promise<{ bucket: string; key: string; etag?: string }> {
  if (!bucket) throw new Error("bucket is required");
  if (!filepath) throw new Error("filepath (key) is required");

  // 👇 fetch your S3 resource globally (adjust path if needed)
  const s3res: WindmillS3 = await getResource("u/jtmckay/s3");
  const cfg = normalizeS3(s3res);

  const client = new S3Client(cfg);

  const body = new TextEncoder().encode(data);
  const cmd = new PutObjectCommand({
    Bucket: bucket,
    Key: filepath,
    Body: body,
    ContentType: contentType,
    CacheControl: cacheControl,
  });

  const out = await client.send(cmd);
  return { bucket, key: filepath, etag: out.ETag };
}
