# CS454 Midterm — One Service, Two Deployment Environments

A small Node.js HTTP service packaged as **one container image** (`cs454-midterm:1.0.0`) and deployed two ways:

1. **Docker Compose** inside an Ubuntu 24.04 VM (Multipass on macOS), reachable from the Mac host.
2. **Kubernetes** (single-node **k3s**) running inside that **same VM**, as a 2-replica Deployment behind a ClusterIP Service.

> **ScreenShots:** [ScreenShots/](ScreenShots/)

| Deliverable | Location |
|---|---|
| Application source | [src/server.js](src/server.js), tests in [test/](test/) |
| Dockerfile / .dockerignore | [Dockerfile](Dockerfile), [.dockerignore](.dockerignore) |
| Compose configuration | [compose.yaml](compose.yaml) |
| Kubernetes manifests | [k8s/deployment.yaml](k8s/deployment.yaml), [k8s/service.yaml](k8s/service.yaml) |
| In-cluster test client | [scripts/svc-requests.sh](scripts/svc-requests.sh) |
| Technical report (diagram, comparison, troubleshooting, OpenStack, CS554 extension) | [docs/REPORT.md](docs/REPORT.md) |
| Evidence log (index + raw terminal transcripts) | [evidence/EVIDENCE.md](evidence/EVIDENCE.md) |
| Walkthrough script | [docs/WALKTHROUGH.md](docs/WALKTHROUGH.md) |

---

## Application

| Endpoint | Behavior |
|---|---|
| `GET /` | JSON: `service` (from `SERVICE_NAME`), `message` (from `MESSAGE`), `hostname` (container/Pod hostname), `requestCount` |
| `GET /health` | `200 {"status":"ok"}` while ready; `503 {"status":"not-ready"}` if the optional readiness toggle file exists |
| anything else | `404` |

| Variable | Default | Purpose |
|---|---|---|
| `PORT` | `8080` | Listening port (binds `0.0.0.0`) |
| `SERVICE_NAME` | `cs454-midterm` | Returned in `service` |
| `MESSAGE` | `Hello from the mini-project!` | Returned in `message` |
| `NOT_READY_FILE` | _(unset)_ | **CS554 only.** If set and the file exists, `/health` returns 503. Unset = original starter behavior. |

**Counter behavior:** `requestCount` is an in-memory counter inside each Node.js process and increments only on successful `GET /` requests (not `/health`). It resets when the process restarts, and each replica has its own count. Every request is logged to stdout as one JSON line (`{"method":"GET","path":"/","status":200}`), so it appears in `docker compose logs` / `kubectl logs`.

**Change from the starter:** I added the optional `NOT_READY_FILE` readiness toggle (≈8 lines in `src/server.js`, plus a test). It exists because Kubernetes forbids editing a running Pod's readiness probe (see [evidence 06](evidence/06-readiness-cs554.txt)), so the CS554 experiment needs a per-Pod, application-level way to fail readiness without stopping the process.

## Tools used

| Where | Tool | Version used |
|---|---|---|
| Host | macOS 27 (Apple Silicon, arm64), Multipass | 1.16.3 |
| VM | Ubuntu 24.04.5 LTS (arm64), 2 vCPU / 3 GB RAM / 15 GB disk | kernel 6.8 |
| VM | Docker Engine + Compose plugin | 29.9.2 / v5.6.0 |
| VM | k3s (Kubernetes) + bundled `kubectl` | v1.36.5+k3s1 |
| Base image | `node:22.11.0-alpine3.20` | Node 22 |

Any Linux VM with Docker Engine works the same way; on x86 hosts the commands are identical.

---

## 0. Run the tests locally (optional)

```bash
npm test                 # Node >= 22, no npm install needed
```

## 1. Create the VM (manual setup step)

```bash
# On the host (macOS)
multipass launch 24.04 --name cs454-vm --cpus 2 --memory 3G --disk 15G
multipass info cs454-vm          # note the IPv4 address (mine: 192.168.252.4)
multipass shell cs454-vm         # open a shell inside the VM
```

**VM networking:** On macOS, Multipass's default network is Apple **vmnet "shared" mode** (NAT). The host gets a bridge interface (`bridge100`, `192.168.252.1/24`) and the VM gets a private address on the same subnet (`enp0s1`, `192.168.252.4/24`). The host can reach the VM's address **directly**, so **no port forwarding is configured**. The VM reaches the internet via NAT through the host. Your VM's IP may differ: use `multipass info cs454-vm`.

## 2. Install Docker Engine + Compose in the VM (manual setup step)

From Docker's official apt repository ([docs](https://docs.docker.com/engine/install/ubuntu/)):

