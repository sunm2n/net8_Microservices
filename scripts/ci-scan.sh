#!/usr/bin/env bash
#
# CI — 이미지 취약점 스캔 확인
#
# 방금 푸시한 이미지의 Trivy 스캔이 끝나기를 기다리고 결과를 판정한다.
#
#   사용법:  scripts/ci-scan.sh <태그>
#
# Harbor 는 pull 시점에도 차단하지만, 그때는 이미 배포가 시작된 뒤다.
# 실제로 겪은 형태는 이랬다. 빌드·푸시·매니페스트 갱신이 모두 성공하고,
# ArgoCD 가 동기화한 다음, 파드가 ImagePullBackOff 로 뜨지 못했다.
# containerd 는 412 Precondition Failed 만 남겨 원인을 알기 어려웠다.
#
# 이 단계는 그 판정을 배포 전으로 당긴다.
set -euo pipefail

TAG="${1:?사용법: ci-scan.sh <태그>}"

HARBOR_HOST="${HARBOR_HOST:-harbor.localtest.me}"
HARBOR_PROJECT="${HARBOR_PROJECT:-erp-hq}"
HARBOR_USER="${HARBOR_USER:-admin}"
HARBOR_PASSWORD="${HARBOR_PASSWORD:-Harbor12345}"

# 어느 등급부터 막을지. Harbor 프로젝트 설정과 맞춘다.
BLOCK_SEVERITY="${BLOCK_SEVERITY:-Critical}"

SERVICES=(catalog-api basket-api discount-grpc ordering-api yarp-apigateway shopping-web)

