# =============================================================================
# frontend/Dockerfile
# -----------------------------------------------------------------------------
# Multi-stage build for the Next.js frontend.
# Uses 3 stages to produce a minimal production image:
#   Stage 1 (deps)    — install Node dependencies
#   Stage 2 (builder) — compile the Next.js app into a standalone bundle
#   Stage 3 (runner)  — final image with ONLY the compiled output
#
# The final image does NOT contain: source code, node_modules, or build tools.
# This makes it significantly smaller and more secure than a single-stage build.
# =============================================================================

# Stage 1: Install dependencies only
# Separated so Docker can cache this layer — npm install only re-runs if
# package.json changes, not when source code changes.
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json ./
RUN npm install

# Stage 2: Build the application
# Copies node_modules from stage 1, then compiles Next.js.
# "npm run build" generates the .next/standalone directory (enabled by next.config.js output: 'standalone').
FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules  
COPY . .
RUN npm run build

# Stage 3: Production runtime image
# Only copies the compiled standalone bundle from the builder stage.
# No source code, no node_modules bloat — just what's needed to run.
FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production  

# Copy only the compiled output — standalone mode produces a self-contained server.js
COPY --from=builder /app/.next/standalone ./
# Copy static assets (CSS, JS, images) served directly by Next.js
COPY --from=builder /app/.next/static ./.next/static

# Document that the container listens on port 3000
EXPOSE 3000

# Start the standalone Next.js server
CMD ["node", "server.js"]
