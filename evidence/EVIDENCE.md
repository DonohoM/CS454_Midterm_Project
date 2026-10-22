# Evidence Log

All output below was captured on 2026-10-20 (UTC) from the live environment. Each excerpt links to the **full, unedited transcript** (`*.txt`), which includes the exact command and a timestamp for every step. Prompts show where a command ran: `host$` = macOS host, `ubuntu@cs454-vm` = inside the Multipass VM.

| # | Requirement | Full transcript |
|---|---|---|
| E1 | VM details, Docker versions, image build | [01-vm-and-image.txt](01-vm-and-image.txt) |
| E2 | Compose: status, requests in VM and from host, logs, restart | [02-compose.txt](02-compose.txt) |
| E3 | Kubernetes: cluster location, image import, 2 ready replicas, Service access | [03-k8s-deploy.txt](03-k8s-deploy.txt) |
| E4 | Pod deletion and replacement | [04-pod-replacement.txt](04-pod-replacement.txt) |
| E5 | Service selector failure and recovery | [05-selector-failure.txt](05-selector-failure.txt) (first, invalidated attempt: [05a](05a-selector-failure-attempt1-invalidated.txt)) |
| E6 | CS554: resources, readiness probe, one-Pod NotReady experiment | [06-readiness-cs554.txt](06-readiness-cs554.txt) |

---

## E1 — VM and image

```
host$ multipass info cs454-vm
State:          Running
IPv4:           192.168.252.4
Release:        Ubuntu 24.04.5 LTS
CPU(s):         2

ubuntu@cs454-vm$ docker compose build ...
 Image cs454-midterm:1.0.0 Built
ubuntu@cs454-vm$ docker image ls cs454-midterm
IMAGE                 ID             DISK USAGE   CONTENT SIZE
cs454-midterm:1.0.0   1af027cc5226        218MB         54.1MB
```

## E2 — Docker Compose inside the VM

**Status (healthy) and published port:**
```
ubuntu@cs454-vm$ docker compose ps
NAME                  IMAGE                 STATUS                   PORTS
cs454-midterm-web-1   cs454-midterm:1.0.0   Up 8 seconds (healthy)   0.0.0.0:8080->8080/tcp, [::]:8080->8080/tcp
```

**Both endpoints from inside the VM:**
```
ubuntu@cs454-vm$ curl -s -i http://localhost:8080/health
HTTP/1.1 200 OK
{"status":"ok"}
ubuntu@cs454-vm$ curl -s http://localhost:8080/      (x3)
{"service":"cs454-midterm-compose","message":"Hello from Docker Compose inside the Multipass VM","hostname":"295a0125c83c","requestCount":1}
{"service":"cs454-midterm-compose",...,"hostname":"295a0125c83c","requestCount":2}
{"service":"cs454-midterm-compose",...,"hostname":"295a0125c83c","requestCount":3}
```

**From the macOS host to the VM (vmnet shared/NAT network, no port forwarding):**
```
host$ ifconfig bridge100 | grep 'inet '
	inet 192.168.252.1 netmask 0xffffff00 broadcast 192.168.252.255
host$ curl -s -i http://192.168.252.4:8080/health
HTTP/1.1 200 OK
{"status":"ok"}
host$ curl -s http://192.168.252.4:8080/
{"service":"cs454-midterm-compose",...,"hostname":"295a0125c83c","requestCount":4}
```

**How the VM port reaches the container (Docker DNAT rule):**
```
ubuntu@cs454-vm$ sudo iptables -t nat -S DOCKER | grep 8080
-A DOCKER ! -i br-0589de434458 -p tcp -m tcp --dport 8080 -j DNAT --to-destination 172.18.0.2:8080
```

**Container logs:**
```
ubuntu@cs454-vm$ docker compose logs --no-log-prefix web
Listening on port 8080
{"method":"GET","path":"/health","status":200}
{"method":"GET","path":"/","status":200}
...
```

