#!/usr/bin/env bash
#
# CI — Harbor 푸시
#
# 빌드한 이미지를 Harbor 의 erp-hq 프로젝트로 올린다.
#
#   사용법:  scripts/ci-push.sh <태그>
#
# 환경변수:
#   HARBOR_HOST      기본 harbor.localtest.me
#   HARBOR_PROJECT   기본 erp-hq
#   HARBOR_USER      기본 admin
#   HARBOR_PASSWORD  기본 Harbor12345 (로컬 PoC 값)
#   KIND_INGRESS_NODE 기본 erp-poc-worker
set -euo pipefail

TAG="${1:?사용법: ci-push.sh <태그>}"

HARBOR_HOST="${HARBOR_HOST:-harbor.localtest.me}"
HARBOR_PROJECT="${HARBOR_PROJECT:-erp-hq}"
HARBOR_USER="${HARBOR_USER:-admin}"
HARBOR_PASSWORD="${HARBOR_PASSWORD:-Harbor12345}"
KIND_INGRESS_NODE="${KIND_INGRESS_NODE:-erp-poc-worker}"
REGISTRY_REPO="${REGISTRY_REPO:-eshop}"
SKOPEO_IMAGE="quay.io/skopeo/stable:v1.19.0"

SERVICES=(catalog-api basket-api discount-grpc ordering-api yarp-apigateway shopping-web)

log() { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }
ok()  { printf '  \033[0;32m✓\033[0m %s\n' "$*"; }
die() { printf '\n\033[0;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# Harbor 는 클러스터 안에 있고 Ingress 를 통해 노출된다.
# harbor.localtest.me 는 공개 DNS 에서 127.0.0.1 로 해석되므로
# kind 네트워크에 붙은 컨테이너에서는 Ingress 노드를 직접 가리켜야 한다.
INGRESS_IP="$(docker inspect "${KIND_INGRESS_NODE}" \
  --format '{{(index .NetworkSettings.Networks "kind").IPAddress}}' 2>/dev/null || true)"
[[ -n "${INGRESS_IP}" ]] || die "Ingress 노드를 찾을 수 없다: ${KIND_INGRESS_NODE}
  kind 클러스터가 떠 있는지 확인할 것."

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

# docker push 를 쓰지 않는다.
# 평문 HTTP 레지스트리에 올리려면 데몬에 insecure-registries 를 추가하고
# 재시작해야 하는데, 러너가 도는 머신의 보안 설정을 건드리는 일이다.
#
# skopeo 는 --dest-tls-verify=false 로 인증 흐름까지 평문을 허용한다.
# (crane 의 --insecure 는 레지스트리 연결에만 적용되어 Harbor 의 http realm 을 거부한다)
skopeo() {
  docker run --rm --network kind \
    --add-host "${HARBOR_HOST}:${INGRESS_IP}" \
    -v "${TMPDIR}:/work" "${SKOPEO_IMAGE}" "$@"
}

log "푸시 대상  ${HARBOR_HOST}/${HARBOR_PROJECT}  태그 ${TAG}"
ok "Ingress ${KIND_INGRESS_NODE} → ${INGRESS_IP}"

for svc in "${SERVICES[@]}"; do
  SRC="${REGISTRY_REPO}/${svc}:${TAG}"
  DST="${HARBOR_HOST}/${HARBOR_PROJECT}/${svc}:${TAG}"

  docker image inspect "${SRC}" >/dev/null 2>&1 \
    || die "이미지가 없다: ${SRC}  (ci-build.sh 를 먼저 실행)"

  docker save "${SRC}" -o "${TMPDIR}/${svc}.tar"
  skopeo copy \
    --dest-tls-verify=false \
    --dest-creds "${HARBOR_USER}:${HARBOR_PASSWORD}" \
    "docker-archive:/work/${svc}.tar" \
    "docker://${DST}" >/dev/null 2>&1 || die "푸시 실패: ${DST}"
  rm -f "${TMPDIR}/${svc}.tar"

  ok "${DST}"
done

log "완료 — ${#SERVICES[@]}개"
