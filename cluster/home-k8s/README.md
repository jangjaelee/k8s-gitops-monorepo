# home-k8s

집 홈랩 Kubernetes 클러스터 `home-k8s`의 플랫폼 구성요소 명세입니다. 이 폴더에는 이 클러스터에 배포하는 모든 것을 둡니다.
구성요소의 버전이나 Argo CD Application이 바뀌면 **같은 PR에서 이 문서도 갱신합니다**(리뷰 에이전트 검사 9번).

> 이 폴더 안 파일 주석에 적은 경로(`helm/...`, `manifests/...`, `argocd/applications/...`)는 이 폴더 기준입니다.
> Application의 `path`와 `$values` 경로는 레포 루트 기준(`cluster/home-k8s/...`)입니다.

## 클러스터

| 항목 | 값 |
|---|---|
| 구성 | kubeadm, 5노드(control-plane 1 + worker 3 + CI 전용 worker-node-04, 아래 "CI 전용 노드"), Ubuntu 24.04, 모든 노드 Wi-Fi(192.168.50.0/24) |
| Kubernetes | v1.36.0 |
| 컨테이너 런타임 | containerd 2.3.6 |
| CNI | Cilium 1.20.2 — kube-proxy 대체, VXLAN, LB IPAM + L2 announcement, Local Redirect Policy |
| GitOps | Argo CD v3.5.5 (chart argo-cd 10.10.5, `https://argocd.awx.kr`, Google 로그인) |
| Service mesh | Istio 1.30.3 sidecar 모드 + istio-cni, revision `1-30-3`(tag `default`) |
| Ingress | Gateway API v1.5.1 (Istio 구현), Gateway `istio-system/istio-gateway` |
| 인증서 | cert-manager v1.20.2 + 사설 CA(`ClusterIssuer/homelab-ca`) |
| 스토리지 | local-path-provisioner v0.0.37 (기본 StorageClass `local-path`, Retain) |

## 폴더 구성

```
cluster/home-k8s/
├── README.md                  # 이 문서 (구성요소·버전·Application 명세)
├── argocd/
│   ├── applications/          # Argo CD Application (kubectl apply로 등록)
│   └── repositories/          # Argo CD 저장소 등록 Secret (공개 저장소만, 인증 정보 없음)
├── helm/<release>/            # Helm values (Argo CD multi-source의 $values 또는 Helm CLI)
├── manifests/<app>/           # Helm이 아닌 매니페스트 (path 소스 Application)
├── images/<name>/             # 클러스터에서 쓰는 자체 이미지 Dockerfile (GitHub Actions가 ghcr.io로 빌드)
└── node-config/               # 노드(OS) 설정 — Argo CD 미적용, SSH로 설치
```

## 구성요소 명세

### Helm CLI로 관리 (Argo CD 미관리)

CNI나 Argo CD가 망가져도 Argo CD 없이 복구할 수 있게 Helm CLI로 직접 적용합니다.

| Release | 네임스페이스 | 차트 | 앱 버전 | values |
|---|---|---|---|---|
| cilium | kube-system | cilium/cilium 1.20.2 | 1.20.2 | `helm/cilium/values.yaml` |
| argocd | argo-cd | argo/argo-cd 10.10.5 | v3.5.5 | `helm/argocd/values.yaml` |

### Argo CD Application

모든 앱: `metadata.namespace: argo-cd`, automated sync(prune, selfHeal), `ServerSideApply=true`.

