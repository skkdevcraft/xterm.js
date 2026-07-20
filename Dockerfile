# Stage 1: Build all esbuild bundles
FROM node:22-bookworm AS builder

WORKDIR /workspace

# Install system build dependencies (needed for native addons like node-pty)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Copy dependency manifests first for better caching
COPY package.json package-lock.json ./

# Copy the workspace addon manifests (needed for npm workspace resolution)
COPY addons/addon-attach/package.json addons/addon-attach/package.json
COPY addons/addon-clipboard/package.json addons/addon-clipboard/package.json
COPY addons/addon-fit/package.json addons/addon-fit/package.json
COPY addons/addon-image/package.json addons/addon-image/package.json
COPY addons/addon-ligatures/package.json addons/addon-ligatures/package.json
COPY addons/addon-progress/package.json addons/addon-progress/package.json
COPY addons/addon-search/package.json addons/addon-search/package.json
COPY addons/addon-serialize/package.json addons/addon-serialize/package.json
COPY addons/addon-unicode11/package.json addons/addon-unicode11/package.json
COPY addons/addon-unicode-graphemes/package.json addons/addon-unicode-graphemes/package.json
COPY addons/addon-web-fonts/package.json addons/addon-web-fonts/package.json
COPY addons/addon-webgl/package.json addons/addon-webgl/package.json
COPY addons/addon-web-links/package.json addons/addon-web-links/package.json

# Install all dependencies (including workspaces)
RUN npm ci --ignore-scripts && npm rebuild node-pty

# Copy source code needed for esbuild bundles
COPY tsconfig*.json ./
COPY src/ ./src/
COPY addons/ ./addons/
COPY demo/ ./demo/
COPY bin/ ./bin/
COPY typings/ ./typings/
COPY test/ ./test/
COPY css/ ./css/

# Build esbuild bundles (compiles TypeScript natively, no tsc/tsgo needed).
# We build each piece individually, skipping test outputs that are not needed.

#   1. Core xterm.mjs
RUN node bin/esbuild.mjs && node bin/esbuild.mjs --headless

#   2. All addon .mjs bundles
RUN node <<'SCRIPT'
const { execSync } = require('child_process');
const fs = require('fs');
const addons = fs.readdirSync('addons')
  .filter(f => f.startsWith('addon-'))
  .map(f => f.slice(6));
for (const a of addons) {
  console.log('Building addon: ' + a);
  execSync('node bin/esbuild.mjs --addon=' + a, { stdio: 'inherit' });
}
SCRIPT

#   3. Demo server bundle  (external: node-pty only)
RUN node bin/esbuild.mjs --demo-server

#   4. Demo client bundle  (aliases addon .mjs files)
RUN node bin/esbuild.mjs --demo-client

# ---------------------------------------------------------------------------
# Stage 2: Runtime image — only what's needed to serve the demo
FROM node:22-bookworm-slim

WORKDIR /workspace

# Install runtime system dependencies for node-pty
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Copy node_modules from builder (node-pty is the only runtime external dep)
COPY --from=builder /workspace/node_modules ./node_modules

# Copy the demo server bundle and its entry point
COPY --from=builder /workspace/demo/dist/server-bundle.js ./demo/dist/server-bundle.js
COPY --from=builder /workspace/demo/dist/server-bundle.js.map ./demo/dist/server-bundle.js.map
COPY --from=builder /workspace/demo/start.js ./demo/start.js

# Copy the demo client bundle (served statically)
COPY --from=builder /workspace/demo/dist/client-bundle.*.js ./demo/dist/

# Copy static assets served by the demo server
COPY --from=builder /workspace/css/xterm.css ./css/xterm.css
COPY --from=builder /workspace/demo/index.html ./demo/index.html
COPY --from=builder /workspace/demo/test.html ./demo/test.html
COPY --from=builder /workspace/demo/index.css ./demo/index.css
COPY --from=builder /workspace/demo/logo.png ./demo/logo.png
COPY --from=builder /workspace/demo/fonts ./demo/fonts

# Expose the demo server port
EXPOSE 3000

# Start the demo server (see demo/start.js)
CMD ["node", "demo/start.js"]