log()  { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[0;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[0;33m!\033[0m %s\n' "$*"; }
die()  { printf '\n\033[0;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

api() { curl -s --max-time 20 -u "${HARBOR_USER}:${HARBOR_PASSWORD}" "$@"; }

log "취약점 스캔 확인  태그 ${TAG}"

# 허용목록은 Harbor 에서 직접 읽는다.
#
# 스크립트에 복사해두면 Harbor 쪽 설정과 조용히 어긋난다.
# CI 는 통과시켰는데 배포에서 막히거나, 그 반대가 된다.
ALLOWLIST="$(api "http://${HARBOR_HOST}/api/v2.0/projects/${HARBOR_PROJECT}" 2>/dev/null \
  | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    print(''); raise SystemExit
print(','.join(i['cve_id'] for i in (d.get('cve_allowlist') or {}).get('items', [])))
" 2>/dev/null || true)"

REUSE_SYS="$(api "http://${HARBOR_HOST}/api/v2.0/projects/${HARBOR_PROJECT}" 2>/dev/null \
  | python3 -c "
import json,sys
print((json.load(sys.stdin).get('metadata') or {}).get('reuse_sys_cve_allowlist','?'))
" 2>/dev/null || echo '?')"

ALLOW_COUNT=0
[[ -n "${ALLOWLIST}" ]] && ALLOW_COUNT="$(echo "${ALLOWLIST}" | tr ',' '\n' | grep -c . || true)"
ok "프로젝트 허용목록 ${ALLOW_COUNT}건 (reuse_sys_cve_allowlist=${REUSE_SYS})"

# reuse_sys_cve_allowlist 가 true 면 Harbor 는 프로젝트 허용목록이 아니라
# 시스템 전역 목록을 본다. 그러면 여기서 읽은 목록과 실제 판정이 달라진다.
[[ "${REUSE_SYS}" == "true" ]] && \
  warn "Harbor 가 시스템 전역 허용목록을 사용한다. 아래 판정과 실제 pull 결과가 다를 수 있다."

BLOCKED=""
TOTAL_FINDINGS=0

for svc in "${SERVICES[@]}"; do
  # 스캔은 푸시 직후 자동으로 시작된다(auto_scan). 끝날 때까지 기다린다.
  DIGEST=""
  STATUS=""
  for _ in $(seq 1 60); do
    READ="$(api "http://${HARBOR_HOST}/api/v2.0/projects/${HARBOR_PROJECT}/repositories/${svc}/artifacts?with_tag=true&with_scan_overview=true" \
      2>/dev/null | TAG="${TAG}" python3 -c "
import json,sys,os
tag=os.environ['TAG']
try:
    arts=json.load(sys.stdin)
except Exception:
    raise SystemExit
for a in arts:
    if any(t['name']==tag for t in (a.get('tags') or [])):
        st='Pending'
        for v in (a.get('scan_overview') or {}).values():
            st=v.get('scan_status','Pending')
        print(a['digest'], st)
        break
" 2>/dev/null || true)"
    DIGEST="${READ%% *}"
    STATUS="${READ##* }"
    [[ "${STATUS}" == "Success" ]] && break
    sleep 5
  done

  if [[ "${STATUS}" != "Success" ]]; then
    die "${svc}: 스캔이 끝나지 않았다 (상태 ${STATUS:-없음}).
  Harbor 의 Trivy 파드와 프로젝트의 auto_scan 설정을 확인할 것."
  fi

  # 허용목록에 없는 대상 등급 취약점을 센다.
  RESULT="$(api "http://${HARBOR_HOST}/api/v2.0/projects/${HARBOR_PROJECT}/repositories/${svc}/artifacts/${DIGEST}/additions/vulnerabilities" \
    2>/dev/null | ALLOWLIST="${ALLOWLIST}" SEVERITY="${BLOCK_SEVERITY}" python3 -c "
import json,sys,os
allow={x for x in os.environ['ALLOWLIST'].split(',') if x}
want=os.environ['SEVERITY']
try:
    d=json.load(sys.stdin)
except Exception:
    print('0 0 '); raise SystemExit
found=set(); total=0
for v in d.values():
    for x in v.get('vulnerabilities', []):
        if x.get('severity') == want:
            total += 1
            if x['id'] not in allow:
                found.add((x['id'], x.get('package','?')))
print(len(found), total, ';'.join(f'{c}|{p}' for c,p in sorted(found)))
" 2>/dev/null || echo "0 0 ")"

  NEW_COUNT="$(echo "${RESULT}" | awk '{print $1}')"
  ALL_COUNT="$(echo "${RESULT}" | awk '{print $2}')"
  DETAIL="$(echo "${RESULT}" | cut -d' ' -f3-)"
  TOTAL_FINDINGS=$((TOTAL_FINDINGS + NEW_COUNT))

  if [[ "${NEW_COUNT}" -gt 0 ]]; then
    printf '  \033[0;31m✗\033[0m %-18s %s %s건 — 허용목록 밖 %s건\n' \
      "${svc}" "${BLOCK_SEVERITY}" "${ALL_COUNT}" "${NEW_COUNT}"
    echo "${DETAIL}" | tr ';' '\n' | while IFS='|' read -r cve pkg; do
      [[ -n "${cve}" ]] && printf '        %-20s %s\n' "${cve}" "${pkg}"
    done
    BLOCKED="1"
  else
    ok "${svc}  ${BLOCK_SEVERITY} ${ALL_COUNT}건 (전부 허용목록)"
  fi
done

if [[ -n "${BLOCKED}" ]]; then
  die "허용목록에 없는 ${BLOCK_SEVERITY} 취약점 ${TOTAL_FINDINGS}건.
  배포하지 않고 중단한다.

  고칠 수 있으면 해당 패키지를 올린다.
  베이스 이미지처럼 손댈 수 없는 것이면 Harbor 프로젝트의 CVE 허용목록에 등록한다.
  허용목록은 손댈 수 없는 것만 담아야 한다. 고칠 수 있는 것을 넣어두면
  목록이 쌓이기만 하고 게이트가 아무것도 막지 않게 된다."
fi

log "통과 — 배포 가능"
