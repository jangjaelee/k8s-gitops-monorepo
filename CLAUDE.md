# k8s-gitops-monorepo

집 홈랩 Kubernetes 클러스터(kubeadm 4노드, Cilium 1.20.2, Argo CD v3.3.8)의 Helm values와 매니페스트를 모두 이 레포로 관리한다.
클러스터 운영 메모(노드, 접속, 작업 이력)는 로컬 `~/Workspace/Alex/my-k8s/CLAUDE.md`에 있다.

**이 레포는 public이다.** 비밀번호, 토큰, 개인키, kubeconfig, Secret 데이터는 절대 커밋하지 않는다.

## 디렉터리

| 경로 | 내용 |
|---|---|
| `helm/<release>/values.yaml` | Helm values. 첫 줄 주석에 chart 이름·버전과 연결된 Argo CD 앱을 적는다 |
| `argocd/applications/<app>.yaml` | Argo CD `Application`. 클러스터에는 `kubectl apply -f`로 등록한다 |
| `manifests/<app>/` | Helm이 아닌 일반 매니페스트. `path` 소스 Argo CD 앱이 가리킨다 |
| `.claude/agents/` | PR 리뷰·머지 에이전트 |

## Argo CD Application 규칙

- `metadata.namespace: argo-cd`, `project`: 시스템 구성요소는 `system`, 관측은 `o11y`
- Helm 차트: `targetRevision`은 정확한 버전으로 고정한다(`*`, 범위, `latest` 금지)
- values는 multi-source로 참조한다: 차트 소스 + `ref: values`(이 레포, `main`) → `$values/helm/<release>/values.yaml`
- `syncOptions`에 `ServerSideApply=true`. 네임스페이스를 만들어야 하면 `CreateNamespace=true`
- 컨트롤러가 런타임에 바꾸는 필드(webhook caBundle, failurePolicy 등)는 `ignoreDifferences` + `RespectIgnoreDifferences=true`

## Argo CD로 관리하지 않는 것

CNI나 Argo CD가 망가져도 Argo CD 없이 복구할 수 있게 Helm CLI로 직접 적용한다. values 파일 첫 줄 주석에 차트·버전을 적는다.

- Cilium(`helm/cilium/values.yaml`)
  `helm upgrade cilium cilium/cilium -n kube-system --version <고정> -f helm/cilium/values.yaml --force-conflicts`
  ConfigMap만 바뀌면 `kubectl -n kube-system rollout restart ds/cilium`이 필요하다.
- Argo CD(`helm/argocd/values.yaml`)
  `helm upgrade argocd argo/argo-cd -n argo-cd --version <고정> -f helm/argocd/values.yaml --force-conflicts`

## 작업 흐름

1. 작업 단위마다 브랜치(`feat/…`, `fix/…`, `chore/…`)를 만들고 PR을 연다. main에 직접 push하지 않는다.
2. 리뷰와 머지는 `gitops-pr-reviewer` 에이전트가 한다(`.claude/agents/gitops-pr-reviewer.md`).
3. 머지된 뒤에 클러스터에 적용한다(Argo CD 앱 등록 또는 Helm CLI). 적용 결과는 `my-k8s/TASKS.md` 작업 기록에 남긴다.
