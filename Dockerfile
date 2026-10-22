# Same image is used by Docker Compose (in the VM) and by Kubernetes (k3s).
FROM node:22.11.0-alpine3.20

ENV NODE_ENV=production \
    PORT=8080

WORKDIR /app

# The service has no npm dependencies, so only the manifest and source are copied.
COPY package.json ./
COPY src/ ./src/

# Run as the unprivileged "node" user provided by the base image.
USER node

EXPOSE 8080

# Exec form so node is PID 1 and receives SIGTERM directly from docker/kubelet.
CMD ["node", "src/server.js"]
