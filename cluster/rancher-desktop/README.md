# rancher-desktop

로컬 Mac의 Rancher Desktop(k3s) 클러스터 `rancher-desktop`의 플랫폼 구성요소 명세입니다. 이 폴더에는 이 클러스터에 배포하는 모든 것을 둡니다.
home-k8s(`cluster/home-k8s/`)와 같은 구성을 로컬 단일 노드에 맞게 줄였습니다. kubectl context 이름도 `rancher-desktop`입니다.
구성요소의 버전이나 Argo CD Application이 바뀌면 **같은 PR에서 이 문서도 갱신합니다**(리뷰 에이전트 검사 9번).

> 이 폴더 안 파일 주석에 적은 경로(`helm/...`, `manifests/...`, `argocd/applications/...`)는 이 폴더 기준입니다.
> Application의 `path`와 `$values` 경로는 레포 루트 기준(`cluster/rancher-desktop/...`)입니다.

## 클러스터

| 항목 | 값 |
|---|---|
| 구성 | Rancher Desktop(Lima VM), k3s 단일 노드 `lima-rancher-desktop`, Alpine Linux 3.23, **arm64**, 6 CPU·16Gi |
| Kubernetes | v1.36.5+k3s1 (k3s 옵션 `--disable traefik --docker`) |
| 컨테이너 런타임 | docker 29.1.3 (Rancher Desktop moby, k3s 내장 cri-dockerd) |
| CNI | Flannel VXLAN(k3s 기본), kube-proxy, Pod CIDR `10.42.0.0/16` |
| GitOps | Argo CD v3.5.5 (chart argo-cd 10.10.5, `https://argocd.awx.kr`, Google 로그인) |
| Service mesh | Istio 1.30.3 sidecar 모드 + istio-cni, revision `1-30-3`(tag `default`) |
| Ingress | Gateway API v1.5.1 (Istio 구현), Gateway `istio-system/istio-gateway`, k3s ServiceLB |
| 인증서 | cert-manager v1.20.2 + 사설 CA(`ClusterIssuer/homelab-ca`) |
| 스토리지 | k3s 기본 local-path-provisioner (기본 StorageClass `local-path`, reclaim Delete) |
| 비밀값 | Kubernetes Secret을 kubectl로 직접 만듭니다(Vault·External Secrets 미사용) |

### k3s 기본 구성요소 (레포 미관리)

k3s가 `/var/lib/rancher/k3s/server/manifests/`로 직접 설치·관리합니다. Argo CD 앱으로 같은 것을 다시 설치하지 않습니다(StorageClass `local-path`, APIService `v1beta1.metrics.k8s.io`가 충돌함).

| 구성요소 | 네임스페이스 | 비고 |
|---|---|---|
| CoreDNS | kube-system | 사용자 설정은 ConfigMap `coredns-custom`(`manifests/gateways/coredns-custom.yaml`) |
| local-path-provisioner | kube-system | 기본 StorageClass `local-path`. 데이터는 VM 안 `/var/lib/rancher/k3s/storage` |
| metrics-server | kube-system | `kubectl top` |
| ServiceLB(Klipper) | kube-system | LoadBalancer Service마다 `svclb-*` DaemonSet이 노드 포트를 엽니다 |
| Traefik | — | **꺼 둡니다**(Rancher Desktop 설정 Kubernetes → Traefik 끔). 켜면 :80/:443을 먼저 차지해 Istio Gateway Service가 Pending이 됩니다 |

## 폴더 구성

```
cluster/rancher-desktop/
├── README.md                  # 이 문서 (구성요소·버전·Application 명세)
├── argocd/
│   └── applications/          # Argo CD Application (kubectl apply로 등록)
├── helm/<release>/            # Helm values (Argo CD multi-source의 $values 또는 Helm CLI)
└── manifests/<app>/           # Helm이 아닌 매니페스트 (path 소스 Application)
```

## 구성요소 명세

### Helm CLI로 관리 (Argo CD 미관리)