| Application | Project | 네임스페이스 | 소스(차트·버전 / 경로) | 앱 버전 | 이 레포의 values·매니페스트 | 비고 |
|---|---|---|---|---|---|---|
| gateway-api-crds | system | (cluster) | github.com/kubernetes-sigs/gateway-api `config/crd/standard` @ v1.5.1 | v1.5.1 | — | prune 끔 |
| cilium-lb | system | (cluster) | 이 레포 path @ main | — | `manifests/cilium-lb/` | LB IP 풀 .200–.220, L2 정책 |
| local-path-provisioner | system | local-path-storage | github.com/rancher/local-path-provisioner `deploy/chart` @ v0.0.37 | v0.0.37 | `helm/local-path-provisioner/values.yaml` | 기본 StorageClass |
| cert-manager | system | cert-manager | jetstack/cert-manager v1.20.2 | v1.20.2 | `helm/cert-manager/values.yaml` | `crds.enabled`, `crds.keep` |
| cert-manager-issuers | system | cert-manager | 이 레포 path @ main | — | `manifests/cert-manager-issuers/` | 사설 CA `homelab-ca` |
| istio-base | system | istio-system | istio/base 1.30.3 | 1.30.3 | `helm/istio-base/values.yaml` | `defaultRevision: 1-30-3` |
| istio-cni | system | istio-system | istio/cni 1.30.3 | 1.30.3 | `helm/istio-cni/values.yaml` | Cilium 체이닝 |
| istiod-1-30-3 | system | istio-system | istio/istiod 1.30.3 | 1.30.3 | `helm/istiod-1-30-3/values.yaml` | revision `1-30-3`, tag `default`, replicas 2(HPA min 2, PDB, 노드 분산) |
| gateways | system | istio-system | 이 레포 path @ main | proxyv2 1.30.3 | `manifests/gateways/` | Gateway(HPA min 2·max 5, PDB, 노드 분산), 인증서, HTTP→HTTPS 리다이렉트 |
| argocd-config | system | argo-cd | 이 레포 path @ main | — | `manifests/argocd/` | HTTPRoute `argocd.awx.kr` |
| argo-rollouts | system | argo-rollouts | argo/argo-rollouts 2.43.8 | v1.10.1 | `helm/argo-rollouts/values.yaml` | Gateway API 플러그인 v0.17.0 |
| kyverno | system | kyverno | kyverno/kyverno 3.9.1 | v1.19.1 | `helm/kyverno/values.yaml` | 엔진, `ServerSideDiff=true` |
| kyverno-policies | system | kyverno | kyverno/kyverno-policies 3.9.1 + 이 레포 path | v1.19.1 | `helm/kyverno-policies/values.yaml`, `manifests/kyverno-policies/` | PSS restricted 17개 + 모범 사례 2개, **모두 Audit**, `ServerSideDiff=true` |
| node-local-dns | system | kube-system | deliveryhero/node-local-dns 2.9.2 (OCI) + 이 레포 path | k8s-dns-node-cache 1.26.7 | `helm/node-local-dns/values.yaml`, `manifests/node-local-dns/` | Cilium LRP, 외부 이름은 1.1.1.1 → 8.8.8.8 → 공유기 순, serve_stale 1h |
| vault | system | vault | hashicorp/vault 0.34.1 + 이 레포 path | Vault 2.0.4 | `helm/vault/values.yaml`, `manifests/vault/` | raft 단일 노드, 자동 unseal CronJob |
| external-secrets | system | external-secrets | external-secrets/external-secrets 2.13.0 + 이 레포 path | v2.13.0 | `helm/external-secrets/values.yaml`, `manifests/external-secrets/` | ClusterSecretStore `vault`, `ServerSideDiff=true` |
| arc-controller | system | arc-systems | actions-runner-controller-charts/gha-runner-scale-set-controller 0.15.0 (OCI) + 이 레포 path | ARC 0.15.0 | `helm/arc-controller/values.yaml`, `manifests/arc-controller/` | 네임스페이스 arc-systems·arc-runners, `watchSingleNamespace: arc-runners` |
| arc-infralens | system | arc-runners | actions-runner-controller-charts/gha-runner-scale-set 0.15.0 (OCI) + 이 레포 path | ARC 0.15.0 | `helm/arc-infralens/values.yaml`, `manifests/arc-infralens/` | 러너 스케일 셋 `arc-infralens`(jangjaelee/infralens), DinD, ExternalSecret, NetworkPolicy |
| ci-cache | system | ci-cache | 이 레포 path | registry 3.1.2 | `manifests/ci-cache/` | CI 러너용 Docker Hub 미러(프록시)·BuildKit 캐시 레지스트리, worker-node-04 hostPath, 아래 "CI 전용 노드" |
| infralens-poc | default | infralens | github.com/jangjaelee/infralens(비공개) `deploy/helm/infralens` @ 040baef | sha-040baef | `helm/infralens-poc/values.yaml` | InfraLens PoC, 배포 키 필요(아래 "InfraLens PoC" 절) |
| kube-state-metrics | system | kube-system | prometheus-community/kube-state-metrics 7.4.0 | v2.19.0 | 기본값 | |
| metric-server | o11y | kube-system | metrics-server/metrics-server 3.13.0 | v0.8.0 | `helm/metrics-server/values.yaml` | release 이름 `metric-server` |
| kube-prometheus-stack | o11y | prometheus-operator | prometheus-community/kube-prometheus-stack 84.1.0 | operator v0.90.1 | `helm/prometheus-operator/values.yaml` | |

### Argo CD 저장소 등록

| 파일 | 저장소 | 용도 |
|---|---|---|
| `argocd/repositories/deliveryhero-oci.yaml` | `ghcr.io/deliveryhero/helm-charts` (OCI, 공개) | node-local-dns 차트 |
| `argocd/repositories/arc-oci.yaml` | `ghcr.io/actions/actions-runner-controller-charts` (OCI, 공개) | ARC 차트 |
| (레포에 없음) Secret `argo-cd/repo-infralens` | `git@github.com:jangjaelee/infralens.git` (비공개, 읽기 전용 배포 키) | InfraLens 차트. 개인 키가 들어 있어 클러스터에서 직접 만든다 |

