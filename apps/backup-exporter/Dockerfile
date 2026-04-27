# syntax=docker/dockerfile:1
FROM node:20-alpine AS builder
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci --ignore-scripts

COPY tsconfig.json ./
COPY src/ ./src/
RUN npm run build

# ---- runtime stage ----
FROM node:20-alpine AS runtime
WORKDIR /app

ENV NODE_ENV=production

COPY package.json package-lock.json* ./
RUN npm ci --omit=dev --ignore-scripts

COPY --from=builder /app/dist ./dist

STOPSIGNAL SIGTERM

USER node

# Default: single-run mode. Container scheduler (Dallas's Bicep) controls frequency.
# Set EXPORT_LOOP_INTERVAL_MS to run continuously without an external scheduler.
CMD ["node", "dist/index.js"]