Argo CD가 망가져도 Argo CD 없이 복구할 수 있게 Helm CLI로 직접 적용합니다.

| Release | 네임스페이스 | 차트 | 앱 버전 | values |
|---|---|---|---|---|
| argocd | argo-cd | argo/argo-cd 10.10.5 | v3.5.5 | `helm/argocd/values.yaml` |

### Argo CD Application

모든 앱: `metadata.namespace: argo-cd`, automated sync(prune, selfHeal), `ServerSideApply=true`.

| Application | Project | 네임스페이스 | 소스(차트·버전 / 경로) | 앱 버전 | 이 레포의 values·매니페스트 | 비고 |
|---|---|---|---|---|---|---|
| gateway-api-crds | system | (cluster) | github.com/kubernetes-sigs/gateway-api `config/crd/standard` @ v1.5.1 | v1.5.1 | — | prune 끔 |
| cert-manager | system | cert-manager | jetstack/cert-manager v1.20.2 | v1.20.2 | `helm/cert-manager/values.yaml` | `crds.enabled`, `crds.keep` |
| cert-manager-issuers | system | cert-manager | 이 레포 path @ main | — | `manifests/cert-manager-issuers/` | 사설 CA `homelab-ca` |
| istio-base | system | istio-system | istio/base 1.30.3 | 1.30.3 | `helm/istio-base/values.yaml` | `defaultRevision: 1-30-3` |
| istio-cni | system | istio-system | istio/cni 1.30.3 | 1.30.3 | `helm/istio-cni/values.yaml` | Flannel 체이닝, `global.platform: k3s` |
| istiod-1-30-3 | system | istio-system | istio/istiod 1.30.3 | 1.30.3 | `helm/istiod-1-30-3/values.yaml` | revision `1-30-3`, tag `default`, HPA min 1(PDB 없음) |
| gateways | system | istio-system | 이 레포 path @ main | proxyv2 1.30.3 | `manifests/gateways/` | Gateway(레플리카 1), 인증서, HTTP→HTTPS 리다이렉트, CoreDNS `coredns-custom`(kube-system) |
| argocd-config | system | argo-cd | 이 레포 path @ main | — | `manifests/argocd/` | HTTPRoute `argocd.awx.kr` |
| argo-rollouts | system | argo-rollouts | argo/argo-rollouts 2.43.8 | v1.10.1 | `helm/argo-rollouts/values.yaml` | Gateway API 플러그인 v0.17.0(linux-arm64) |
| kyverno | system | kyverno | kyverno/kyverno 3.9.1 | v1.19.1 | `helm/kyverno/values.yaml` | 엔진, `ServerSideDiff=true` |
| kyverno-policies | system | kyverno | kyverno/kyverno-policies 3.9.1 + 이 레포 path | v1.19.1 | `helm/kyverno-policies/values.yaml`, `manifests/kyverno-policies/` | PSS restricted 17개 + 모범 사례 2개, **모두 Audit**, `ServerSideDiff=true` |
| infralens-dex | default | infralens-test | 이 레포 path @ main | Dex v2.45.1 | `manifests/infralens-dex/` | InfraLens 로그인 IdP, issuer `https://infralens.awx.kr/dex`, memory storage |
| infralens-poc | default | infralens | github.com/jangjaelee/infralens(비공개) `deploy/helm/infralens` @ 88dc0a5 | sha-88dc0a5 (ghcr.io/jangjaelee) | `helm/infralens-poc/values.yaml` | InfraLens PoC, 배포 키 필요, AI 채팅은 사용자 키(BYOK)만(아래 "InfraLens PoC" 절) |
| kube-state-metrics | system | kube-system | prometheus-community/kube-state-metrics 7.4.0 | v2.19.0 | 기본값 | |
| kube-prometheus-stack | o11y | prometheus-operator | prometheus-community/kube-prometheus-stack 84.1.0 | operator v0.90.1 | `helm/prometheus-operator/values.yaml` | operator만(Prometheus·Grafana·Alertmanager 끔) |

