FROM node:22-slim

RUN apt-get update && apt-get install -y git curl procps python3 make g++ cron tini && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev --prefer-online && npm cache clean --force

ENV PATH="/app/node_modules/.bin:$PATH"
ENV ALPHACLAW_ROOT_DIR=/data

# gbrain: install via the native ClawHub plugin path, then defensively patch
# in a top-level "id" field. As of the gbrain releases we've inspected, the
# manifest openclaw.plugin.json ships without "id", which OpenClaw's native
# plugin loader (manifest.ts) hard-requires ("plugin manifest requires id").
# This patch is a no-op if a future gbrain release already includes "id".
RUN openclaw plugins install clawhub:gbrain \
    && find /app /root -iname "openclaw.plugin.json" -path "*gbrain*" -print0 2>/dev/null \
       | xargs -0 -r -I{} node -e ' \
           const fs = require("fs"); \
           const p = process.argv[1]; \
           const j = JSON.parse(fs.readFileSync(p, "utf-8")); \
           if (!j.id) { j.id = "gbrain"; fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n"); console.log("patched id into " + p); } \
           else { console.log(p + " already has id: " + j.id); } \
         ' {}

RUN mkdir -p /data

EXPOSE 3000

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["alphaclaw", "start"]