**Restart → counter resets (same container/hostname, new process):**
```
ubuntu@cs454-vm$ curl -s http://localhost:8080/
{...,"hostname":"295a0125c83c","requestCount":6}
ubuntu@cs454-vm$ docker compose restart web
 Container cs454-midterm-web-1 Restarting
 Container cs454-midterm-web-1 Started
ubuntu@cs454-vm$ curl -s http://localhost:8080/
{...,"hostname":"295a0125c83c","requestCount":1}
ubuntu@cs454-vm$ docker compose logs --no-log-prefix --tail 8 web
...
Received SIGTERM; stopping.
Listening on port 8080
```
`docker compose down && up -d` instead created a **new container** (hostname `91cdf5e53727`, count 1). Killing the node process with `kill -9` made Docker's `restart: unless-stopped` policy restart the same container (`restarts=1`, count 1).

## E3 — Kubernetes (k3s in the same VM)

**Cluster location and the same image imported into k3s containerd:**
```
ubuntu@cs454-vm$ kubectl get nodes -o wide
NAME       STATUS   ROLES           VERSION        INTERNAL-IP     CONTAINER-RUNTIME
cs454-vm   Ready    control-plane   v1.36.5+k3s1   192.168.252.4   containerd://2.3.4-k3s1.36

ubuntu@cs454-vm$ docker save cs454-midterm:1.0.0 | sudo k3s ctr images import -
docker.io/library/cs454 midterm:1.0.0   	saved
application/vnd.oci.image.index.v1+json sha256:1af027cc522640df7f68b4c980e601999b9b6faa206f5279c9a0f89d111b7b7a
ubuntu@cs454-vm$ sudo k3s crictl images | grep -E 'IMAGE|cs454'
IMAGE                              TAG                 IMAGE ID            SIZE
docker.io/library/cs454-midterm    1.0.0               68150b0eff014       54.1MB
```
(The index digest `1af027cc…` equals Docker's image ID, and image ID `68150b0e…` equals the config digest from the Docker build. It is the same image.)

**Deployment, two ready Pods, Service, EndpointSlice:**
```
ubuntu@cs454-vm$ kubectl get deployment cs454-web -o wide
NAME        READY   UP-TO-DATE   AVAILABLE   IMAGES                SELECTOR
cs454-web   2/2     2            2           cs454-midterm:1.0.0   app=cs454-web

ubuntu@cs454-vm$ kubectl get pods -l app=cs454-web -o wide --show-labels
NAME                        READY   STATUS    RESTARTS   IP          LABELS
cs454-web-dc55fc6cd-fwjfl   1/1     Running   0          10.42.0.6   app=cs454-web,pod-template-hash=dc55fc6cd
cs454-web-dc55fc6cd-qrvmg   1/1     Running   0          10.42.0.5   app=cs454-web,pod-template-hash=dc55fc6cd

ubuntu@cs454-vm$ kubectl get service cs454-web -o wide
NAME        TYPE        CLUSTER-IP     PORT(S)   SELECTOR
cs454-web   ClusterIP   10.43.72.144   80/TCP    app=cs454-web

ubuntu@cs454-vm$ kubectl get endpointslices -l kubernetes.io/service-name=cs454-web -o wide
NAME              ADDRESSTYPE   PORTS   ENDPOINTS
cs454-web-vfdqk   IPv4          8080    10.42.0.6,10.42.0.5
```

**Requests through the Service. Port-forward stays on one Pod; the in-cluster client reaches both:**
```
ubuntu@cs454-vm$ kubectl port-forward service/cs454-web 8081:80 & ; curl localhost:8081/health ; curl localhost:8081/ (x4)
{"status":"ok"}
{"service":"cs454-midterm-k8s","message":"Hello from Kubernetes (k3s)","hostname":"cs454-web-dc55fc6cd-fwjfl","requestCount":1}
... fwjfl 2, fwjfl 3, fwjfl 4            <- every request to the same Pod

ubuntu@cs454-vm$ kubectl run client ... node -e "fetch('http://cs454-web/') x8"
200 {...,"hostname":"cs454-web-dc55fc6cd-qrvmg","requestCount":1}
...
200 {...,"hostname":"cs454-web-dc55fc6cd-fwjfl","requestCount":5}
200 {...,"hostname":"cs454-web-dc55fc6cd-qrvmg","requestCount":6}
200 {...,"hostname":"cs454-web-dc55fc6cd-fwjfl","requestCount":6}
```

## E4 — Pod replacement

```
ubuntu@cs454-vm$ kubectl delete pod cs454-web-dc55fc6cd-qrvmg --wait=false; timeout 12 kubectl get pods -l app=cs454-web --watch -o wide
pod "cs454-web-dc55fc6cd-qrvmg" deleted from default namespace
NAME                        READY   STATUS              RESTARTS   AGE   IP
cs454-web-dc55fc6cd-fx78m   1/1     Running             0          27s   10.42.0.9
cs454-web-dc55fc6cd-qq2b2   0/1     ContainerCreating   0          0s    <none>       <- replacement created immediately
cs454-web-dc55fc6cd-qrvmg   1/1     Terminating         0          69s   10.42.0.5
cs454-web-dc55fc6cd-qrvmg   0/1     Completed           0          69s   10.42.0.5
cs454-web-dc55fc6cd-qq2b2   0/1     Running             0          0s    10.42.0.11   <- running, not yet Ready
cs454-web-dc55fc6cd-qq2b2   1/1     Running             0          6s    10.42.0.11   <- readiness probe passed

ubuntu@cs454-vm$ kubectl get deploy cs454-web
NAME        READY   UP-TO-DATE   AVAILABLE
cs454-web   2/2     2            2
ubuntu@cs454-vm$ kubectl get endpointslices -l kubernetes.io/service-name=cs454-web
cs454-web-vfdqk   IPv4          8080    10.42.0.9,10.42.0.11
```
ReplicaSet events from the first deletion (Pod `fwjfl` → replacement `fx78m`):
```
Normal  SuccessfulCreate  52s   replicaset-controller  Created pod: cs454-web-dc55fc6cd-qrvmg
Normal  SuccessfulCreate  52s   replicaset-controller  Created pod: cs454-web-dc55fc6cd-fwjfl
Normal  SuccessfulCreate  10s   replicaset-controller  Created pod: cs454-web-dc55fc6cd-fx78m
```
New Pods start at `requestCount` 1 (`fx78m` → 1, 2, 3) while the surviving Pod keeps counting (`qrvmg` → 8, 9, 10).

## E5 — Controlled failure: Service selector mismatch

**Baseline:** selector `{"app":"cs454-web"}`, EndpointSlice `10.42.0.9,10.42.0.11`, in-cluster requests and a port-forward both return 200.

**Change (exact):**
```
ubuntu@cs454-vm$ kubectl patch service cs454-web --type merge -p '{"spec":{"selector":{"app":"cs454-web-broken"}}}'
service/cs454-web patched
```

**Symptom seen by clients:**
```
ubuntu@cs454-vm$ scripts/svc-requests.sh 3          # in-cluster client -> http://cs454-web/
ERROR ECONNREFUSED
ERROR ECONNREFUSED
ERROR ECONNREFUSED
ubuntu@cs454-vm$ time kubectl port-forward service/cs454-web 8081:80   # new session
error: timed out waiting for the condition
real	1m0.151s
```

**Observations:**
```
# 1. Deployment and Pods healthy
cs454-web   2/2     2            2
cs454-web-dc55fc6cd-fx78m   1/1   Running   0   10.42.0.9    app=cs454-web,pod-template-hash=dc55fc6cd
cs454-web-dc55fc6cd-qq2b2   1/1   Running   0   10.42.0.11   app=cs454-web,pod-template-hash=dc55fc6cd

# 2. Selector does not match any Pod label
cs454-web   ClusterIP   10.43.72.144   80/TCP   app=cs454-web-broken
ubuntu@cs454-vm$ kubectl get pods -l app=cs454-web-broken
No resources found in default namespace.

# 3. EndpointSlice is empty
NAME              ADDRESSTYPE   PORTS     ENDPOINTS
cs454-web-vfdqk   IPv4          <unset>   <unset>

# 4. kube-proxy rejects traffic to the ClusterIP (explains ECONNREFUSED)
-A KUBE-SERVICES -d 10.43.72.144/32 -p tcp -m comment --comment "default/cs454-web:http has no endpoints" -m tcp --dport 80 -j REJECT --reject-with icmp-port-unreachable

# 5. A direct Pod request works (app is fine; this does NOT test the Service)
POD_IP=10.42.0.9  ->  {"status":"ok"}
```

**Correction and recovery:**
```
ubuntu@cs454-vm$ kubectl apply -f k8s/service.yaml
service/cs454-web configured
cs454-web   ClusterIP   10.43.72.144   80/TCP   app=cs454-web
cs454-web-vfdqk   IPv4   8080   10.42.0.11,10.42.0.9
ubuntu@cs454-vm$ scripts/svc-requests.sh 4
200 {...,"hostname":"cs454-web-dc55fc6cd-qq2b2","requestCount":5}
200 {...,"hostname":"cs454-web-dc55fc6cd-fx78m","requestCount":9}
...
# new port-forward session:
{...,"hostname":"cs454-web-dc55fc6cd-fx78m","requestCount":11} (curl exit=0)
```

**Two incidental observations** (documented with notes in the transcripts): a port-forward session opened **before** the selector change kept working after it, and a port-forward attached to a Pod that was later deleted died with `error: lost connection to pod`. Both show that a port-forward is bound to one Pod and does not re-check the Service.

## E6 — CS554: resources, readiness probe, readiness experiment

**Applied settings:**
```
cs454-web-dc55fc6cd-fx78m  qos=Burstable  resources={"limits":{"cpu":"250m","memory":"128Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}
    Readiness:  http-get http://:http/health delay=2s timeout=2s period=5s #success=1 #failure=2
ubuntu@cs454-vm$ kubectl top pods -l app=cs454-web
cs454-web-dc55fc6cd-fx78m   3m           10Mi
cs454-web-dc55fc6cd-qq2b2   3m           10Mi
```

**Per-Pod probe patch is not allowed (why a toggle file is used):**
```
The Pod "cs454-web-dc55fc6cd-fx78m" is invalid: spec: Forbidden: pod updates may not change fields other than `spec.containers[*].image`, ...
```

**Baseline:**
```
10.42.0.11	cs454-web-dc55fc6cd-qq2b2	ready=true	serving=true
10.42.0.9	cs454-web-dc55fc6cd-fx78m	ready=true	serving=true
```

**Failure:** `kubectl exec cs454-web-dc55fc6cd-fx78m -- touch /tmp/not-ready`
```
NAME                        READY   STATUS    RESTARTS   AGE
cs454-web-dc55fc6cd-fx78m   0/1     Running   0          5m23s     <- NotReady, still Running, no restart
cs454-web-dc55fc6cd-qq2b2   1/1     Running   0          4m56s
cs454-web   1/2     2            1

10.42.0.11	cs454-web-dc55fc6cd-qq2b2	ready=true	serving=true
10.42.0.9	cs454-web-dc55fc6cd-fx78m	ready=false	serving=false

ubuntu@cs454-vm$ kubectl exec cs454-web-dc55fc6cd-fx78m -- ps -o pid,etime,args
    1  5:25   node src/server.js                  <- process still running
Warning  Unhealthy  3s (x3 over 8s)  kubelet  Readiness probe failed: HTTP probe failed with statuscode: 503
curl http://10.42.0.9:8080/   -> 200 {...,"hostname":"cs454-web-dc55fc6cd-fx78m","requestCount":15}   <- direct, bypasses Service

ubuntu@cs454-vm$ scripts/svc-requests.sh 8          # through the Service
200 {...,"hostname":"cs454-web-dc55fc6cd-qq2b2",...}   x8   <- only the Ready Pod receives traffic
```
Note: `kubectl get endpointslices -o wide` still lists `10.42.0.9` in its ENDPOINTS column because that column shows all addresses regardless of readiness. The `conditions.ready` field is what kube-proxy acts on.

**Recovery:** `kubectl exec cs454-web-dc55fc6cd-fx78m -- rm /tmp/not-ready`
```
cs454-web-dc55fc6cd-fx78m   1/1     Running   0          5m45s     <- same Pod, still 0 restarts
cs454-web   2/2     2            2
10.42.0.11	cs454-web-dc55fc6cd-qq2b2	ready=true	serving=true
10.42.0.9	cs454-web-dc55fc6cd-fx78m	ready=true	serving=true
    1  5:46   node src/server.js                  <- same process (elapsed time continues)
200 {...,"hostname":"cs454-web-dc55fc6cd-fx78m","requestCount":16}   <- counter continued from 15: no restart
ubuntu@cs454-vm$ kubectl diff -f k8s/ >/dev/null && echo ...
live objects match k8s/ manifests (kubectl diff: no changes)
```