```bash
# Inside the VM
sudo apt-get update && sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker ubuntu && exit        # log out and back in so the group applies
```

## 3. Get the code into the VM

```bash
# Inside the VM
git clone <this-repo-url> ~/cs454-midterm && cd ~/cs454-midterm
```
(Alternative: `multipass transfer` a tarball from the host.)

## 4. Build the image

```bash
# Inside the VM, in ~/cs454-midterm
docker compose build             # builds ./Dockerfile and tags it cs454-midterm:1.0.0
docker image ls cs454-midterm
```

## 5. Docker Compose: start, access, inspect, restart

```bash
docker compose up -d
docker compose ps                               # STATUS shows (healthy) via the Compose healthcheck
curl -i http://localhost:8080/health            # from inside the VM
curl http://localhost:8080/
docker compose logs web                         # request log lines
docker compose restart web                      # same container, new process -> requestCount restarts at 1
```

From the **host** (macOS), using the VM's address:

```bash
curl http://192.168.252.4:8080/health
curl http://192.168.252.4:8080/
BASE_URL=http://192.168.252.4:8080 bash test/smoke.sh
```

Compose publishes VM port `0.0.0.0:8080` → container port `8080` (`ports: "8080:8080"`).

## 6. Install k3s in the same VM (manual setup step)

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --disable servicelb --write-kubeconfig-mode 644" sh -
kubectl get nodes -o wide        # k3s installs kubectl; node cs454-vm should be Ready
```

Traefik and ServiceLB are disabled because this project only needs a ClusterIP Service. `--write-kubeconfig-mode 644` lets the `ubuntu` user run `kubectl` without `sudo`.

## 7. Make the image available to Kubernetes (image loading)

k3s does **not** use Docker's image store; it runs its own containerd. The image built in step 4 is exported from Docker and imported into k3s's containerd. No registry is involved:

```bash
docker save cs454-midterm:1.0.0 | sudo k3s ctr images import -
sudo k3s crictl images | grep cs454-midterm      # docker.io/library/cs454-midterm  1.0.0
```

The Deployment uses `image: cs454-midterm:1.0.0` with **`imagePullPolicy: Never`**, so the kubelet uses only that local copy and never tries to pull from Docker Hub. **Repeat this import after every rebuild.**

## 8. Kubernetes: deploy, access, inspect

```bash
kubectl apply -f k8s/
kubectl rollout status deployment/cs454-web
kubectl get deployment,rs,pods,svc -l app=cs454-web -o wide
kubectl get endpointslices -l kubernetes.io/service-name=cs454-web
```

Access method A, **port-forward** (VM localhost:8081 → Service port 80). Note: this pins the session to *one* Pod:
```bash
kubectl port-forward service/cs454-web 8081:80 &
curl http://localhost:8081/ ; curl http://localhost:8081/health
kill %1   # in an interactive shell; otherwise kill the PID
```

Access method B, an **in-cluster client** that goes through the Service's ClusterIP and therefore only reaches Ready endpoints:
```bash
scripts/svc-requests.sh 8          # 8 requests to http://cs454-web/ from a throwaway Pod
```

## 9. Experiments (commands used; output in [evidence/](evidence/EVIDENCE.md))

```bash
# Pod replacement (Part 3)
kubectl delete pod <one-cs454-web-pod> --wait=false
kubectl get pods -l app=cs454-web --watch            # new Pod appears, becomes 1/1

# Selector failure (Part 4)
kubectl patch service cs454-web --type merge -p '{"spec":{"selector":{"app":"cs454-web-broken"}}}'
scripts/svc-requests.sh 3                            # ECONNREFUSED
kubectl get endpointslices -l kubernetes.io/service-name=cs454-web    # <unset>
kubectl apply -f k8s/service.yaml                    # restore the declared selector
scripts/svc-requests.sh 3                            # 200 again

# Readiness (CS554)
kubectl exec <pod> -- touch /tmp/not-ready           # that one Pod -> 0/1 Ready, still Running
kubectl get endpointslices -l kubernetes.io/service-name=cs454-web -o yaml   # conditions.ready: false
kubectl exec <pod> -- rm /tmp/not-ready              # back to 1/1
```

## 10. Cleanup

```bash
# Inside the VM
kubectl delete -f k8s/
sudo k3s ctr images rm docker.io/library/cs454-midterm:1.0.0
docker compose down
docker image rm cs454-midterm:1.0.0
/usr/local/bin/k3s-uninstall.sh          # optional: remove k3s entirely

# On the host: delete the VM entirely
multipass delete cs454-vm && multipass purge
```

## Not included (by design)

No VM images, image tarballs, kubeconfig files, keys or credentials are committed (see [.gitignore](.gitignore)).
