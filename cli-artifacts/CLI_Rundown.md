# AP(CLI Tool)

```sh
Two flows

 ┌─ PATH 1 · UI-driven (no files anywhere) ──────────────────────────────────┐
 │                                                                           │
 │  AI Workspace SPA                                                         │
 │   Service Providers ─▶ [+ Add New Provider]                               │
 │        │                                                                  │
 │        ├─ pick template ......... openai │ anthropic │ google-vertex      │
 │        │                          aws-bedrock │ mistralai │ meta          │
 │        ├─ Connection tab ........ upstream URL + vendor API key           │
 │        ├─ Models tab ............ which models this provider exposes      │
 │        ├─ Security tab .......... api-key-auth for consumers              │
 │        ├─ Rate Limiting tab ..... request / token / cost ceilings         │
 │        ├─ Guardrails tab ........ content policies                        │
 │        └─ Resources tab ......... /chat/completions, /embeddings, …       │
 │        │                                                                  │
 │        ▼  BFF /proxy ─▶ platform-api                                      │
 │   POST /api/v0.9/llm-providers                    ← provider created
 │        │                                                                  │
 │   Deployments card ─▶ [Deploy to gateway]
 │   POST /api/v0.9/llm-providers/{id}/deployments   ← {gatewayId, host}     │
 │        │
 │        ▼  WebSocket push to the connected gateway-controller              │
 │   controller fetches artifact ─▶ bbolt ─▶ xDS ─▶ Envoy + Policy Engine
 └───────────────────────────────────────────────────────────────────────────┘

 ┌─ PATH 2 · CLI / GitOps (files in git) ────────────────────────────────────┐
 │
 │  ap project init --display-name "OpenAI Provider" \                       │
 │                  --type App-LLM-Provider
 │        │                                                                  │
 │        ▼  ⚠ scaffold is REST-shaped — you rewrite runtime.yaml
 │  edit metadata.yaml   (+ spec.associatedGateways)                         │
 │  edit runtime.yaml    (template, upstream.url, auth, accessControl,
 │                        policies)                                          │
 │  edit definition.yaml (OpenAPI, folded into the payload verbatim)
 │        │                                                                  │
 │  ap ai-workspace use -n <workspace>
 │  ap ai-workspace build       ← validates presence/kind/name ONLY          │
 │  ap ai-workspace apply       ← no --project-id: providers aren't
 │        │                       project-scoped (build.go:288-291)          │
 │        ▼
 │  POST /api/v0.9/llm-providers  { id, displayName, version, context,       │
 │        │                         template, openapi, modelProviders,
 │        │                         upstream{main{url,auth}}, security,      │
 │        │                         rateLimiting, accessControl, policies,
 │        │                         associatedGateways[] }                   │
 │        ▼  same WebSocket push ─▶ gateway
 └───────────────────────────────────────────────────────────────────────────┘


What an API project is

One directory = one artifact, expressed as Kubernetes-style manifests, living in git. It's the single source of truth that fans out to three destinations. The CLI never invents state; every apply is a pure function of these files plus the active connection.

ap project init --display-name "Echo API" --type REST
                                 │
                                 ▼
Echo API/                              ← dir name = display name verbatim
├── .api-platform/
│   └── config.yaml                    ← the project's routing table (not the artifact)
├── metadata.yaml                      ← identity / catalog facing
├── runtime.yaml                       ← execution / gateway facing
├── definition.yaml                    ← the contract (OpenAPI 3.0.3 starter)
├── docs/                              ← created empty
└── tests/                             ← created empty

Only those three dirs and four files. cli/src/cmd/project/init.go:124-160.

The four artifact types

--type is one of these exact strings (cli/src/utils/constants.go:104-108), and it changes the apiVersion + kind stamped into the manifests:

 --type              metadata.yaml                         runtime.yaml
 ─────────────────── ───────────────────────────────────── ──────────────────────
 REST                management.api-platform.wso2.com/v1   gateway.…wso2.com/v1
                     kind: RestApi                         kind: RestApi
                     (full business/ownership spec)

 LLM-Proxy           ai-workspace.…wso2.com/v1alpha        gateway.…wso2.com/v1
                     kind: LlmProxyMetadata                kind: LlmProxy

 App-LLM-Provider    ai-workspace.…wso2.com/v1alpha        gateway.…wso2.com/v1
                     kind: LlmProviderMetadata             kind: LlmProvider

 MCP-Proxy           ai-workspace.…wso2.com/v1alpha        gateway.…wso2.com/v1
                     kind: McpMetadata                     kind: Mcp

Two things to notice. First, runtime.yaml always carries the gateway.… apiVersion regardless of type — it's the gateway's language in every case. Second, AI-Workspace metadata kinds carry a Metadata suffix precisely so they don't collide with the runtime kind; ap ai-workspace build strips that suffix and asserts the two match (build.go:211-219). A LlmProxyMetadata paired with an Mcp runtime is a hard build failure.

The three artifact files

┌─ metadata.yaml ─────────────────────────────────────────────────────────┐
│  WHO this API is. Never deployed to the gateway.                        │
│                                                                          │
│  REST form:                        AI-Workspace form:                    │
│    spec.displayName                  spec.displayName                    │
│    spec.version                      spec.version                        │
│    spec.description                                                      │
│    spec.gatewayType  wso2/api-platform    ← that's it. Two fields.       │
│    spec.status       PUBLISHED                                           │
│    spec.referenceID  ""            ← YOU fill this: the gateway API ID   │
│    spec.tags[] / labels[]             returned by `ap gateway apply`     │
│    spec.businessInformation{4}                                           │
│    spec.endpoints{sandboxUrl, productionUrl}                             │
└──────────────────────────────────────────────────────────────────────────┘

┌─ runtime.yaml ──────────────────────────────────────────────────────────┐
│  HOW it executes. This is the file the gateway ingests, verbatim.       │
│                                                                          │
│    spec.displayName   "Echo API"                                        │
│    spec.version       ""            ← emitted EMPTY, you must fill it    │
│    spec.context       ""            ← emitted EMPTY, you must fill it    │
│    spec.upstream.main.url  http://sample-backend.org:9080                │
│                            # "Change this to your backend URL"           │
│    spec.operations[]  /* × GET POST PUT DELETE OPTIONS                   │
│                                                                          │
│  Everything real lives here and is NOT scaffolded — policies (api-key-   │
│  auth, cors, rate-limit), subscriptionPlans, per-operation policy chains,│
│  LLM provider auth, MCP tool defs. See gateway/examples/*.yaml.          │
└──────────────────────────────────────────────────────────────────────────┘

┌─ definition.yaml ───────────────────────────────────────────────────────┐
│  WHAT the contract is. openapi: 3.0.3, one "/*" path, 5 verbs, all 200.  │
│  Consumed by devportal (published as the spec) and ai-workspace (folded  │
│  into the llm-proxy/mcp payload). The gateway does NOT read it.          │
└──────────────────────────────────────────────────────────────────────────┘

.api-platform/config.yaml — the routing table

This is the piece people miss: it's not part of the artifact, it's the map telling each command where to look.

version: 1.0.0

# Default file paths (can be customized)
filePaths:
  deploymentArtifact: ./runtime.yaml
  metadataFile: ./metadata.yaml
  definition: ./definition.yaml
  docs: ./docs
  tests: ./tests

# Governance rulesets for design-time validation
governanceRulesets: []

# Auto-sync configuration for vscode plugin
autoSync:
  gatewayArtifactFromDefinition: true  # Auto-generate runtime.yaml when definition.yaml changes

Then ~20 lines of commented-out portal templates that ap devportal gen (or you, by hand) uncomment. Because every path is indirected through here, you can rename or relocate any file and the commands follow — Normalize() backfills anything left blank (config.go:128-145).

How the files fan out to destinations

                 metadata.yaml   runtime.yaml   definition.yaml   ./devportal
                       │              │               │                │
 ap gateway apply ─────┼──────────────●───────────────┼────────────────┼──▶ gateway-controller
   -f runtime.yaml     │         (the ONLY file)      │                │
                       │              │               │                │
 ap devportal gen ─────●──────────────┼───────────────●────────────────▶ creates ./devportal/
 ap devportal build    │              │               │                │   (devportal.yaml,
 ap devportal apply ───┼──────────────┼───────────────┼────────────────●──▶ definition.yaml,
                       │              │               │                     docs/, content/)
 ap ai-workspace ──────●──────────────●───────────────●─────────────────────▶ platform-api
   build / apply    (identity +   (auth, upstream,  (OpenAPI folded
                     assoc.       model routing)    into payload)
                     gateways)

So: gateway takes one file, devportal takes two + a generated overlay, ai-workspace takes all three.

The portal overlay model

A project can carry sub-roots that repackage the same artifact per destination:

Echo API/
├── metadata.yaml  runtime.yaml  definition.yaml     ← canonical
├── devportal/                                       ← `ap devportal gen` creates this
│   ├── devportal.yaml     (portal-specific metadata)
│   ├── definition.yaml    (COPIED from project root)
│   ├── docs/  content/
└── ai-workspace/                                    ← optional, config-declared only
    ├── artifact.yaml  runtime.yaml  definition.yaml

Config-wise these are asymmetric by design: devportals: is a list (a project can publish to many portals), ai-workspace: is a single object — "a project can have at most one ai-workspace configuration" (config.go:95-100). If you declare no ai-workspace block at all, build/apply default portalRoot: "." and read the project root directly (build.go:155-158), which is why the AI Workspace flow works with no extra scaffolding.

Naming rules

metadata.name is derived, not the display name — lowercased, _/space → -, everything outside [a-z0-9.-] → -, collapsed hyphens, trimmed, fallback "api" (init.go:186-202). "Echo API" → echo-api. This value is the identity key: it's what apply looks up to decide create-vs-update, and build rejects the project if metadata.yaml and runtime.yaml disagree on it.


```
## Three main components of artifact