### Argo CD 저장소 등록

| 파일 | 저장소 | 용도 |
|---|---|---|
| (레포에 없음) Secret `argo-cd/repo-infralens` | `git@github.com:jangjaelee/infralens.git` (비공개, 읽기 전용 배포 키) | InfraLens 차트. 개인 키가 들어 있어 클러스터에서 직접 만든다 |

## 외부 노출

모든 외부 접속은 Istio Gateway 하나로 들어옵니다. 호스트 이름은 home-k8s와 같은 `*.awx.kr`이고, Mac의 `/etc/hosts`에 `127.0.0.1`로 등록합니다.

```
브라우저(Mac) ──► 127.0.0.1:80/443 (/etc/hosts)
                   └─► Rancher Desktop 포트 포워딩(Mac → VM)
                        └─► svclb-istio-gateway-istio (k3s ServiceLB, 노드 :80/:443)
                             └─► Service istio-system/istio-gateway-istio (LoadBalancer, Istio 자동 생성)
                                  └─► Gateway istio-system/istio-gateway  (:80 HTTP, :443 HTTPS, 호스트별 listener)
                                       └─► HTTPRoute ─► Service ─► Pod
```

```
# /etc/hosts (Mac). home-k8s용 *.awx.kr 항목은 주석 처리해 둔다
127.0.0.1 argocd.awx.kr infralens.awx.kr home.awx.kr www.home.awx.kr
```

| 호스트 | Listener | 인증서(istio-system) | HTTPRoute | 백엔드 |
|---|---|---|---|---|
| `home.awx.kr`, `www.home.awx.kr` | `http`, `https` | `istio-gateway-tls` | 앱별 | 테스트용, HTTP 허용 |
| `argocd.awx.kr` | `https-argocd` | `argocd-gateway-tls` | `argo-cd/argocd-server` | `argocd-server:80`(`server.insecure`) |
| `infralens.awx.kr` | `https-infralens` | `infralens-gateway-tls` | `infralens-test`·`infralens`의 HTTPRoute(InfraLens 쪽 관리) | InfraLens 앱·웹·Dex |

- `argocd.awx.kr`, `infralens.awx.kr`는 :80 요청을 https로 301 리다이렉트합니다(`manifests/gateways/http-redirect.yaml`).
- 호스트 전용 listener는 그 앱의 네임스페이스 하나에서만 HTTPRoute를 받습니다(`allowedRoutes` Selector). `https-infralens`만 예외로 `infralens-test`(시험 설치, Dex)와 `infralens`(PoC 설치) 두 곳에서 받습니다. 두 곳의 라우트가 같은 경로를 잡으면 Gateway API 규칙에 따라 먼저 만든 라우트가 이깁니다.
- **Pod 안 이름 풀이**: Mac의 `/etc/hosts`는 Pod에 보이지 않습니다. 그대로 두면 Pod에서 `*.awx.kr`은 공인 DNS를 거쳐 home-k8s로 갑니다. 그래서 CoreDNS `coredns-custom`(`manifests/gateways/coredns-custom.yaml`)이 `argocd.awx.kr`·`infralens.awx.kr`을 `istio-gateway-istio.istio-system.svc.cluster.local`로 바꿔 풉니다(예: InfraLens 앱 → OIDC issuer `https://infralens.awx.kr/dex`).
- 앱 쪽 egress NetworkPolicy는 istio-system의 Gateway Pod(`gateway.networking.k8s.io/gateway-name: istio-gateway`) :443을 허용해야 합니다.
- Gateway Pod는 1개입니다(HPA·PDB 없음). Pod가 다시 뜨는 동안 접속이 끊깁니다.

## 작업 흐름

