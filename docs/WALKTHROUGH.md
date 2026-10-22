# Walkthrough recording script (target 4 minutes)

Show results, not installation. Before recording: VM running, Compose up, Deployment applied, two terminals open (host + `multipass shell cs454-vm`, `cd ~/cs454-midterm`).

| Time | Show | Say (key points) |
|---|---|---|
| 0:00–0:30 | `docs/REPORT.md` diagram | Mac host → Multipass VM (192.168.252.4) → Docker container and k3s Pods, all from one image `cs454-midterm:1.0.0`. |
| 0:30–1:15 | VM: `docker compose ps`; `curl localhost:8080/` ×2. Host: `curl http://192.168.252.4:8080/` and `/health`. VM: `docker compose logs --tail 5 web` | Healthy container; host reaches the VM directly over the vmnet shared network on published port 8080; each request is logged. |
| 1:15–1:45 | `docker compose restart web`, then `curl localhost:8080/` | Same hostname, count back to 1: the process restarted and its in-memory counter was lost. |
| 1:45–2:30 | `kubectl get deploy,pods,svc,endpointslices -l app=cs454-web` (endpointslices: `-l kubernetes.io/service-name=cs454-web`); `scripts/svc-requests.sh 6` | 2/2 ready, Service selects both Pods; in-cluster client through the Service hits both hostnames (port-forward would pin to one). |
| 2:30–3:10 | `kubectl delete pod <one> --wait=false; kubectl get pods -w` (Ctrl-C after it is 1/1) | ReplicaSet sees 1 ≠ 2 and creates a new Pod; new name, new IP, counter starts at 1. Compose only restarts in place. |
| 3:10–4:10 | Troubleshooting: `kubectl patch service cs454-web --type merge -p '{"spec":{"selector":{"app":"cs454-web-broken"}}}'`; `scripts/svc-requests.sh 2` (ECONNREFUSED); `kubectl get pods` (still Ready); `kubectl get svc -o wide`; EndpointSlice `<unset>`; `kubectl apply -f k8s/service.yaml`; `scripts/svc-requests.sh 2` (200) | Pods healthy but the Service has zero endpoints because the selector matches no labels; kube-proxy rejects → connection refused. Healthy Pods ≠ reachable Service. Re-applying the manifest fixes it. |
| 4:10–4:30 | (optional, CS554) `kubectl exec <pod> -- touch /tmp/not-ready`, show `0/1 Running`, restore | Readiness removes a Pod from Service traffic without restarting it. |
