# node:24-alpine — Node 24 is the current Active LTS line (LTS since Oct 2025, supported to Apr 2028).
FROM node:24-alpine AS deps

WORKDIR /app

# Copy manifests first so `npm ci` is only re-run when dependencies actually change.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

FROM node:24-alpine

# The app only ever runs `node`, but the base image also ships npm, npx, corepack and yarn.
# Their bundled dependencies (tar, undici, brace-expansion, ...) were the source of every
# HIGH finding Trivy reported for this image, so they are removed from the runtime stage.
RUN rm -rf /usr/local/lib/node_modules /usr/local/bin/npm /usr/local/bin/npx \
    /usr/local/bin/corepack /usr/local/bin/yarn /usr/local/bin/yarnpkg /opt/yarn-*

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Alpine node images ship a non-root `node` user (uid 1000) — use it instead of root.
USER node

EXPOSE 8080

# Docker-only liveness check (Kubernetes ignores HEALTHCHECK). /api/random_name needs no database.
HEALTHCHECK --interval=30s --timeout=3s \
  CMD ["node", "-e", "fetch('http://127.0.0.1:' + (process.env.SERVER_PORT || 8080) + '/api/random_name').then(r => process.exit(r.ok ? 0 : 1), () => process.exit(1))"]

CMD ["node", "server.js"]