1. 브랜치를 만들고 PR을 엽니다. `gitops-pr-reviewer` 에이전트가 리뷰하고 squash 머지합니다.
2. 머지 후 적용합니다. 명령은 레포 루트에서 `rancher-desktop` context로 실행합니다(`kubectl config use-context rancher-desktop`).
   - 새 Application 또는 Application 파일 변경: `kubectl apply -f cluster/rancher-desktop/argocd/applications/<app>.yaml`
   - 기존 앱의 values·매니페스트 변경: Argo CD가 main을 자동 동기화합니다.
   - Argo CD (Helm CLI)
     ```bash
     helm upgrade argocd argo/argo-cd -n argo-cd --version 10.10.5 -f cluster/rancher-desktop/helm/argocd/values.yaml --force-conflicts --wait
     ```
     버전을 올릴 때는 `--version`, values 파일 첫 줄 주석, 이 문서를 함께 바꿉니다.

## 처음부터 올릴 때

레포 루트에서 실행합니다(`C=cluster/rancher-desktop`, context `rancher-desktop`).

0. Rancher Desktop: Kubernetes 켬, Traefik 끔. Mac `/etc/hosts`에 위 "외부 노출"의 항목을 넣습니다.
1. TLS 검사 프록시가 있는 네트워크면 ConfigMap `custom-ca-certs`를 먼저 만듭니다(아래 "TLS 검사 프록시").
   Argo CD: `helm install argocd argo/argo-cd -n argo-cd --create-namespace --version 10.10.5 -f $C/helm/argocd/values.yaml`
2. Google 로그인 client secret(아래 "Argo CD" 절)과 AppProject `system`·`o11y`
   ```bash
   for p in system o11y; do
   kubectl apply -f - <<EOF
   apiVersion: argoproj.io/v1alpha1
   kind: AppProject
   metadata:
     name: $p
     namespace: argo-cd
   spec:
     sourceRepos: ['*']
     destinations: [{server: https://kubernetes.default.svc, namespace: '*'}]
     clusterResourceWhitelist: [{group: '*', kind: '*'}]
   EOF
   done
   ```
3. Application 등록 순서
   ```bash
   A=$C/argocd/applications
   kubectl apply -f $A/gateway-api-crds.yaml
   kubectl apply -f $A/cert-manager.yaml
   kubectl apply -f $A/cert-manager-issuers.yaml
   kubectl apply -f $A/istio-base.yaml
   kubectl apply -f $A/istio-cni.yaml
   kubectl apply -f $A/istiod-1-30-3.yaml
   kubectl apply -f $A/gateways.yaml
   kubectl apply -f $A/argocd-config.yaml
   kubectl apply -f $A/argo-rollouts.yaml
   kubectl apply -f $A/kyverno.yaml -f $A/kyverno-policies.yaml   # 정책은 엔진(CRD) 다음
   kubectl apply -f $A/infralens-dex.yaml      # Secret dex-secrets를 만든 뒤(아래 "InfraLens PoC" 절)
   kubectl apply -f $A/infralens-poc.yaml      # 배포 키 Secret과 InfraLens 쪽 Secret·DB가 있은 뒤(아래 "InfraLens PoC" 절)
   kubectl apply -f $A/kube-state-metrics.yaml -f $A/kube-prometheus-stack.yaml
   ```
4. 확인
   ```bash
   kubectl -n argo-cd get app
   kubectl -n istio-system get svc istio-gateway-istio          # EXTERNAL-IP가 노드 IP(Pending 아님)
   curl -skI https://argocd.awx.kr | head -1                     # Mac에서
   kubectl run dnstest --rm -it --restart=Never --image=busybox:1.37 -- nslookup infralens.awx.kr   # 10.43.x.x(Gateway ClusterIP)
   ```

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

새 HTTPS 전용 호스트(`<이름>.awx.kr`)는 `manifests/gateways/`에 네 가지를 추가합니다.
- 전용 인증서 `certificate-<이름>.yaml`: `certificate-infralens.yaml`을 복사해 이름만 바꿉니다.
- `gateway.yaml`에 호스트별 listener를 추가합니다.
- `http-redirect.yaml`의 hostnames에 그 호스트를 넣습니다.
- Pod에서도 부를 호스트면 `coredns-custom.yaml`에 rewrite 줄을 넣습니다.