1. runtime.yaml — replace wholesale, modeled on gateway/examples/mistral-provider.yaml:

```yaml
apiVersion: gateway.api-platform.wso2.com/v1
kind: LlmProvider
metadata:
  name: mistral-provider
spec:
  displayName: Mistral Provider
  version: v1.0                      # must match ^v\d+\.\d+$
  template: mistralai                # drives modelProviders; without it that block is omitted
  upstream:
    url: https://api.mistral.ai      # note: upstream.url, NOT upstream.main.url
    auth:
      type: api-key
      header: Authorization
      value: Bearer <YOUR_MISTRAL_KEY>
  policies:
    - name: api-key-auth
      version: v1
      paths:
        - {path: /v1/chat/completions, methods: [POST], params: {key: X-AP
        - {path: /v1/embeddings,       methods: [POST], params: {key: X-API-Key, in: header}}
        - {path: /v1/models,           methods: [GET],  params: {key: X-AP
  accessControl:
    mode: deny_all
    exceptions:
      - {path: /v1/chat/completions, methods: [POST]}
      - {path: /v1/embeddings,       methods: [POST]}
      - {path: /v1/models,           methods: [GET]}
```

2. definition.yaml — the scaffold's /* placeholder is useless. There's a realer-specs/mistral/openapi.yaml. Copy it over.

