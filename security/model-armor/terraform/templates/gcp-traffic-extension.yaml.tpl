kind: GCPTrafficExtension
apiVersion: networking.gke.io/v1
metadata:
  name: ${NAME}
  namespace: ${NAMESPACE}
spec:
  targetRefs:
  - group: "gateway.networking.k8s.io"
    kind: Gateway
    name: ${GATEWAY_NAME}
  extensionChains:
  - name: model-armor-chain
    matchCondition:
      celExpressions:
      - celMatcher: 'request.path == "/v1/completions"'
    extensions:
    - name: model-armor-service
      supportedEvents:
      - RequestHeaders
      - RequestBody
      - ResponseBody
      - ResponseHeaders
      - ResponseTrailers
      - RequestTrailers
      timeout: "10000ms"
      googleAPIServiceName: "modelarmor.us-central1.rep.googleapis.com"
      failOpen: false
      metadata:
        model_armor_settings: '${MODEL_ARMOR_SETTINGS}'
