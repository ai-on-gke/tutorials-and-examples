import time
import threading
from datetime import datetime, timezone, timedelta
from kubernetes import client, config, watch
from prometheus_client import Gauge, start_http_server


POD_STARTUP_TIME = Gauge(
    "k8s_pod_startup_seconds",
    "Time from Pod container start to Pod Ready",
    ["namespace", "owner", "owner_kind", "pod"],
)

POD_CREATED_TO_READY_TIME = Gauge(
    "k8s_pod_created_to_ready_seconds",
    "Time from Pod creation to Pod Ready (includes scheduling and image pull)",
    ["namespace", "owner", "owner_kind", "pod"],
)

POD_SCHEDULED_TO_READY_TIME = Gauge(
    "k8s_pod_scheduled_to_ready_seconds",
    "Time from Pod scheduled to Pod Ready (node-side latency)",
    ["namespace", "owner", "owner_kind", "pod"],
)

class PodStartupMonitor:
    def __init__(self, namespace=None):
        try:
            config.load_incluster_config()
            print("Using in-cluster config")
        except:
            config.load_kube_config()
            print("Using KUBECONFIG")

        self.namespace = namespace # Keep None to track all namespaces
        self.apps = client.AppsV1Api()
        self.core = client.CoreV1Api()

        self.seen_pods = set()

        self.lock = threading.Lock()

    def watch_pods(self):
        w = watch.Watch()
        retry_delay = 5
        
        while True:
            try:
                stream = (
                    w.stream(self.core.list_namespaced_pod, self.namespace)
                    if self.namespace
                    else w.stream(self.core.list_pod_for_all_namespaces)
                )

                for event in stream:
                    self.handle_pod(event["object"])
                
                retry_delay = 5

            except Exception as e:
                print(f"Pod watch error: {e}")
                time.sleep(retry_delay)
                retry_delay = min(retry_delay * 2, 60)

    def get_scheduled_time(self, pod):
        """Get the time when pod was assigned to a node"""
        if not pod.status.conditions:
            return None
    
        for c in pod.status.conditions:
            if c.type == "PodScheduled" and c.status == "True":
                return c.last_transition_time
    
        return None

    def handle_pod(self, pod):
        ns = pod.metadata.namespace
        pod_name = pod.metadata.name
        pod_key = (ns, pod_name)
    
        owner, owner_kind = self.get_owner_info(pod)
    
        created = pod.metadata.creation_timestamp
        scheduled = self.get_scheduled_time(pod)
        started = self.get_started_time(pod)
        ready = self.get_ready_time(pod)
    
        if not created or not ready:
            return
    
        with self.lock:
            if pod_key in self.seen_pods:
                return
            self.seen_pods.add(pod_key)
    
        common_labels = dict(
            namespace=ns,
            owner=owner,
            owner_kind=owner_kind,
            pod=pod_name,
        )
    
        # Created to Ready (total end-to-end)
        created_to_ready = (ready - created).total_seconds()
        if created_to_ready >= 0:
            POD_CREATED_TO_READY_TIME.labels(**common_labels).set(created_to_ready)
    
        # Scheduled to Ready (node-side: image pull + runtime + app warmup)
        if scheduled:
            sched_to_ready = (ready - scheduled).total_seconds()
            if sched_to_ready >= 0:
                POD_SCHEDULED_TO_READY_TIME.labels(**common_labels).set(sched_to_ready)
    
        # Started to Ready (runtime + app warmup only)
        if started:
            started_to_ready = (ready - started).total_seconds()
            if started_to_ready >= 0:
                POD_STARTUP_TIME.labels(**common_labels).set(started_to_ready)
    
        msg = (
            f"[READY] {ns}/{pod_name} ({owner_kind}/{owner}) "
            f"created_to_ready={created_to_ready:.2f}s"
        )
        if scheduled:
            msg += f" sched_to_ready={sched_to_ready:.2f}s"
        if started:
            msg += f" started_to_ready={started_to_ready:.2f}s"
        print(msg)
        
    def get_started_time(self, pod):
        """Get the time when pod containers started"""
        if not pod.status.container_statuses:
            return None
        
        # Earliest container start time
        start_times = []
        for container_status in pod.status.container_statuses:
            if container_status.state and container_status.state.running:
                if container_status.state.running.started_at:
                    start_times.append(container_status.state.running.started_at)
        
        return min(start_times) if start_times else None

    def get_ready_time(self, pod):
        """Get the time when pod became Ready"""
        if not pod.status.conditions:
            return None

        for c in pod.status.conditions:
            if c.type == "Ready" and c.status == "True":
                return c.last_transition_time

        return None

    def get_owner_info(self, pod):
        """Extract owner name and kind from pod's owner references"""
        if not pod.metadata.owner_references:
            return pod.metadata.name, "standalone"
            
        for ref in pod.metadata.owner_references:
            if ref.kind == "ReplicaSet":
                parts = ref.name.rsplit("-", 1)
                return (parts[0] if len(parts) == 2 else ref.name), "Deployment"
            elif ref.kind in ("StatefulSet", "DaemonSet", "Job", "Node"):
                return ref.name, ref.kind

        ref = pod.metadata.owner_references[0]
        return ref.name, ref.kind

    def run(self, port=8080):
        start_http_server(port)
        print(f"Metrics available on :{port}/metrics")

        threading.Thread(target=self.watch_pods, daemon=True).start()

        while True:
            time.sleep(1)


if __name__ == "__main__":
    import os
    import sys

    namespace = sys.argv[1] if len(sys.argv) > 1 else os.getenv("NAMESPACE")
    port = int(os.getenv("METRICS_PORT", "8080"))

    PodStartupMonitor(namespace).run(port)