## 외부 노출

모든 외부 접속은 Istio Gateway 하나(LB IP `192.168.50.200`)로 들어옵니다. DNS A 레코드는 hosting.co.kr에 등록합니다.

```
Client ──► 192.168.50.200 (Cilium LB IPAM, L2 ARP)
            └─► Service istio-system/istio-gateway-istio (LoadBalancer, Istio 자동 생성, externalTrafficPolicy Local: 클라이언트 IP 보존, Gateway Pod 있는 노드만 L2 광고)
                 └─► Gateway istio-system/istio-gateway  (:80 HTTP, :443 HTTPS, 호스트별 listener)
                      └─► HTTPRoute ─► Service ─► Pod
```

| 호스트 | Listener | 인증서(istio-system) | HTTPRoute | 백엔드 |
|---|---|---|---|---|
| `home.awx.kr`, `www.home.awx.kr` | `http`, `https` | `istio-gateway-tls` | 앱별 | 테스트용, HTTP 허용 |
| `vault.awx.kr` | `https-vault` | `vault-gateway-tls` | `vault/vault` | `vault:8200` |
| `argocd.awx.kr` | `https-argocd` | `argocd-gateway-tls` | `argo-cd/argocd-server` | `argocd-server:80`(`server.insecure`) |
| `infralens.awx.kr` | `https-infralens` | `infralens-gateway-tls` | `infralens-test`·`infralens`의 HTTPRoute(InfraLens 쪽 관리) | InfraLens 앱·웹·Dex |

- `vault.awx.kr`, `argocd.awx.kr`, `infralens.awx.kr`는 :80 요청을 https로 301 리다이렉트합니다(`manifests/gateways/http-redirect.yaml`).
- 호스트 전용 listener는 그 앱의 네임스페이스 하나에서만 HTTPRoute를 받습니다(`allowedRoutes` Selector). `https-infralens`만 예외로 `infralens-test`(시험 설치, Dex)와 `infralens`(PoC 설치) 두 곳에서 받습니다. 두 곳의 라우트가 같은 경로를 잡으면 Gateway API 규칙에 따라 먼저 만든 라우트가 이깁니다.
- DNS A 레코드(hosting.co.kr)는 클러스터 안 Pod에서도 같은 주소로 풀립니다(CoreDNS → 노드 resolv.conf). Pod에서 LB IP로 나가는 연결은 Cilium이 Gateway Pod로 바로 보내므로, 앱 쪽 egress NetworkPolicy는 `ipBlock` 대신 istio-system의 Gateway Pod(`gateway.networking.k8s.io/gateway-name: istio-gateway`) :443을 허용해야 합니다.
- LB IP `192.168.50.201–220`은 비어 있습니다(풀 `home-pool`).

## 작업 흐름

1. 브랜치를 만들고 PR을 엽니다. `gitops-pr-reviewer` 에이전트가 리뷰하고 squash 머지합니다.
2. 머지 후 적용합니다. 명령은 레포 루트에서 실행합니다.
   - 새 Application 또는 Application 파일 변경: `kubectl apply -f cluster/home-k8s/argocd/applications/<app>.yaml`
   - 기존 앱의 values·매니페스트 변경: Argo CD가 main을 자동 동기화합니다.
   - Cilium·Argo CD (Helm CLI)
     ```bash
     helm upgrade cilium cilium/cilium -n kube-system --version 1.20.2 -f cluster/home-k8s/helm/cilium/values.yaml --force-conflicts --wait
     kubectl -n kube-system rollout restart ds/cilium     # ConfigMap만 바뀐 경우
     helm upgrade argocd argo/argo-cd -n argo-cd --version 10.10.5 -f cluster/home-k8s/helm/argocd/values.yaml --force-conflicts --wait
     ```
     버전을 올릴 때는 `--version`, values 파일 첫 줄 주석, 이 문서를 함께 바꿉니다. Argo CD 업그레이드는 Helm hook 대기 때문에 20분쯤 걸립니다.

## 처음부터 올릴 때

레포 루트에서 실행합니다(`C=cluster/home-k8s`).

