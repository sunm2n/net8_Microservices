#!/usr/bin/env bash
#
# CI — 이미지 빌드
#
# 서비스 6개의 컨테이너 이미지를 만든다.
#
#   사용법:  scripts/ci-build.sh <태그>
#
# CI 로직을 워크플로 YAML 이 아니라 셸 스크립트에 두는 이유:
# 이 PoC 의 최종 목적지는 GitLab + Jenkins 다. 로직이 여기 있으면
# 전환할 때 호출하는 래퍼만 바꾸면 되고, 로컬에서 그대로 실행해 볼 수도 있다.
set -euo pipefail

TAG="${1:?사용법: ci-build.sh <태그>}"
REGISTRY_REPO="${REGISTRY_REPO:-eshop}"

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../src" && pwd)"

# 이미지 이름 → Dockerfile 경로
# 빌드 컨텍스트는 항상 src 루트다.
# Dockerfile 이 BuildingBlocks 같은 형제 디렉터리를 COPY 하므로 좁히면 실패한다.
SERVICES=(
  "catalog-api:Services/Catalog/Catalog.API/Dockerfile"
  "basket-api:Services/Basket/Basket.API/Dockerfile"
  "discount-grpc:Services/Discount/Discount.Grpc/Dockerfile"
  "ordering-api:Services/Ordering/Ordering.API/Dockerfile"
  "yarp-apigateway:ApiGateways/YarpApiGateway/Dockerfile"
  "shopping-web:WebApps/Shopping.Web/Dockerfile"
)

log() { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }
ok()  { printf '  \033[0;32m✓\033[0m %s\n' "$*"; }
die() { printf '\n\033[0;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

[[ -f "${SRC_DIR}/eshop-microservices.sln" ]] || die "src 디렉터리를 찾을 수 없다: ${SRC_DIR}"

log "빌드 ${#SERVICES[@]}개  태그 ${TAG}"

for entry in "${SERVICES[@]}"; do
  name="${entry%%:*}"
  dockerfile="${entry#*:}"
  image="${REGISTRY_REPO}/${name}:${TAG}"

  [[ -f "${SRC_DIR}/${dockerfile}" ]] || die "Dockerfile 없음: ${dockerfile}"

  docker build \
    --file "${SRC_DIR}/${dockerfile}" \
    --tag "${image}" \
    "${SRC_DIR}" \
    2>&1 | grep -E "^(#[0-9]+ (DONE|ERROR)|ERROR)" | tail -2 || true

  docker image inspect "${image}" >/dev/null 2>&1 || die "빌드 실패: ${image}"
  SIZE="$(docker image inspect "${image}" --format '{{.Size}}' | awk '{printf "%.0f MB", $1/1024/1024}')"
  ok "${image}  ${SIZE}"
done

log "완료"
