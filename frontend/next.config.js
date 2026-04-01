// =============================================================================
// frontend/next.config.js
// -----------------------------------------------------------------------------
// Next.js build configuration.
// =============================================================================

/** @type {import('next').NextConfig} */
const nextConfig = {
  // output: "standalone" tells Next.js to produce a self-contained build
  // in .next/standalone/ that includes its own minimal Node.js server.
  // This is required for the multi-stage Docker build — it allows the final
  // container image to run without a full node_modules directory.
  // Result: the Docker image is ~80% smaller than a standard Next.js build.
  output: "standalone"
};

module.exports = nextConfig;
