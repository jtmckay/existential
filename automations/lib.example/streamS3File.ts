// Fetch a file from a pre-signed S3 URL, returning its blob and metadata.
// Mirrors the AWS SDK stream pattern from the reference implementation but works
// with rclone-generated signed URLs — no AWS SDK or extra deps required.

export interface S3File {
  blob: Blob;
  contentType: string;
  contentLength: number;
  filename: string;
}

const AUDIO_TYPES: Record<string, string> = {
  mp3: "audio/mpeg",
  mp4: "audio/mp4",
  wav: "audio/wav",
};

function inferContentType(filename: string, fallback: string): string {
  const ext = filename.split(".").pop()?.toLowerCase() ?? "";
  return AUDIO_TYPES[ext] ?? fallback;
}

export async function streamS3File(preSignedUrl: string): Promise<S3File> {
  const filename = decodeURIComponent(
    new URL(preSignedUrl).pathname.split("/").pop() ?? "audio"
  );

  const headRes = await fetch(preSignedUrl, { method: "HEAD" });
  if (!headRes.ok) {
    throw new Error(`HEAD ${preSignedUrl} → ${headRes.status} ${headRes.statusText}`);
  }
  const rawContentType = headRes.headers.get("content-type") ?? "";
  const contentLength = Number(headRes.headers.get("content-length") ?? 0);
  const contentType =
    rawContentType && rawContentType !== "application/octet-stream"
      ? rawContentType
      : inferContentType(filename, rawContentType || "application/octet-stream");

  const getRes = await fetch(preSignedUrl);
  if (!getRes.ok) {
    throw new Error(`GET ${preSignedUrl} → ${getRes.status} ${getRes.statusText}`);
  }
  const blob = await getRes.blob();

  return { blob, contentType, contentLength, filename };
}