1. Cilium: `helm install cilium cilium/cilium -n kube-system --version 1.20.2 -f $C/helm/cilium/values.yaml`
2. Argo CD: `helm install argocd argo/argo-cd -n argo-cd --create-namespace --version 10.10.5 -f $C/helm/argocd/values.yaml`
3. Application 등록 순서
   ```bash
   A=$C/argocd/applications
   kubectl apply -f $A/gateway-api-crds.yaml
   kubectl apply -f $A/cilium-lb.yaml
   kubectl apply -f $A/local-path-provisioner.yaml
   kubectl apply -f $A/cert-manager.yaml
   kubectl apply -f $A/cert-manager-issuers.yaml
   kubectl apply -f $A/istio-base.yaml
   kubectl apply -f $A/istio-cni.yaml
   kubectl apply -f $A/istiod-1-30-3.yaml
   kubectl apply -f $A/gateways.yaml
   kubectl apply -f $A/argocd-config.yaml
   kubectl apply -f $A/argo-rollouts.yaml
   kubectl apply -f $A/kyverno.yaml -f $A/kyverno-policies.yaml   # 정책은 엔진(CRD) 다음
   kubectl apply -f $C/argocd/repositories/deliveryhero-oci.yaml -f $A/node-local-dns.yaml   # Cilium localRedirectPolicies 필요
   kubectl apply -f $A/vault.yaml       # 이후 vault operator init + Secret vault-unseal-keys 생성
   kubectl apply -f $A/external-secrets.yaml   # Vault 설정(아래 "Vault" 절의 ESO 연동) 후
   kubectl apply -f $C/argocd/repositories/arc-oci.yaml -f $A/arc-controller.yaml
   kubectl apply -f $A/arc-infralens.yaml      # arc-controller Healthy 후, GitHub App 값을 Vault에 넣은 뒤(아래 "ARC" 절)
   kubectl apply -f $A/ci-cache.yaml           # worker-node-04에 taint·라벨을 붙인 뒤(아래 "CI 전용 노드")
   kubectl apply -f $A/infralens-poc.yaml      # 배포 키 Secret과 InfraLens 쪽 Secret·DB가 있은 뒤(아래 "InfraLens PoC" 절)
   kubectl apply -f $A/kube-state-metrics.yaml -f $A/metric-server.yaml -f $A/kube-prometheus-stack.yaml
   ```
4. 노드 설정: `$C/node-config/wifi-promisc/install.sh <SSH 호스트...>`

## 앱을 Gateway에 붙이기

```yaml
# 네임스페이스에 sidecar 주입 (Istio revision 1-30-3)
apiVersion: v1
kind: Namespace
metadata:
  name: my-app
  labels:
    istio.io/rev: 1-30-3
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
  namespace: my-app
spec:
  parentRefs:
    - name: istio-gateway
      namespace: istio-system
  hostnames: ["home.awx.kr"]
  rules:
    - backendRefs:
        - name: my-app
          port: 80
```

새 HTTPS 전용 호스트(`<이름>.awx.kr`)는 `manifests/gateways/`에 세 가지를 추가합니다.
- 전용 인증서 `certificate-<이름>.yaml`: `certificate-infralens.yaml`을 복사해 이름만 바꿉니다.
- `gateway.yaml`에 호스트별 listener를 추가합니다.
- `http-redirect.yaml`의 hostnames에 그 호스트를 넣습니다.

인증서 하나에 여러 호스트(`*.awx.kr` 등)를 넣어 listener들이 같이 쓰게 하지 않습니다. 브라우저가 HTTP/2 연결을 다른 호스트에도 재사용하는데, Istio Gateway는 처음 연결한 호스트(SNI) 기준으로 라우팅하므로 404가 납니다.

## 사설 CA 신뢰 등록 (브라우저 경고 없애기)

```bash
kubectl -n cert-manager get secret homelab-root-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > homelab-root-ca.crt
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain homelab-root-ca.crt   # macOS
```

## Argo CD

- 접속 `https://argocd.awx.kr`. CLI는 Gateway가 HTTP/1.1로 받으므로 `argocd login argocd.awx.kr --grpc-web`.
- 차트 10.x 기본값으로 컴포넌트별 NetworkPolicy(Ingress)가 생깁니다. argocd-server는 모든 출처 허용, redis·repo-server·dex는 Argo CD 내부에서만 접근합니다.
- v3.5부터 repo-server가 Helm v4로 차트를 렌더링합니다.
- Google 로그인: OIDC 직접 연동(Dex 미사용). OAuth 클라이언트는 GCP 프로젝트 `alex-space-0001`, 동의 화면 Testing(테스트 사용자만 로그인).
- client secret은 레포 밖 Secret `argo-cd/argocd-oidc-google`(키 `clientSecret`, 라벨 `app.kubernetes.io/part-of=argocd`)에 둡니다.
  ```bash
  kubectl -n argo-cd create secret generic argocd-oidc-google --from-literal=clientSecret="$(jq -r .web.client_secret client_secret_*.json)"
  kubectl -n argo-cd label secret argocd-oidc-google app.kubernetes.io/part-of=argocd
  ```
- RBAC: `policy.default`는 빈 값(권한 없음). 관리자는 `helm/argocd/values.yaml`의 `policy.csv`에 이메일로 추가합니다.

