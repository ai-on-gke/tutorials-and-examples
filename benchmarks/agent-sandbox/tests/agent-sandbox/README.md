```bash
git clone https://github.com/kubernetes/perf-tests.git

cp config.yaml perf-tests/clusterloader2/config.yaml
cp agent-sandbox-deployment.yaml perf-tests/clusterloader2/agent-sandbox-deployment.yaml

cd perf-tests/clusterloader2

go run cmd/clusterloader.go \
    --testconfig=./config.yaml \
    --provider=gke \
    --kubeconfig=$HOME/.kube/config \
    --report-dir=./test-results
```