3. metadata.yaml — only needed for Path B; add the CP gateway handle once you

```yaml
spec:
  displayName: Mistral Provider
  version: v1.0
  associatedGateways:
    - id: <gateway-handle-from-platform-api>
```

### Note: 
Only an extreme basic artifact gets generated when we run `ap project init`. Users have to manually add the contents to runtime.yaml and defintional.yaml and so on

# -----------------------------------------------------------
#  ----   E2E Gateway Registering and Deployment Path ---
# -----------------------------------------------------------


# Add Platform Gateway to AP

To add the gateway
```sh
ap gateway add --display-name local --server [http://localhost:9090](http://localhost:9090) --auth basic
```
Use the gateway
```sh
ap gateway use --display-name local
```

# Add AI-Workspace to AP

 gateway-controller :9090   →  HTTP Basic     ✅ your command is right
   gateway/configs/config.toml:37  [controller.auth.basic] + [[…users]]

 platform-api       :9243   →  Bearer JWT only ❌ basic/api-key won't authenticate
   internal/middleware/auth.go:133-141

ap gateway add --display-name local --server [http://localhost:9090](http://localhost:9090) --auth basic is exactly right. Its credentials are the admin user the gateway's own scripts/setup.sh generated (WSO2AP_GW_USERNAME / WSO2AP_GW_PASSWORD).

Use [https://localhost:9243](https://localhost:9243) — platform-api, not 9643

I probed both of your running services:

GET  [https://localhost:9243/api/v0.9/projects](https://localhost:9243/api/v0.9/projects)         -> 401   ← API is here, needs a token
POST [https://localhost:9243/api/portal/v0.9/auth/login](https://localhost:9243/api/portal/v0.9/auth/login) -> 401   ← login endpoint live, rejects bad pw
GET  [https://localhost:9643/](https://localhost:9643/)                           -> 200   ← SPA + BFF, browser only

9643 is the AI Workspace SPA behind its BFF — it proxies under a /proxy prefix using browser session cookies, which the CLI has no way to obtain. The CLI builds bare paths like /api/v0.9/llm-providers with no prefix option, so it must talk to placompose maps 9243:9243, so it's reachable from the host.

Connect it

Your logs confirm Auth mode: file (local users, RS256-signed JWT), so the you a token. Username is admin (portals/ai-workspace/api-platform.env:1);the password was printed once by portals/scripts/setup.sh — only the bcrypt hash is stored, so if you've lost it, re-run that script with --force to rotate.

# 1. Get a JWT

```sh
curl -sk -X POST https://localhost:9243/api/portal/v0.9/auth/login \
  -d 'username=admin&password=<your-password>' | jq -r .token
# → eyJhbGciOiJSUzI1NiI…
```

# 2. Export it (keeps the token out of ~/.wso2ap/config.yaml)

```sh
export WSO2AP_AIWORKSPACE_TOKEN='eyJhbGciOiJSUzI1NiI…'
```

# 3. Register the connection

```sh
ap ai-workspace add --display-name dev \
  --server https://localhost:9243 \
  --auth oauth --no-interactive
ap ai-workspace use --display-name dev
```

The admin user's scopes in config.toml already include ap:llm_provider:manage, ap:gateway:manage, and ap:project:manage, so this token covers everything you need.

Self-signed cert, so add --insecure to every ap ai-workspace command (and -k to curl). apply also takes -o json if you want the full server response rather than the summary.

# Connect the Platfrom Gateway to Platfrom-API

```sh
export TOKEN=$(curl -sk -X POST https://localhost:9243/api/portal/v0.9/auth/login \
  -d 'username=admin&password=<your-password>' | jq -r .token)

echo "${TOKEN:0:20}…"   # sanity check it's a JWT, not null
- This is the same ai-workspace token

```

No org creation needed — file mode declares [platform_api.auth.file.organization] id = "default" in config.toml, and your JWT already carries it.

#### 1. Register the gateway

```sh
curl -k -X POST https://localhost:9243/api/v0.9/gateways \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -d '{
    "id": "local-gateway",
    "displayName": "Local Gateway",
    "description": "Local docker-compose gateway",
    "endpoints": ["https://localhost:8443"],
    "functionalityType": "ai"
  }' | jq

```

Required fields are displayName, endpoints, functionalityType (CreateGatewayRequest, openapi.yaml:5705-5708). id is optional but set it explicitly — it's the immutable handle (^[a-z0-9-]+$) you'll reference everywhere else. Use functionalityType: "ai" since you're deploying LLM artifacts. The response comes back with "isActive": false — expected, nothing has connected yet.

#### 2. Generate the gateway token

```sh
export GW_TOKEN=$(curl -sk -X POST \
  https://localhost:9243/api/v0.9/gateways/local-gateway/tokens \
  -H "Authorization: Bearer $TOKEN" -H 'Accept: application/json' | jq -r .token)

echo "$GW_TOKEN"
```

Copy this now — the list endpoint (GET …/tokens) only ever returns hashes, never the token again.

#### 3. Wire it into the gateway-controller

This is the part curl can't do for you. The gateway dials out to platform-api, so the controller needs the host and token in its config. gateway/docker-compose.yaml:35-37 loads gateway/api-platform.env, so append there:

```sh
cat >> gateway/api-platform.env <<EOF
APIP_GW_CONTROLLER_CONTROLPLANE_HOST=host.docker.internal:9243
APIP_GW_CONTROLLER_CONTROLPLANE_TOKEN=$GW_TOKEN
APIP_GW_CONTROLLER_CONTROLPLANE_INSECURE_SKIP_VERIFY=true
APIP_GW_CONTROLLER_CONTROLPLANE_GATEWAY_NAME=local-gateway
EOF
```

#### 4. Verify the connection

```sh
# controller side — should show a control-plane connection, not a retry loop
docker compose -f gateway/docker-compose.yaml logs -f gateway-controller | grep -i "control plane\|connect"

# platform-api side — look for the connection.ack
docker logs -f platform-api | grep -i "websocket\|gateway"

# authoritative check: isActive flips to true
curl -sk https://localhost:9243/api/v0.9/gateways/local-gateway \
  -H "Authorization: Bearer $TOKEN" | jq '{id, isActive, functionalityType}'
```

isActive: true is your green light. If it stays false, it's almost always the HOST value — check the controller logs for a dial error.

#### 5. Then associate and apply

```yaml
# cli-artifacts/Mistral Provider/metadata.yaml
spec:
  displayName: Mistral Provider
  version: v1.0
  associatedGateways:
    - id: local-gateway        # the handle from step 1
```

```sh
cd "cli-artifacts/Mistral Provider"
ap ai-workspace apply --insecure -o json
```

#### 6. Next step: it's created, but not deployed

Worth knowing now: associatedGateways only writes an association mapping (service/llm.go:932-967 → resolveAssociatedGateways). It does not create a deployment. Deployment is a separate call, and the CLI has no ai-workspace deploy sub-command — this is the one step you must do by curl or in the UI:

```sh
curl -k -X POST \
  https://localhost:9243/api/v0.9/llm-providers/mistral-provider/deployments \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "v1.0-local",
    "base": "current",
    "gatewayId": "local-gateway"
  }' | jq
```

## For Deploying LLMProxy

#### Before deploying it, we should have a project created and the proxy should be associated with a specific project

Expected on a fresh install — nothing auto-creates a project. Providers are org-scoped so your Mistral provider didn't need one; proxies do.

For creating a project:

```sh
curl -k -X POST https://localhost:9243/api/v0.9/projects \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -d '{
    "id": "default-project",
    "displayName": "Default Project",
    "description": "Local development project"
  }' | jq
```

Only displayName is required (CreateProjectRequest, openapi.yaml:4960-4961) — id is auto-generated from it if omitted, but set it explicitly so you get a predictable handle instead of whatever slug it derives. organizationId comes from your JWT (default), so don't send it. Your admin token already carries ap:project:manage.

Verify:

```sh
curl -sk https://localhost:9243/api/v0.9/projects \
  -H "Authorization: Bearer $TOKEN" | jq '.list[] | {id, displayName, organizationId}'
```

### Get the provider API Key(Required for the Loopback call made by the proxy -> provider)

There's a dedicated endpoint for it — POST /llm-providers/{id}/api-keys.

```sh
curl -k -X POST \
  https://localhost:9243/api/v0.9/llm-providers/mistral-provider/api-keys \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -d '{
    "id": "proxy-loopback-key",
    "displayName": "Mistral Proxy Loopback Key"
  }' | jq

```

Response (CreateLLMProviderAPIKeyResponse, openapi.yaml:7965-7988):

```json
{
  "status": "success",
  "message": "API key created and broadcasted to gateways successfully",
  "id": "proxy-loopback-key",
  "apiKey": "a1b2c3…"      ← 64 hex chars, shown ONCE
}
```

Only displayName is required; id is derived from it if omitted. Optional expiresAt (ISO 8601) and allowedTargets — a comma-separated gateway list, defaulting to ALL; you could
scope it to local-gateway, but leave it default for the repro so it isn't

Copy apiKey immediately. GET …/api-keys lists metadata only — the plain vain, so a lost key means generating a new one.

Then drop it into the proxy:

```yaml
# cli-artifacts/Mistral-Proxy/runtime.yaml
  provider:
    id: mistral-provider
    auth:
      type: api-key
      header: X-API-Key
      value: a1b2c3…          # the 64-hex key from above
```

One thing to expect

This endpoint broadcasts the key to every gateway in the org and declares available response. So it needs your gateway-controller actually connected — if you get a 503 rather than a 201, that's the WebSocket, not the request. Check first:

```sh
curl -sk https://localhost:9243/api/v0.9/gateways/local-gateway \
  -H "Authorization: Bearer $TOKEN" | jq '{id, isActive}'
```

Then continue the repro:

```sh
cd "cli-artifacts/Mistral-Proxy"
ap ai-workspace apply --project-id default-project --insecure -o json

# Deploy
curl -k -X POST \
  https://localhost:9243/api/v0.9/llm-proxies/mistral-proxy/deployments \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"name":"v1.0-local","base":"current","gatewayId":"local-gateway"}' | jq
```



### For invoking the deployed LLM Provider and LLM Proxy  

```sh
There are three separate keys in this setup, and the one you verified isn't the one being checked:

 Mistral vendor key      upstream.auth.value in runtime.yaml
                         gateway → api.mistral.ai
                         ✓ you confirmed this works — but the client never sends it

 Provider consumer key   X-API-Key header                    ← the 401 is here
                         client → gateway
                         from POST /llm-providers/mistral-provider/api-keys

 Proxy consumer key      X-API-Key on the proxy route
                         separate key, separate endpoint


So for a proxy call you end up with three credentials in play:

 PROXY_API_KEY      → X-API-Key you send      client → proxy
 provider.auth.value → in runtime.yaml         proxy → provider (loopback)
 upstream.auth.value → in provider runtime.yaml gateway → api.mistral.ai


```
  
Generate the Provider Key


```sh
# This is the same command we used for generating the provider token required for adding
# into the LLMProxy.provider.auth.value

export PROVIDER_API_KEY=$(curl -sk -X POST \
  https://localhost:9243/api/v0.9/llm-providers/mistral-provider/api-keys \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"id":"local-test-key","displayName":"Local Test Key"}' | jq -r .apiKey)
```

Invoke the provider using it

```sh
curl -k -X POST https://localhost:8443/v1/chat/completions \
  -H "X-API-Key: $PROVIDER_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "mistral-small-latest",
    "messages": [{"role": "user", "content": "Say hello in one sentence."}]
  }' | jq
```

Generate the Key for Proxy

```sh
export PROXY_API_KEY=$(curl -sk -X POST \
  https://localhost:9243/api/v0.9/llm-proxies/mistral-proxy/api-keys \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"id":"proxy-consumer-key","displayName":"Proxy Consumer Key"}' | jq -r .apiKey)
```

Invoke using that key

```sh
curl -k -X POST https://localhost:8443/mistral-proxy/v1/chat/completions \
  -H "X-API-Key: $PROXY_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"model":"mistral-small-latest","messages":[{"role":"user","content":"ping"}]}' | jq
```