## Kyverno 정책 (Audit)

- 위반해도 막지 않고 PolicyReport만 남깁니다. 시스템 네임스페이스(kube-system, argo-cd, istio-system, cert-manager, kyverno 등)는 검사하지 않습니다.
  - admission: kyverno 앱의 webhook namespaceSelector / background 스캔: 각 정책의 `matchConditions`(차트 `vpolExclude`). ValidatingPolicy의 background 스캔에는 엔진 `resourceFilters`가 적용되지 않아 두 곳에 같은 목록을 둡니다.
- 정책: Pod Security Standards restricted(baseline 포함) 17개(`helm/kyverno-policies/values.yaml`) + 모범 사례 `disallow-latest-tag`, `require-requests-limits`(`manifests/kyverno-policies/`)
- 리포트 확인
  ```bash
  kubectl get policyreport -A                                  # 네임스페이스별 pass/fail 요약
  kubectl get policyreport -n <ns> -o yaml | yq '.results[] | select(.result=="fail") | [.policy, .resources[0].name, .message]'
  ```
- `failurePolicy: Ignore`: Kyverno webhook이 응답하지 못해도 Pod 생성은 통과합니다(Kyverno 장애가 클러스터 장애로 번지지 않게).
- 차단 전환은 정책 단위로 합니다: 차트 정책은 values의 `validationFailureActionByPolicy`, 직접 만든 정책은 `validationActions: [Deny]`.

## Vault

- 접속 `https://vault.awx.kr`. 로그인 방식 Userpass(관리자 정책 `admin`) 또는 Token.
- auth method, 정책, 사용자는 Vault API로 설정하며 레포에 없습니다. unseal key와 root token도 레포 밖에 보관합니다.
- External Secrets Operator 연동(Vault API로 설정, 레포 밖). 관리자 토큰으로 `vault-0`에서 실행합니다.
  ```bash
  vault secrets enable -path=secret -version=2 kv
  vault auth enable kubernetes
  vault write auth/kubernetes/config kubernetes_host=https://kubernetes.default.svc:443
  vault policy write eso-read - <<'EOP'
  path "secret/data/*"     { capabilities = ["read"] }
  path "secret/metadata/*" { capabilities = ["read", "list"] }
  EOP
  vault write auth/kubernetes/role/external-secrets \
    bound_service_account_names=external-secrets bound_service_account_namespaces=external-secrets \
    token_policies=eso-read token_ttl=1h token_max_ttl=4h
  ```

## External Secrets (Vault → Secret)

- 비밀값은 Vault `secret/`(KV v2)에 두고, 레포에는 어떤 값을 어떤 Secret으로 만들지만 적은 `ExternalSecret`을 둡니다.
- 저장소: `ClusterSecretStore/vault`(`manifests/external-secrets/`). ESO는 Vault 역할 `external-secrets`로 읽기만 합니다.
  ```yaml
  apiVersion: external-secrets.io/v1
  kind: ExternalSecret
  metadata:
    name: my-app
    namespace: my-app
  spec:
    refreshInterval: 1h
    secretStoreRef:
      kind: ClusterSecretStore
      name: vault
    target:
      name: my-app            # 만들어질 Secret 이름
    data:
      - secretKey: password   # Secret의 키
        remoteRef:
          key: my-app/db      # Vault secret/my-app/db
          property: password
  ```

## 자체 이미지

| 이미지 | Dockerfile | 빌드 | 쓰는 곳 |
|---|---|---|---|
| `ghcr.io/jangjaelee/arc-runner` (공개) | `images/arc-runner/` | `.github/workflows/arc-runner-image.yaml` | ARC 러너 |

- PR에서는 빌드와 도구 확인만, main에 머지되면 `<러너 버전>-<커밋 7자리>`와 `<러너 버전>` 태그로 push합니다. digest는 Actions 실행 요약에 나옵니다.
- `arc-runner`: 공식 `ghcr.io/actions/actions-runner`(Ubuntu 24.04, git·curl·jq·unzip·docker CLI·buildx)에 python3(+PyYAML)·ruby·helm 4·yq(mikefarah)·gcc·make·file·xz·zstd·zip을 더합니다. Go·Node는 워크플로의 setup 액션이 받습니다.
- 러너는 자동 업데이트 없이 돕니다. 새 러너 릴리스 후 30일 안에 `FROM`을 올려야 GitHub이 잡을 계속 보냅니다. Dependabot(`.github/dependabot.yml`)이 매주 `FROM` 갱신 PR을 엽니다. helm·yq 버전은 Dockerfile `ARG`(체크섬 포함)로 직접 올립니다.

## InfraLens PoC

