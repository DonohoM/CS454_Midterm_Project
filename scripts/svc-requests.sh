#!/usr/bin/env bash
# Send N requests to the Service from a short-lived in-cluster client Pod.
# Uses the app image itself (Node's fetch), so no extra image pull is needed.
# Traffic goes through the Service's ClusterIP, so only Ready endpoints are used.
# usage: scripts/svc-requests.sh [count] [path]
set -euo pipefail
N="${1:-8}"; P="${2:-/}"
kubectl run "client-$RANDOM" --rm -i --restart=Never --quiet \
  --image=cs454-midterm:1.0.0 --image-pull-policy=Never --command -- \
  node -e "(async()=>{for(let i=0;i<$N;i++){try{const r=await fetch('http://cs454-web$P',{headers:{connection:'close'},signal:AbortSignal.timeout(3000)});console.log(r.status,await r.text())}catch(e){console.log('ERROR',e.cause?.code??e.name)}}})()" 2>&1 \
  | grep -v -e 'All commands and output' -e "If you don't see a command prompt"
