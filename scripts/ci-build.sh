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

BUILD_LOG="$(mktemp)"
trap 'rm -f "${BUILD_LOG}"' EXIT

log "빌드 ${#SERVICES[@]}개  태그 ${TAG}"

for entry in "${SERVICES[@]}"; do
  name="${entry%%:*}"
  dockerfile="${entry#*:}"
  image="${REGISTRY_REPO}/${name}:${TAG}"

  [[ -f "${SRC_DIR}/${dockerfile}" ]] || die "Dockerfile 없음: ${dockerfile}"

  # 베이스 이미지를 mcr.microsoft.com 에서 받는 과정이 간헐적으로 실패한다.
  #   Head "https://mcr.microsoft.com/v2/dotnet/aspnet/manifests/8.0": EOF
  # 일시적인 네트워크 문제인데 파이프라인 전체가 멈추고 사람이 재실행해야 했다.
  # 무인 배포를 목표로 하는 이상 그 지점을 남겨둘 수 없다.
  #
  # 컴파일 오류와 네트워크 오류를 종료 코드로 구분할 수 없어 단순 재시도로 둔다.
  # 컴파일 오류라면 세 번 모두 같은 이유로 실패하고 파이프라인은 정상적으로 멈춘다.
  #
  # 근본 해결은 베이스 이미지를 내부 레지스트리로 미러링하는 것이다.
  # 폐쇄망 단계에서는 외부 접근이 불가능해 미러링이 선택이 아니라 필수가 된다.
  BUILT=""
  for attempt in 1 2 3; do
    if docker build \
         --file "${SRC_DIR}/${dockerfile}" \
         --tag "${image}" \
         "${SRC_DIR}" \
         >"${BUILD_LOG}" 2>&1; then
      BUILT="1"
      break
    fi

    if [[ "${attempt}" -lt 3 ]]; then
      DELAY=$((attempt * attempt * 5))   # 5초 → 20초
      printf '  \033[0;33m!\033[0m %s 빌드 실패 (%d/3) — %d초 후 재시도\n' "${name}" "${attempt}" "${DELAY}"
      grep -E "^(ERROR|failed)" "${BUILD_LOG}" | tail -2 | sed 's/^/      /' || true
      sleep "${DELAY}"
    fi
  done

  if [[ -z "${BUILT}" ]]; then
    tail -20 "${BUILD_LOG}" >&2
    die "빌드 실패: ${image} (3회 시도)"
  fi

  docker image inspect "${image}" >/dev/null 2>&1 || die "빌드 실패: ${image}"
  SIZE="$(docker image inspect "${image}" --format '{{.Size}}' | awk '{printf "%.0f MB", $1/1024/1024}')"
  ok "${image}  ${SIZE}"
done

log "완료"
