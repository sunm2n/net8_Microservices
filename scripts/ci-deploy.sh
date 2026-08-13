#!/usr/bin/env bash
#
# CI — 매니페스트 저장소 갱신
#
# 매니페스트 저장소의 이미지 태그를 방금 빌드한 태그로 바꿔 커밋한다.
# 배포 자체는 ArgoCD 가 이 커밋을 감지해 수행한다. 여기서 kubectl 을 쓰지 않는다.
#
#   사용법:  scripts/ci-deploy.sh <태그>
#
# 환경변수:
#   GITOPS_REPO     기본 sunm2n/Kubernetes_devOps_Poc
#   GITOPS_BRANCH   기본 dev
#   GITOPS_VALUES   기본 envs/dev/values.yaml
#   GITOPS_TOKEN    매니페스트 저장소에 쓸 토큰 (없으면 gh 인증을 쓴다)
set -euo pipefail

TAG="${1:?사용법: ci-deploy.sh <태그>}"

GITOPS_REPO="${GITOPS_REPO:-sunm2n/Kubernetes_devOps_Poc}"
GITOPS_BRANCH="${GITOPS_BRANCH:-dev}"
GITOPS_VALUES="${GITOPS_VALUES:-envs/dev/values.yaml}"
COMMIT_SHA="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"
SOURCE_REPO="${GITHUB_REPOSITORY:-sunm2n/net8_Microservices}"

log() { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }
ok()  { printf '  \033[0;32m✓\033[0m %s\n' "$*"; }
die() { printf '\n\033[0;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# ── 자격증명 ─────────────────────────────────────────────────────
#
# 워크플로의 기본 토큰(GITHUB_TOKEN)은 자기 저장소에만 유효해서
# 다른 저장소에 커밋할 수 없다. 별도의 자격증명이 필요하다.
#
# 운영에서는 GITOPS_TOKEN 을 저장소 시크릿으로 주입하는 것이 맞다.
# 이 PoC 는 러너가 로컬 사용자로 돌아 gh 인증을 그대로 쓸 수 있어
# 토큰을 따로 만들지 않았다. 실제 환경에서는 통하지 않는 방식이다.
TOKEN="${GITOPS_TOKEN:-}"
if [[ -z "${TOKEN}" ]]; then
  TOKEN="$(gh auth token 2>/dev/null || true)"
  [[ -n "${TOKEN}" ]] && ok "gh 인증 사용 (로컬 러너 전용)"
else
  ok "GITOPS_TOKEN 사용"
fi
[[ -n "${TOKEN}" ]] || die "매니페스트 저장소에 쓸 자격증명이 없다.
  GITOPS_TOKEN 을 주입하거나, 러너 머신에서 gh auth login 을 마칠 것."

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

# ── 클론 ─────────────────────────────────────────────────────────
log "매니페스트 저장소  ${GITOPS_REPO}@${GITOPS_BRANCH}"

# 토큰이 remote URL 에 남지 않도록 헤더로 전달한다.
# URL 에 넣으면 .git/config 와 에러 메시지에 그대로 노출된다.
AUTH_HEADER="Authorization: Basic $(printf 'x-access-token:%s' "${TOKEN}" | base64 | tr -d '\n')"

git -c "http.extraheader=${AUTH_HEADER}" clone \
  --quiet --depth 1 --branch "${GITOPS_BRANCH}" \
  "https://github.com/${GITOPS_REPO}.git" "${WORKDIR}/gitops" \
  || die "클론 실패"
ok "클론 완료"

cd "${WORKDIR}/gitops"
[[ -f "${GITOPS_VALUES}" ]] || die "값 파일을 찾을 수 없다: ${GITOPS_VALUES}"

# ── 태그 갱신 ────────────────────────────────────────────────────
CURRENT="$(grep -E '^\s+imageTag:' "${GITOPS_VALUES}" | head -1 | awk '{print $2}')"
log "이미지 태그  ${CURRENT} → ${TAG}"

if [[ "${CURRENT}" == "${TAG}" ]]; then
  ok "이미 같은 태그다 — 커밋 없음"
  exit 0
fi

# imageTag 줄만 바꾼다. 다른 값과 주석은 건드리지 않는다.
python3 - "${GITOPS_VALUES}" "${TAG}" <<'PY'
import re, sys
path, tag = sys.argv[1], sys.argv[2]
with open(path, encoding='utf-8') as f:
    text = f.read()
new, count = re.subn(r'(?m)^(\s+imageTag:\s*).*$', lambda m: m.group(1) + tag, text, count=1)
if count != 1:
    sys.exit(f'imageTag 를 정확히 한 곳에서 찾지 못했다 (발견 {count}건)')
with open(path, 'w', encoding='utf-8') as f:
    f.write(new)
PY
ok "${GITOPS_VALUES} 수정"

# ── 커밋 ─────────────────────────────────────────────────────────
git config user.name "erp-poc-ci"
git config user.email "erp-poc-ci@users.noreply.github.com"

git add "${GITOPS_VALUES}"
git commit --quiet -m "deploy: ${TAG}

${SOURCE_REPO}@${COMMIT_SHA} 빌드 결과를 배포한다.
이미지 6개가 같은 태그로 Harbor 에 올라가 있다.

이 커밋은 CI 가 만든 것이며, ArgoCD 가 감지해 클러스터에 반영한다."

git -c "http.extraheader=${AUTH_HEADER}" push --quiet origin "${GITOPS_BRANCH}" \
  || die "푸시 실패"

ok "$(git rev-parse --short HEAD) 커밋·푸시 완료"

cat <<EOF

$(printf '\033[1;32m매니페스트 갱신 완료\033[0m')

  태그   ${TAG}
  대상   ${GITOPS_REPO}@${GITOPS_BRANCH}

  ArgoCD 가 폴링 주기(60초) 안에 감지해 배포한다.

EOF