`infralens` 네임스페이스의 InfraLens PoC를 Argo CD 앱 `infralens-poc`로 설치합니다. 릴리스된 제품을 GitOps로 설치하는 상황을 가정합니다. 처음에는 Helm CLI 릴리스 `infralens`(rev 9)로 설치했고, 2026-10-19에 Argo CD가 넘겨받았습니다.

- 차트는 `jangjaelee/infralens`(비공개)의 `deploy/helm/infralens`를 릴리스 태그(예: `v0.1.0`)로 고정합니다. 이미지(app·web·collector)는 차트 `appVersion`을 따르므로 `image.tag`를 두지 않습니다. 릴리스가 아닌 커밋으로 올려야 할 때는 `targetRevision`을 커밋으로 고정하고 `image.tag`를 values 파일이 아니라 Application의 `helm.parameters`에 둡니다.
- 업그레이드: Application 파일의 `targetRevision`(커밋일 때는 `image.tag`도)을 한 PR에서 바꾸고, 머지 뒤 `kubectl apply -f argocd/applications/infralens-poc.yaml`. apply 전까지는 옛 차트·옛 이미지 그대로라 둘이 어긋나는 때가 없습니다.
- 자동 sync(prune, selfHeal)입니다. values 파일의 다른 값은 머지되면 바로 반영됩니다.
- 차트 밖 리소스(`infralens-pg` StatefulSet·Service, DB·SSO·암호화·LLM Secret, `poc-*` Job)는 InfraLens 쪽이 관리하고 이 앱은 건드리지 않습니다. Dex(`/dex`)는 `infralens-test` 네임스페이스에 있습니다.
- AI 채팅(`llm.enabled`): API 키 Secret `infralens-llm-anthropic`·`infralens-llm-openai`(키 `api-key`)와 DB 계정 Secret `infralens-db-llm`(키 `url`)이 먼저 있어야 합니다. `llm.eval.enabled`를 켜면 주간 평가 CronJob `infralens-llm-eval`(일요일 05:00 KST)이 생깁니다. PoC는 비용 때문에 끄고 한도를 낮춰 둡니다(월 토큰 1,000,000, 사용자당 시간 10·하루 30회).
- 마이그레이션 Job(`infralens-migrate`, Helm 훅)은 Argo CD에서 PreSync 훅으로 sync할 때마다 돕니다.
- 저장소 인증: GitHub 배포 키(읽기 전용, 제목 `argocd-home-k8s`). 개인 키는 Secret `argo-cd/repo-infralens`에만 있고 레포에는 넣지 않습니다. 다시 만들 때는 아래처럼 합니다.

```bash
d=$(mktemp -d); ssh-keygen -q -t ed25519 -N '' -C argocd-home-k8s -f $d/id
kubectl -n argo-cd create secret generic repo-infralens --from-literal=type=git \
  --from-literal=url=git@github.com:jangjaelee/infralens.git --from-literal=project=default --from-file=sshPrivateKey=$d/id
kubectl -n argo-cd label secret repo-infralens argocd.argoproj.io/secret-type=repository
gh repo deploy-key add $d/id.pub --repo jangjaelee/infralens --title argocd-home-k8s   # --allow-write 없이
rm -rf $d
```

## ARC (GitHub Actions 러너)

Actions Runner Controller(러너 스케일 셋 모드)로 GitHub Actions self-hosted 러너를 둡니다. 지금은 `jangjaelee/infralens`(비공개) 저장소 전용 스케일 셋 하나입니다. InfraLens와 독립으로 이 레포에서만 운영합니다(InfraLens 저장소에는 ARC 매니페스트·자격 증명이 없습니다).

