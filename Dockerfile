# node:24-alpine — Node 24 is the current Active LTS line (LTS since Oct 2025, supported to Apr 2028).
FROM node:24-alpine

WORKDIR /app

# Copy manifests first so `npm ci` is only re-run when dependencies actually change.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY . .

# Alpine node images ship a non-root `node` user (uid 1000) — use it instead of root.
USER node

EXPOSE 8080

CMD ["node", "server.js"]
