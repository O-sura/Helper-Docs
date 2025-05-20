### How to run Profile Tests related to APIM Distributed Setup

1. The profile testing is to using pizzashack API to test and verify the functionality and By default, but starting from APIM 4.5.0, pizzashack is not available by default. Because of that, get the pizzashack.war file inside an APIM pack and when building the APIM ACP image, copy that into the relavant directory.
<br>

    - [General Instructions and Postman Tests & Env files for local env](https://github.com/kavindasr/apim-distributed-dev-setup/tree/main/profile-testing)

    - [Postman Tests & Env files for cloud env](https://github.com/wso2/apim-test-integration/tree/4.4.0-profile-automation/tests-cases/profile-tests)
    
<br>

2. Deploy the Distributed Setup using the helm chart available in the helm-apim. In the gateway deployment, add the following ingress rule as well. (To expose and unexposed route)

```yaml
# -------------------------------------------------------------------------------------
#
# Copyright (c) 2025, WSO2 LLC. (http://www.wso2.com). All Rights Reserved.
#
# This software is the property of WSO2 LLC. and its suppliers, if any.
# Dissemination of any information or reproduction of any material contained 
# herein is strictly forbidden, unless permitted by WSO2 in accordance with the 
# WSO2 Commercial License available at https://wso2.com/licenses/eula/3.2
#
# --------------------------------------------------------------------------------------

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
    namespace: {{ .Release.Namespace }}
    annotations:
        nginx.ingress.kubernetes.io/backend-protocol: HTTPS
        nginx.ingress.kubernetes.io/proxy-buffer-size: 8k
        nginx.ingress.kubernetes.io/proxy-buffering: "on"
    name: gw-rest-ingress
spec:
    ingressClassName: nginx
    tls:
    - hosts:
        - {{ .Values.kubernetes.ingress.gateway.hostname }}
      secretName: {{ .Values.kubernetes.ingress.tlsSecret }}
    rules:
    - host: {{ .Values.kubernetes.ingress.gateway.hostname }}
      http:
        paths:
        - path: /api/am/gateway/v2/
          pathType: Prefix
          backend:
            service:
                name: {{ template "apim-helm-gw.fullname" . }}-service
                port:
                  number: {{ add 9443 .Values.wso2.apim.portOffset }}

```
<br>

3. In the postman-env.json, change the properties like ports, cluster IP, pizzashack endpoint, operation_policy_file_path depending on the env. And to run the tests, newman should be installed.
<br>

4. To run the tests:

```
newman run Profile_Tests_Collection.json \
  --environment APIM-4.5.0.postman_environment.json \
  --env-var "cluster_ip=4.224.75.207" \
  --env-var "pizzashack_endpoint=https://apim-acp-wso2am-acp-service:9443/am/sample/pizzashack/v1/api/" \
  --env-var "operation_policy_file_path=./changeHTTPMethod_v2.j2" \
  --insecure --reporters cli,junit \
  --reporter-html-export newman-report.html \
  --delay-request 1000
```