#!/usr/bin/env bash
#
# CI — 단위 테스트
#
# 인프라가 필요 없는 테스트만 돌린다.
# 실제 서비스 간 통신은 매니페스트 저장소의 scripts/12-verify-eshop.sh 가 배포 후에 확인한다.
#
#   사용법:  scripts/ci-test.sh
#
# 이 단계가 실패하면 이미지를 만들지 않는다.
# 빌드보다 앞에 두는 이유는 테스트가 훨씬 빠르기 때문이다(수십 ms 대 수 분).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../src" && pwd)"
RESULTS_DIR="${SRC_DIR}/TestResults"

log() { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }
ok()  { printf '  \033[0;32m✓\033[0m %s\n' "$*"; }
die() { printf '\n\033[0;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

command -v dotnet >/dev/null 2>&1 || die "dotnet SDK 가 필요하다."
[[ -f "${SRC_DIR}/eshop-microservices.sln" ]] || die "src 디렉터리를 찾을 수 없다: ${SRC_DIR}"

rm -rf "${RESULTS_DIR}"

log "단위 테스트"

# --logger trx 로 결과 파일을 남긴다. 워크플로 요약에서 집계에 쓴다.
#
# LogFileName 을 고정하지 않는다. 지정하면 테스트 프로젝트마다 같은 파일에 쓰면서
# 마지막 것만 남고, 집계가 한 프로젝트 분량으로 줄어든다.
# 기본 동작은 프로젝트별로 서로 다른 이름을 만든다.
if dotnet test "${SRC_DIR}/eshop-microservices.sln" \
     --configuration Release \
     --nologo \
     --logger "trx" \
     --results-directory "${RESULTS_DIR}" \
     2>&1 | tee /tmp/ci-test.log | grep -E "통과!|실패!|Passed!|Failed!|error"; then
  :
fi

# dotnet test 의 종료 코드를 그대로 쓴다.
# tee 를 거치므로 PIPESTATUS 로 꺼낸다.
STATUS="${PIPESTATUS[0]:-0}"

# 집계는 trx 파일에서 읽는다. 로그 문자열은 언어 설정에 따라 달라진다.
SUMMARY="$(python3 - "${RESULTS_DIR}" <<'PY' 2>/dev/null || true
import glob, sys, xml.etree.ElementTree as ET
total = passed = failed = 0
for f in glob.glob(f'{sys.argv[1]}/**/*.trx', recursive=True):
    root = ET.parse(f).getroot()
    ns = {'t': 'http://microsoft.com/schemas/VisualStudio/TeamTest/2010'}
    c = root.find('t:ResultSummary/t:Counters', ns)
    if c is not None:
        total += int(c.get('total', 0))
        passed += int(c.get('passed', 0))
        failed += int(c.get('failed', 0))
print(f'{total} {passed} {failed}')
PY
)"

read -r TOTAL PASSED FAILED <<<"${SUMMARY:-0 0 0}"

if [[ "${STATUS}" -ne 0 || "${FAILED}" -gt 0 ]]; then
  printf '\n  \033[0;31m실패한 테스트\033[0m\n'
  grep -E "^\s+(실패|Failed)" /tmp/ci-test.log | head -20 | sed 's/^/  /' || true
  die "테스트 실패 — 통과 ${PASSED} / 전체 ${TOTAL}, 실패 ${FAILED}
  이미지를 만들지 않고 중단한다."
fi

ok "통과 ${PASSED} / 전체 ${TOTAL}"

# 워크플로 요약에 쓸 수 있도록 결과를 내보낸다.
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "total=${TOTAL}"
    echo "passed=${PASSED}"
    echo "failed=${FAILED}"
  } >> "${GITHUB_OUTPUT}"
fi

log "완료"
