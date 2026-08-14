#!/usr/bin/env bash
#
# CI — SonarQube 정적분석
#
# 소스를 분석해 SonarQube 로 보내고 품질 게이트 판정을 확인한다.
#
#   사용법:  scripts/ci-analyze.sh <프로젝트버전>
#
# 환경변수:
#   SONAR_HOST_URL   기본 http://sonarqube.localtest.me
#   SONAR_TOKEN      필수. 없으면 분석을 건너뛴다
#   SONAR_PROJECT    기본 eshop-microservices
#   JAVA_HOME        미설정 시 Homebrew 의 openjdk@17 을 찾는다
set -euo pipefail

PROJECT_VERSION="${1:?사용법: ci-analyze.sh <프로젝트버전>}"

SONAR_HOST_URL="${SONAR_HOST_URL:-http://sonarqube.localtest.me}"
SONAR_PROJECT="${SONAR_PROJECT:-eshop-microservices}"
SONAR_TOKEN="${SONAR_TOKEN:-}"

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../src" && pwd)"

log()  { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[0;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[0;33m!\033[0m %s\n' "$*"; }
die()  { printf '\n\033[0;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# 토큰이 없으면 분석을 건너뛴다.
#
# 분석 서버는 로컬 클러스터에만 있다. 다른 환경에서 이 스크립트를 돌릴 때
# 토큰이 없다고 파이프라인을 세우는 것은 과하다.
# 다만 조용히 넘어가지 않도록 경고는 남긴다.
if [[ -z "${SONAR_TOKEN}" ]]; then
  warn "SONAR_TOKEN 이 없어 정적분석을 건너뛴다."
  warn "분석을 켜려면 저장소 시크릿에 SONAR_TOKEN 을 등록할 것."
  exit 0
fi

# dotnet-sonarscanner 는 JRE 17 이상을 요구한다.
if [[ -z "${JAVA_HOME:-}" ]]; then
  for candidate in /opt/homebrew/opt/openjdk@17 /usr/local/opt/openjdk@17 /opt/homebrew/opt/openjdk; do
    [[ -x "${candidate}/bin/java" ]] && { export JAVA_HOME="${candidate}"; break; }
  done
fi
[[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]] \
  || die "JRE 17 이상을 찾을 수 없다.  brew install openjdk@17"
export PATH="${JAVA_HOME}/bin:${PATH}"
ok "JAVA_HOME ${JAVA_HOME}"

# 스캐너는 전역 도구로 설치한다. 이미 있으면 건너뛴다.
export PATH="${HOME}/.dotnet/tools:${PATH}"
if ! command -v dotnet-sonarscanner >/dev/null 2>&1; then
  log "dotnet-sonarscanner 설치"
  dotnet tool install --global dotnet-sonarscanner >/dev/null 2>&1 \
    || dotnet tool update --global dotnet-sonarscanner >/dev/null 2>&1 \
    || die "스캐너 설치 실패"
fi
ok "dotnet-sonarscanner 준비"

curl -s -o /dev/null --max-time 10 "${SONAR_HOST_URL}/api/system/status" \
  || die "SonarQube 에 연결할 수 없다: ${SONAR_HOST_URL}"

# ── 분석 ─────────────────────────────────────────────────────────
#
# 스캐너는 begin → build → end 순서로 빌드를 감싸야 한다.
# 컴파일 과정을 가로채 분석 데이터를 모으는 구조라 그 사이의 빌드가 필요하다.
#
# 이미지 빌드(ci-build.sh)는 Docker 안에서 일어나 이 감싸기가 통하지 않는다.
# 그래서 여기서 호스트 빌드를 한 번 더 돌린다.
# 중복이지만 대안(Docker 안에 스캐너를 넣는 것)은 이미지에 분석 도구가 섞이고
# 캐시가 매번 깨져 더 비싸다.
log "분석 시작  ${SONAR_PROJECT} v${PROJECT_VERSION}"

cd "${SRC_DIR}"

dotnet-sonarscanner begin \
  /k:"${SONAR_PROJECT}" \
  /v:"${PROJECT_VERSION}" \
  /d:sonar.host.url="${SONAR_HOST_URL}" \
  /d:sonar.token="${SONAR_TOKEN}" \
  /d:sonar.scanner.scanAll=false \
  /d:sonar.exclusions="**/bin/**,**/obj/**,**/Migrations/**,**/*.cshtml" \
  /d:sonar.qualitygate.wait=true \
  /d:sonar.qualitygate.timeout=300 \
  >/dev/null || die "스캐너 begin 실패"
ok "begin"

dotnet build eshop-microservices.sln -c Release --nologo >/dev/null 2>&1 \
  || { dotnet-sonarscanner end /d:sonar.token="${SONAR_TOKEN}" >/dev/null 2>&1 || true; die "빌드 실패"; }
ok "build"

# end 단계에서 결과를 업로드하고, sonar.qualitygate.wait 때문에
# 품질 게이트 판정이 나올 때까지 기다린 뒤 결과에 따라 종료 코드를 정한다.
if dotnet-sonarscanner end /d:sonar.token="${SONAR_TOKEN}" >/tmp/sonar-end.log 2>&1; then
  ok "end — 품질 게이트 통과"
  GATE="PASSED"
else
  GATE="FAILED"
fi

# 판정 근거를 API 로 다시 확인해 사람이 읽을 형태로 남긴다.
log "품질 게이트"

RESULT="$(curl -s --max-time 30 -u "${SONAR_TOKEN}:" \
  "${SONAR_HOST_URL}/api/qualitygates/project_status?projectKey=${SONAR_PROJECT}" 2>/dev/null \
  | python3 -c "
import json,sys
try:
    s=json.load(sys.stdin)['projectStatus']
except Exception:
    print('UNKNOWN'); raise SystemExit
print(s.get('status','UNKNOWN'))
for c in s.get('conditions', []):
    if c.get('status') != 'OK':
        print(f\"  {c.get('metricKey')}: {c.get('actualValue')} (기준 {c.get('comparator')} {c.get('errorThreshold')})\")
" 2>/dev/null || echo "UNKNOWN")"

STATUS="$(echo "${RESULT}" | head -1)"
echo "${RESULT}" | tail -n +2 | sed 's/^/  /'

if [[ "${STATUS}" == "OK" ]]; then
  ok "통과 (${SONAR_HOST_URL}/dashboard?id=${SONAR_PROJECT})"
elif [[ "${GATE}" == "FAILED" || "${STATUS}" == "ERROR" ]]; then
  tail -20 /tmp/sonar-end.log >&2 2>/dev/null || true
  die "품질 게이트 실패 — 배포하지 않고 중단한다.
  ${SONAR_HOST_URL}/dashboard?id=${SONAR_PROJECT}"
else
  warn "판정을 확인하지 못했다 (${STATUS}). 대시보드에서 직접 확인할 것."
fi

log "완료"