Mac `/etc/hosts`에도 그 호스트를 `127.0.0.1`로 넣습니다.

인증서 하나에 여러 호스트(`*.awx.kr` 등)를 넣어 listener들이 같이 쓰게 하지 않습니다. 브라우저가 HTTP/2 연결을 다른 호스트에도 재사용하는데, Istio Gateway는 처음 연결한 호스트(SNI) 기준으로 라우팅하므로 404가 납니다.

## TLS 검사 프록시

이 Mac이 붙는 네트워크의 TLS 검사 프록시가 일부 외부 사이트 인증서를 자체 CA로 바꿔 내보냅니다. Mac과 VM의 dockerd는 Rancher Desktop이 Mac 키체인 CA를 넣어 줘서 이미지 pull이 되지만, **Pod 안은 그 CA를 모릅니다**.

| 영향 | 사이트(2026-10-22 확인) | 대응 |
|---|---|---|
| Argo CD repo-server Helm 차트 받기 | `charts.jetstack.io`, `argoproj.github.io`, `kyverno.github.io`, `prometheus-community.github.io` | `helm/argocd/values.yaml` `repoServer.volumes` |
| argo-rollouts 플러그인 받기 | `release-assets.githubusercontent.com` | `helm/argo-rollouts/values.yaml` `controller.volumes` |
| InfraLens AWS 연결 확인·수집 | `sts.amazonaws.com`, `sts.us-east-1`, `ec2.us-east-1`, `rds.ap-northeast-2` 등(엔드포인트마다 다름) | Kyverno `MutatingPolicy` `inject-custom-ca`(`manifests/kyverno-policies/custom-ca.yaml`) + 네임스페이스 라벨 |

영향 없음: github.com, Istio 차트(GCS), Google 로그인, GCP API(`*.googleapis.com`), docker.io·ghcr.io, LLM API.

values는 ConfigMap `custom-ca-certs`(키 `custom-ca.crt`)를 `/etc/ssl/certs/custom-ca.crt`로 마운트합니다(`optional: true`, 없으면 기본 CA만). Go 프로그램은 `/etc/ssl/certs` 안 파일을 모두 읽어 신뢰합니다. **CA 인증서는 레포에 넣지 않고** 클러스터에만 만듭니다. 프록시 CA의 중간·루트 인증서를 Mac 시스템 키체인에서 꺼내 한 파일(PEM)로 합칩니다.

```bash
# <프록시 CA 이름>: 키체인 접근 → 시스템 키체인에서 확인. 체인 전체(중간 + 루트)를 넣는다
security find-certificate -a -c "<프록시 CA 이름>" -p /Library/Keychains/System.keychain > custom-ca.crt
echo | openssl s_client -connect charts.jetstack.io:443 -servername charts.jetstack.io -CAfile custom-ca.crt 2>/dev/null | grep 'Verify return code'   # 0 (ok)
for ns in argo-cd argo-rollouts infralens; do
  kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n $ns create configmap custom-ca-certs --from-file=custom-ca.crt --dry-run=client -o yaml | kubectl apply -f -
done
kubectl -n argo-cd rollout restart deploy/argocd-repo-server   # ConfigMap을 바꾼 뒤(subPath 마운트는 자동 갱신 안 됨)
```

차트에 볼륨을 더할 수 없는 앱(InfraLens)은 Kyverno `MutatingPolicy` `inject-custom-ca`가 넣습니다. 네임스페이스에 라벨을 붙이면 그 뒤에 만드는 Pod에 같은 ConfigMap을 `/etc/ssl/certs/custom-ca.crt`로 마운트합니다(Pod 생성 때만, Deployment 템플릿은 그대로라 Argo CD 차이 없음). 이미 떠 있는 Pod는 재시작해야 반영됩니다.

```bash
kubectl label namespace infralens custom-ca-certs/inject=true
kubectl -n infralens rollout restart deploy/infralens-app deploy/infralens-kube-gateway   # 수집 CronJob은 다음 실행부터
```

