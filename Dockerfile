FROM node:22-slim

RUN apt-get update && apt-get install -y git curl procps python3 make g++ cron tini unzip && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev --prefer-online && npm cache clean --force

ENV PATH="/app/node_modules/.bin:$PATH"
ENV ALPHACLAW_ROOT_DIR=/data

# gbrain: build from source and install as a native OpenClaw plugin.
# Both the plain `bun install -g github:garrytan/gbrain` release AND
# ClawHub's published bundle (gbrain@0.10.1) ship openclaw.plugin.json
# without a top-level "id" field, which OpenClaw's native plugin loader
# hard-requires ("plugin manifest requires id"). We build from source
# (which also gets us the compiled ./bin/gbrain the manifest's mcpServers
# entry expects — a plain install doesn't produce that binary) and patch
# the id in before installing from the local, already-fixed copy so
# OpenClaw's manifest validation passes.
#
# --dangerously-force-unsafe-install: OpenClaw's dangerous-code scanner
# flags gbrain's use of `new RegExp(...)` (src/core/takes-fence.ts, a
# regex built from a string constant to parse "takes" tables) as dynamic
# code execution. Reviewed the source: no eval/new Function/vm.*/dynamic
# require-import/child_process anywhere in the file. Treating this as a
# scanner false positive on RegExp construction, not real dangerous code.
ENV BUN_INSTALL="/opt/bun"
ENV PATH="$BUN_INSTALL/bin:$PATH"
RUN curl -fsSL https://bun.sh/install | bash \
    && git clone --depth=1 https://github.com/garrytan/gbrain.git /opt/gbrain \
    && cd /opt/gbrain \
    && bun install \
    && bun run build \
    && node -e ' \
         const fs = require("fs"); \
         const p = "/opt/gbrain/openclaw.plugin.json"; \
         const j = JSON.parse(fs.readFileSync(p, "utf-8")); \
         if (!j.id) j.id = "gbrain"; \
         fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n"); \
       ' \
    && openclaw plugins install /opt/gbrain --link --dangerously-force-unsafe-install

RUN mkdir -p /data

EXPOSE 3000

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["alphaclaw", "start"]