| 항목 | 값 |
|---|---|
| 컨트롤러 | 앱 `arc-controller`, ns `arc-systems`, `watchSingleNamespace: arc-runners`(ClusterRole 없음). 리스너 Pod도 여기 뜹니다 |
| 스케일 셋 | 앱 `arc-infralens`, ns `arc-runners`, 이름 **`arc-infralens`**(= 워크플로 `runs-on` 값), 저장소 단위 등록 |
| 러너 | ephemeral(잡 하나 후 삭제), min 0 / max 12, linux/amd64. Pod당 requests 3 CPU·4Gi, 메모리 limit 8Gi(runner 2 CPU·dind 1 CPU, 각각 2Gi / 4Gi) |
| 배치 | CI 전용 worker-node-04를 먼저 채우고(preferred nodeAffinity + taint toleration) 넘치면 일반 워커. node-04에는 CPU 기준 러너 5개(메모리도 20Gi로 들어감) |
| Go 캐시 | 노드 hostPath `/var/lib/ci-cache/go` → 러너 `/ci-cache/go`(`GOMODCACHE`·`GOCACHE`), `INFRALENS_CI_LOCAL_GO_CACHE=1`이면 워크플로가 setup-go 캐시를 끔. 잡 사이에 남음 |
| Docker 캐시 | 앱 `ci-cache`(ns `ci-cache`). dind dockerd `--registry-mirror=http://registry-mirror.ci-cache.svc.cluster.local:5000`, env `INFRALENS_CI_DOCKERHUB_MIRROR`(미러)·`INFRALENS_CI_BUILD_CACHE`(`build-cache.ci-cache.svc.cluster.local:5000`, BuildKit `type=registry`). HTTP·인증 없음, NetworkPolicy로 러너에서만 |
| Docker | DinD 네이티브 사이드카 `docker:29.9.1-dind`(privileged), `DOCKER_HOST=unix:///var/run/docker.sock`. `/var/lib/docker`는 emptyDir 40Gi(러너와 함께 삭제) |
| 이미지 | `ghcr.io/jangjaelee/arc-runner`(위 "자체 이미지") |
| 격리 | 권한 없는 SA + `automountServiceAccountToken: false`. NetworkPolicy `arc-runners`: 들어오는 연결 전부 차단, 나가는 연결은 DNS, ci-cache 레지스트리(TCP 5000), 공인 IP만(그 밖의 Pod·Service·노드·API 서버·집 LAN 불가) |
| 인증 | GitHub App(infralens 저장소에만 설치) → Vault `secret/arc-infralens/github-app` → ExternalSecret → Secret `arc-runners/arc-infralens-github-app` |

### GitHub App 준비 (처음 한 번, 레포 밖)

1. App 만들기: <https://github.com/settings/apps/new?name=arc-infralens-home-k8s&url=https://github.com/jangjaelee/k8s-gitops-monorepo&public=false&webhook_active=false&administration=write&metadata=read>
   (Repository permissions: Administration Read and write, Metadata Read-only / Webhook 끔 / Only on this account)
2. App 설정 페이지에서 App ID를 적고, Private keys → Generate a private key로 `.pem`을 받습니다.
3. Install App → Only select repositories → `jangjaelee/infralens`. 설치 후 주소 `.../settings/installations/<숫자>`의 숫자가 Installation ID입니다.
4. Vault에 넣습니다. UI(`https://vault.awx.kr` → `secret/` → Create secret, path `arc-infralens/github-app`)에서 키 `github_app_id`, `github_app_installation_id`, `github_app_private_key`(PEM 전체)를 넣거나 CLI로 넣습니다.
   ```bash
   kubectl -n vault exec -i vault-0 -- sh -c 'cat > /tmp/app.pem' < <받은 파일>.pem
   kubectl -n vault exec -it vault-0 -- sh
   vault login -method=userpass username=<관리자>
   vault kv put secret/arc-infralens/github-app github_app_id=<App ID> github_app_installation_id=<Installation ID> github_app_private_key=@/tmp/app.pem
   rm /tmp/app.pem
   ```
5. 받은 `.pem`은 Vault에 넣은 뒤 지웁니다. Administration 쓰기 권한이 있는 키라 레포·로컬에 남기지 않습니다.

### 확인

```bash
kubectl -n argo-cd get app arc-controller arc-infralens
kubectl -n arc-runners get externalsecret arc-infralens-github-app       # SecretSynced
kubectl -n arc-runners get autoscalingrunnerset arc-infralens
kubectl -n arc-systems get pods                                          # 컨트롤러 + arc-infralens-*-listener
kubectl -n arc-runners get ephemeralrunners,pods -w                      # 잡이 오면 러너 Pod 생성 → 끝나면 삭제
```

GitHub `jangjaelee/infralens` → Settings → Actions → Runners에 스케일 셋 `arc-infralens`가 보입니다. 워크플로는 `runs-on: arc-infralens`로 씁니다(InfraLens는 저장소 변수 `CI_RUNNER`).

### CI 전용 노드

worker-node-04(16 CPU·22Gi, 디스크 전체 456G·2026-10-20 여유 411G)는 러너 전용입니다. taint와 라벨은 Argo CD가 아니라 kubectl로 붙입니다(노드 객체는 레포로 관리하지 않습니다).

```bash
kubectl taint node worker-node-04 dedicated=ci:NoSchedule
kubectl label node worker-node-04 node-role.kubernetes.io/ci=
```