프록시가 없는 네트워크에서는 ConfigMap이 있어도 해가 없습니다.

## 사설 CA 신뢰 등록 (브라우저 경고 없애기)

이 클러스터의 `homelab-ca`는 home-k8s와 다른 CA입니다(cert-manager가 클러스터마다 새로 만듦). 두 클러스터를 오가면 둘 다 신뢰 등록합니다.

```bash
kubectl --context rancher-desktop -n cert-manager get secret homelab-root-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > homelab-root-ca-rancher-desktop.crt
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain homelab-root-ca-rancher-desktop.crt   # macOS
```

## Argo CD

- 접속 `https://argocd.awx.kr`. CLI는 Gateway가 HTTP/1.1로 받으므로 `argocd login argocd.awx.kr --grpc-web`.
- 차트 10.x 기본값으로 컴포넌트별 NetworkPolicy(Ingress)가 생깁니다. argocd-server는 모든 출처 허용, redis·repo-server·dex는 Argo CD 내부에서만 접근합니다. k3s는 내장 network policy controller로 NetworkPolicy를 적용합니다.
- v3.5부터 repo-server가 Helm v4로 차트를 렌더링합니다.
- Google 로그인: OIDC 직접 연동(Dex 미사용). home-k8s와 같은 OAuth 클라이언트(GCP 프로젝트 `alex-space-0001`, 동의 화면 Testing)를 씁니다. 호스트 이름이 같아 redirect URI `https://argocd.awx.kr/auth/callback`을 따로 추가하지 않습니다.
- client secret은 레포 밖 Secret `argo-cd/argocd-oidc-google`(키 `clientSecret`, 라벨 `app.kubernetes.io/part-of=argocd`)에 둡니다.
  ```bash
  kubectl -n argo-cd create secret generic argocd-oidc-google --from-literal=clientSecret="$(jq -r .web.client_secret client_secret_*.json)"
  kubectl -n argo-cd label secret argocd-oidc-google app.kubernetes.io/part-of=argocd
  ```
- RBAC: `policy.default`는 빈 값(권한 없음). 관리자는 `helm/argocd/values.yaml`의 `policy.csv`에 이메일로 추가합니다.

## Kyverno 정책 (Audit)

- 위반해도 막지 않고 PolicyReport만 남깁니다. 시스템 네임스페이스(kube-system, kube-public, kube-node-lease, argo-cd, istio-system, cert-manager, kyverno)는 검사하지 않습니다.
  - admission: kyverno 앱의 webhook namespaceSelector / background 스캔: 각 정책의 `matchConditions`(차트 `vpolExclude`). ValidatingPolicy의 background 스캔에는 엔진 `resourceFilters`가 적용되지 않아 두 곳에 같은 목록을 둡니다.
- 정책: Pod Security Standards restricted(baseline 포함) 17개(`helm/kyverno-policies/values.yaml`) + 모범 사례 `disallow-latest-tag`, `require-requests-limits`(`manifests/kyverno-policies/`)
- 리포트 확인
  ```bash
  kubectl get policyreport -A                                  # 네임스페이스별 pass/fail 요약
  kubectl get policyreport -n <ns> -o yaml | yq '.results[] | select(.result=="fail") | [.policy, .resources[0].name, .message]'
  ```
- `failurePolicy: Ignore`: Kyverno webhook이 응답하지 못해도 Pod 생성은 통과합니다(Kyverno 장애가 클러스터 장애로 번지지 않게).
- 차단 전환은 정책 단위로 합니다: 차트 정책은 values의 `validationFailureActionByPolicy`, 직접 만든 정책은 `validationActions: [Deny]`.

## 비밀값 (Kubernetes Secret)

로컬 클러스터라 Vault·External Secrets를 두지 않습니다. 비밀값은 `kubectl create secret`으로 직접 만들고 **레포에는 넣지 않습니다**. 레포의 values·매니페스트는 Secret 이름(`existingSecret` 등)만 가리킵니다.

