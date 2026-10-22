# Deployment planning prompts

These are prompts, not deployment files.

## Dockerfile
Choose a versioned Node base image. Select WORKDIR, copy the service files, select a runtime user, and set the Node startup command. No dependencies need installing. Ensure .dockerignore excludes files unnecessary for the image.

## Compose
Choose an image tag and build context, runtime PORT/SERVICE_NAME/MESSAGE values, and a host-to-container port mapping. Run inside a VM. Record which address/port the host uses and any VM port forwarding.

## Kubernetes
Use that same image tag. Decide how it is loaded into your cluster and choose an appropriate imagePullPolicy. Define matching Deployment Pod labels and Service selectors. Set replicas to two and align application, container, and Service ports. Document access.

## Experiments
Record a working baseline before changing anything. Observe Pod names and readiness before/after deleting one Pod. For the controlled failure, change the Service selector only, inspect labels and EndpointSlices, and restore it.

## CS554
Choose and justify CPU/memory requests/limits. Add an HTTP readiness probe for /health. Plan a one-replica readiness failure and recovery without terminating its application process.

## OpenStack
Complete the written deployment plan from the handout. Installation is not required.