- DaemonSet(cilium, cilium-envoy, node-local-dns, istio-cni-node)은 모든 NoSchedule taint를 견뎌 이 노드에도 뜹니다. 새 DaemonSet을 넣을 때는 toleration을 확인합니다.
- taint는 NoSchedule이라 붙이기 전에 떠 있던 Pod는 남습니다. 러너 말고 다른 Pod가 남았으면 지워서 다른 노드로 보냅니다.
- taint와 라벨은 노드 객체에 남으므로 재부팅이나 kubelet 재시작에는 그대로입니다. 노드를 지우고 다시 join할 때만 다시 붙입니다. 이때 taint는 kubeadm `JoinConfiguration.nodeRegistration.taints`로 넣을 수 있지만, `node-role.kubernetes.io/*` 라벨은 kubelet이 스스로 붙일 수 없어(NodeRestriction) join 뒤 위 `kubectl label`을 다시 실행합니다. kubelet `config.yaml`의 `registerWithTaints`는 `kubeadm upgrade node`가 덮어쓰므로 쓰지 않습니다.
- Go 캐시 비우기: 그 노드에서 `sudo rm -rf /var/lib/ci-cache/go`(러너가 없을 때). 빌드 캐시(`build`)는 Go가 5일 안 쓴 항목을 스스로 지우고, 모듈 캐시(`mod`)는 쌓이기만 하니 디스크를 가끔 봅니다.
- Docker 캐시(`ci-cache`): 저장소는 node-04의 `/var/lib/ci-cache/registry-mirror`·`build-cache`이고, Service라 어느 노드의 러너든 씁니다. 미러는 받은 지 7일(`REGISTRY_PROXY_TTL`) 지나면 지우고, CronJob `ci-cache/cleanup`이 매일 05:00 KST에 디렉터리마다 40GiB를 넘으면 비웁니다. 미러는 Docker Hub(docker.io)만 캐시합니다(ghcr.io 제외). Docker Hub에는 여전히 익명으로 받습니다(공인 IP당 시간당 100회).

되돌리기:

1. 러너 배치·캐시: 이 설정을 넣은 PR을 revert합니다(Argo CD 자동 sync). 이후 러너는 일반 워커에만 뜨고 Actions 캐시를 다시 씁니다.
2. 노드: `kubectl taint node worker-node-04 dedicated=ci:NoSchedule-` / `kubectl label node worker-node-04 node-role.kubernetes.io/ci-`
3. Docker 캐시: 위 PR revert와 함께 `kubectl -n argo-cd delete app ci-cache`(네임스페이스는 남으니 `kubectl delete ns ci-cache`).
4. 캐시 디렉터리는 노드마다 `sudo rm -rf /var/lib/ci-cache`.

### 운영

- 러너 이미지 갱신: Dependabot의 `FROM` PR 머지 → 이미지 빌드 → Actions 실행 요약의 태그·digest로 `helm/arc-infralens/values.yaml`의 `runnerImage` 앵커를 바꾸는 PR. 새 러너 릴리스 후 30일 안에 끝내야 잡을 계속 받습니다.
- ARC 업그레이드: 컨트롤러와 스케일 셋의 차트 버전이 같아야 합니다. `arc-infralens` 앱 삭제(리스너·러너 정리 확인) → `arc-controller` `targetRevision`·values 첫 줄·컨트롤러 이미지 `image.tag`(digest)·이 문서 변경 → `arc-infralens`를 같은 버전으로 다시 등록.
- 삭제 순서: `arc-infralens` → `arc-controller`. 스케일 셋 리소스의 finalizer를 컨트롤러가 풀어야 합니다.
- **InfraLens를 공개로 바꾸기 전에** `arc-infralens` 앱을 지우고 저장소 변수 `CI_RUNNER`를 비웁니다. 공개 저장소의 fork PR이 self-hosted 러너에서 돌 수 있습니다.
- dind는 privileged라 잡 코드가 노드 root 권한을 얻을 수 있습니다. 비공개 저장소의 신뢰하는 코드만 돌립니다. Kyverno PSS 정책은 Audit이라 막지 않고, `arc-runners` PolicyReport에 fail로 남습니다.
- Docker Hub 익명 pull 한도: 러너는 매번 새로 떠서 이미지 캐시가 없고, 모든 pull이 집 공인 IP 하나에서 나갑니다. 한도에 걸리면 워크플로에서 `docker login`을 하거나 pull-through 캐시를 둡니다(미구성).

## 알려진 제약

- **Wi-Fi 노드와 L2 announcement**: worker-01/02(Broadcom `brcmfmac`)는 promiscuous 모드가 꺼져 있으면 LB IP의 ARP 요청을 받지 못해, 모든 노드에 `wifi-promisc.service`를 둡니다(`node-config/wifi-promisc/`).
- **iwlwifi 노드와 L2 announcement**: master·worker-03(Intel `iwlwifi`)은 주기 Wi-Fi 스캔 때문에 Cilium 장치 정보가 망가져 lease를 잡으면 LB IP가 응답하지 않았습니다. 두 노드의 Wi-Fi를 한 AP에 고정해 해결했습니다(`node-config/wifi-bssid-lock/`, 로밍 안 함).
- 사설 CA 인증서이므로 CA를 신뢰 등록하지 않은 기기에서는 인증서 경고가 납니다.