| Secret | 키 | 쓰는 곳 |
|---|---|---|
| `argo-cd/argocd-oidc-google` | `clientSecret` | Argo CD Google 로그인 |
| `argo-cd/repo-infralens` | `sshPrivateKey` 등 | InfraLens 차트 저장소(아래) |
| `infralens/infralens-*` | 아래 "InfraLens PoC" 표 | InfraLens PoC |
| `infralens-test/dex-secrets` | `INFRALENS_CLIENT_SECRET`, `ADMIN_PASSWORD_HASH` | Dex(아래) |

Rancher Desktop에서 "Reset Kubernetes"를 하면 Secret도 지워지므로 다시 만듭니다.

## InfraLens PoC

`infralens` 네임스페이스의 InfraLens PoC를 Argo CD 앱 `infralens-poc`로 설치합니다. 릴리스된 제품을 GitOps로 설치하는 상황을 가정합니다. 차트·이미지 고정 방식은 home-k8s와 같습니다(`cluster/home-k8s/README.md` "InfraLens PoC").

- 차트는 `jangjaelee/infralens`(비공개)의 `deploy/helm/infralens`를 릴리스 태그(예: `v0.1.0`)로 고정합니다. 커밋으로 올릴 때는 `targetRevision`을 커밋으로, `image.tag`를 Application의 `helm.parameters`에 둡니다.
- 업그레이드: Application 파일의 `targetRevision`(커밋일 때는 `image.tag`도)을 한 PR에서 바꾸고, 머지 뒤 `kubectl apply -f cluster/rancher-desktop/argocd/applications/infralens-poc.yaml`.
- 이미지는 `linux/amd64`·`linux/arm64` 멀티 아키텍처라 노드(arm64)에서 네이티브로 돕니다(`sha-cdbdf87`부터, InfraLens `publish-arm64` 워크플로). amd64 전용 태그로 되돌리면 QEMU 에뮬레이션에서 Steampipe가 plugin manager를 찾지 못해(`/proc/<pid>/exe`가 `qemu-x86_64`) 클라우드 수집이 모두 실패합니다. 태그를 올리기 전에 `docker buildx imagetools inspect ghcr.io/jangjaelee/infralens-collector:<태그>`로 arm64가 있는지 확인합니다.
- 설치 전에 만들 것(차트 밖, 레포에 넣지 않음). 순서대로 만듭니다.

  | 준비물 | 키 | 만드는 법 |
  |---|---|---|
  | PostgreSQL `infralens-pg`, Secret `infralens-db-app`·`-loader`·`-migrator` | `url` | InfraLens 레포 `planning/private/poc/setup-db.sh`(context를 `rancher-desktop`으로 바꿔 실행) |
  | Secret `infralens-db-llm` | `url` | role `infralens_llm_ro`에 비밀번호를 주고 같은 형식의 URL로(AI 채팅) |
  | Secret `infralens-encryption` | `active`, `k1` | `--from-literal=active=k1 --from-literal=k1="$(openssl rand -base64 32)"`. BYOK 사용자 키 암호화에도 씀 |
  | Secret `infralens-sso` | `client-secret` | Dex `INFRALENS_CLIENT_SECRET`과 같은 값 |
  | Secret `infralens-gw-ca` | `ca.crt` | 이 클러스터 사설 CA(`cert-manager/homelab-root-ca`의 `ca.crt`). home-k8s CA가 아님 |
  | Secret `infralens-test/dex-secrets` | `INFRALENS_CLIENT_SECRET`, `ADMIN_PASSWORD_HASH` | 아래 "Dex" |

