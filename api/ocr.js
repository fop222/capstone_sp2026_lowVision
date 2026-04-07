export default async function handler(req, res) {
  // Proxies Flutter web requests to the OCR/VLM Flask server to avoid HTTPS->HTTP mixed content.
  // Configure target with Vercel env var: OCR_PROXY_TARGET (e.g. http://128.180.121.230:5010)

  const targetBase = (process.env.OCR_PROXY_TARGET || "").replace(/\/$/, "");
  if (!targetBase) {
    res.status(500).json({
      error:
        "OCR_PROXY_TARGET is not set. Set it in Vercel Environment Variables (e.g. http://128.180.121.230:5010).",
    });
    return;
  }

  // Map: /api/ocr?path=/extract-text  ->  ${targetBase}/extract-text
  const path = typeof req.query.path === "string" ? req.query.path : "/extract-text";
  const targetUrl = new URL(targetBase + path);

  // Forward method + body (supports multipart/form-data and JSON).
  const init = {
    method: req.method,
    headers: {
      // Let node fetch set content-length boundaries automatically for multipart.
      // Forward content-type if present (important for multipart).
      ...(req.headers["content-type"] ? { "content-type": req.headers["content-type"] } : {}),
    },
  };

  if (req.method !== "GET" && req.method !== "HEAD") {
    // Vercel provides req as a stream; read raw bytes.
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    init.body = Buffer.concat(chunks);
  }

  const upstream = await fetch(targetUrl.toString(), init);
  const buf = Buffer.from(await upstream.arrayBuffer());

  // Copy content-type back.
  const ct = upstream.headers.get("content-type");
  if (ct) res.setHeader("content-type", ct);
  res.status(upstream.status).send(buf);
}

