# ARC 러너 이미지 → ghcr.io/jangjaelee/arc-runner (빌드: .github/workflows/arc-runner-image.yaml)
# 쓰는 곳: 러너 스케일 셋 arc-infralens (helm/arc-infralens/values.yaml)
# 공식 러너 이미지(Ubuntu 24.04, git·curl·jq·unzip·sudo·docker CLI·buildx 포함)에
# GitHub 호스팅 ubuntu-24.04 러너에서 워크플로가 쓰던 도구를 더한다. Node는 setup 액션이 받는다.
# Go는 이미지에 미리 넣는다(아래 도구 캐시). 2026-11-18 PM 승인: setup-go 다운로드가 19분 멈춰 잡 취소(run 44110812622)
#
# ARC 러너는 자동 업데이트 없이 잡 하나만 돌고 지워진다(ephemeral). 새 러너 릴리스가 나오면
# 30일 안에 FROM을 올려야 GitHub이 잡을 계속 보낸다(Dependabot이 PR을 연다, .github/dependabot.yml).
FROM ghcr.io/actions/actions-runner:2.338.2@sha256:6d0b2d80d80f143f77dcb676e50920100bbb547e39e883454d57f45ab8c31300

# 체크섬: get.helm.sh/helm-v<버전>-linux-amd64.tar.gz.sha256sum, github.com/mikefarah/yq 릴리스 checksums-bsd
ARG HELM_VERSION=4.3.1
ARG HELM_SHA256=0403a88ae20913d11b10a2467b50087721fea7581736da6b9d3992f5357fe54b
ARG YQ_VERSION=4.54.1
ARG YQ_SHA256=8e34fc298390875de416e6a4afcb8cabeceb25d9aa8506c1a2f9353cf702ea5f
# Go: infralens go.mod의 go 판(1.27). 체크섬은 https://go.dev/dl/?mode=json 의 linux-amd64 archive sha256
# Go 판을 올릴 때(go.mod 변경) 여기 GO_VERSION·GO_SHA256도 같이 올린다. 안 맞으면 setup-go가 예전처럼 내려받는다(느릴 뿐 실패 아님)
ARG GO_VERSION=1.27.4
ARG GO_SHA256=7226736c2339719cda28fbf3a54d71aa63bcefe376e98cef00034268dab24840

USER root

# python3·ruby: 문서 검사(frontmatter YAML), gcc·libc6-dev·make: cgo·go test -race,
# file·xz-utils·zstd·zip: 스모크 스크립트, actions/cache·setup 액션의 압축 해제
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 python3-yaml ruby \
        gcc libc6-dev make \
        file xz-utils zstd zip \
    && rm -rf /var/lib/apt/lists/*

# Playwright Chromium 시스템 라이브러리·도구·글꼴. playwright-core 1.64.1(infralens src/web)의 ubuntu24.04-x64
# tools + chromium 목록 그대로다(npx playwright install-deps chromium이 까는 것). 미리 넣어 두면 e2e의 --with-deps가
# apt를 건너뛴다(2026-10-22 security.ubuntu.com Hash Sum mismatch로 e2e 반복 실패). Playwright를 올리면 목록을 다시 맞춘다.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        xvfb fonts-noto-color-emoji fonts-unifont libfontconfig1 libfreetype6 xfonts-cyrillic xfonts-scalable \
        fonts-liberation fonts-ipafont-gothic fonts-wqy-zenhei fonts-tlwg-loma-otf fonts-freefont-ttf \
        libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 libatspi2.0-0t64 libcairo2 libcups2t64 libdbus-1-3 \
        libdrm2 libgbm1 libglib2.0-0t64 libnspr4 libnss3 libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 \
        libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2 \
    && rm -rf /var/lib/apt/lists/*

# helm 4, yq(mikefarah, 호스팅 러너와 같은 Go 구현)
RUN curl -fsSL -o /tmp/helm.tgz "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
    && echo "${HELM_SHA256}  /tmp/helm.tgz" | sha256sum -c - \
    && tar -xzf /tmp/helm.tgz -C /tmp linux-amd64/helm \
    && install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm \
    && rm -rf /tmp/helm.tgz /tmp/linux-amd64 \
    && curl -fsSL -o /tmp/yq "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" \
    && echo "${YQ_SHA256}  /tmp/yq" | sha256sum -c - \
    && install -m 0755 /tmp/yq /usr/local/bin/yq \
    && rm -f /tmp/yq

# 도구 캐시: _work는 emptyDir이라 이미지의 _work/_tool이 가려진다. 호스팅 러너처럼 /opt/hostedtoolcache를 쓴다.
# setup-go는 <캐시>/go/<판>/x64 와 x64.complete 표시가 있으면 내려받지 않는다. 다른 판은 runner 소유라 그대로 받아 넣을 수 있다
ENV RUNNER_TOOL_CACHE=/opt/hostedtoolcache AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache
RUN mkdir -p /opt/hostedtoolcache/go/${GO_VERSION}/x64 \
    && curl -fsSL -o /tmp/go.tgz "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
    && echo "${GO_SHA256}  /tmp/go.tgz" | sha256sum -c - \
    && tar -xzf /tmp/go.tgz -C /opt/hostedtoolcache/go/${GO_VERSION}/x64 --strip-components=1 \
    && touch /opt/hostedtoolcache/go/${GO_VERSION}/x64.complete \
    && rm -f /tmp/go.tgz \
    && chown -R runner:runner /opt/hostedtoolcache

# 호스팅 러너와 같은 로캘(UTF-8 파일·출력)
ENV LANG=C.UTF-8

USER runner