- **AI 채팅은 사용자 키(BYOK)만 씁니다**(`llm.byok`, `orgKeyFallback: false`). 조직 키 Secret(`infralens-llm-anthropic`·`-openai`)은 두지 않습니다. 로그인한 사용자가 화면에서 자기 Anthropic·OpenAI 키를 넣고, 키는 `infralens-encryption`으로 암호화해 최대 30일 보관합니다. 키가 없는 사용자는 채팅을 쓰지 못합니다.
- **Dex**(앱 `infralens-dex`, ns `infralens-test`): `https://infralens.awx.kr/dex`. 정적 사용자 `admin`(이메일 `admin@infralens.local`, userID `00000000-0000-0000-0000-000000000001` = values `adminSubjects`의 관리자). memory storage라 Dex가 재시작하면 다시 로그인합니다. 설정(`manifests/infralens-dex/config.yaml`)을 바꾸면 `dex.yaml`의 `checksum/config` 값도 바꿔 재시작시킵니다.
  ```bash
  CS=$(openssl rand -hex 24)                                   # 클라이언트 secret (Dex와 infralens-sso에 같은 값)
  HASH=$(htpasswd -nbBC 10 "" '<관리자 비밀번호>' | tr -d ':\n')   # bcrypt
  kubectl create namespace infralens-test --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n infralens-test create secret generic dex-secrets --from-literal=INFRALENS_CLIENT_SECRET="$CS" --from-literal=ADMIN_PASSWORD_HASH="$HASH"
  kubectl -n infralens create secret generic infralens-sso --from-literal=client-secret="$CS"
  unset CS HASH
  ```
- `app.trustedProxyCIDRs`는 k3s Pod CIDR `10.42.0.0/16`입니다.
- 마이그레이션 Job(`infralens-migrate`, Helm 훅)은 Argo CD에서 PreSync 훅으로 sync할 때마다 돕니다.
- 저장소 인증: GitHub 배포 키(읽기 전용, 제목 `argocd-rancher-desktop`). home-k8s와 다른 키를 씁니다. 개인 키는 Secret `argo-cd/repo-infralens`에만 두고 레포에는 넣지 않습니다.

```bash
d=$(mktemp -d); ssh-keygen -q -t ed25519 -N '' -C argocd-rancher-desktop -f $d/id
kubectl -n argo-cd create secret generic repo-infralens --from-literal=type=git \
  --from-literal=url=git@github.com:jangjaelee/infralens.git --from-literal=project=default --from-file=sshPrivateKey=$d/id
kubectl -n argo-cd label secret repo-infralens argocd.argoproj.io/secret-type=repository
gh repo deploy-key add $d/id.pub --repo jangjaelee/infralens --title argocd-rancher-desktop   # --allow-write 없이
rm -rf $d
```

## 알려진 제약

- **단일 노드**: istiod·Gateway·Argo CD 등 모두 레플리카 1이라 Pod 재시작이나 VM 재시작 동안 서비스가 끊깁니다. PDB를 두지 않습니다.
- **자원**: 6 CPU·16Gi를 모든 구성요소가 나눠 씁니다. 부족하면 Rancher Desktop 설정(Virtual Machine → Memory/CPUs)에서 늘립니다.
- **arm64**: 새 구성요소·자체 이미지·플러그인 바이너리(argo-rollouts처럼 아키텍처별 파일을 받는 것)는 arm64용인지 확인합니다. amd64 전용 이미지는 QEMU 에뮬레이션으로 돌지만 느리고, Steampipe처럼 자기 프로세스를 `/proc/<pid>/exe`로 확인하는 프로그램은 동작하지 않습니다.
- **호스트 이름 공유**: home-k8s와 같은 `*.awx.kr`을 쓰므로 Mac에서는 `/etc/hosts`로 어느 클러스터에 붙을지 정합니다. 이 Mac에서 home-k8s에 접속하려면 항목을 다시 주석 처리합니다.
- **Rancher Desktop Reset**: "Reset Kubernetes"는 클러스터를 새로 만듭니다. "처음부터 올릴 때"를 다시 하고 Secret·사설 CA 신뢰 등록도 다시 합니다.
- 사설 CA 인증서이므로 CA를 신뢰 등록하지 않은 기기에서는 인증서 경고가 납니다.
