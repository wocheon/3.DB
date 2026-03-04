#!/bin/bash

# 색상 출력 함수 정의
function red (){ echo -e "\E[;31m$1\E[0m"; }
function green (){ echo -e "\E[;32m$1\E[0m"; }
function yellow (){ echo -e "\E[;33m$1\E[0m"; }

# ==============================================================================
# MariaDB 전 버전 호환(10.5 ~ 11.x) 메모리 단편화/누수 정밀 진단 스크립트
# ==============================================================================

MYSQL_USER="root"
MYSQL_PASS="" # 필요시 입력 (예: MYSQL_PASS="your_password")
MYSQL_CONN="mysql -u$MYSQL_USER -N -e"
if [ -n "$MYSQL_PASS" ]; then MYSQL_CONN="mysql -u$MYSQL_USER -p$MYSQL_PASS -N -e"; fi

echo "========================================================================="
echo "   MariaDB Memory Fragmentation & Bloat Analysis Report"
echo "   점검 일시: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================================="

# 1. 시스템 및 MariaDB 기본 상태 수집
PID=$(pgrep -f mariadbd | head -n1)
if [ -z "$PID" ]; then echo "[오류] MariaDB 프로세스를 찾을 수 없습니다."; exit 1; fi

MALLOC_LIB=$($MYSQL_CONN "SELECT @@version_malloc_library;")
if [[ -z "$MALLOC_LIB" ]]; then MALLOC_LIB="system (glibc)"; fi

PAGE_SIZE=$($MYSQL_CONN "SELECT @@innodb_page_size")
TOTAL_PAGES=$($MYSQL_CONN "SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_pages_total'" | awk '{print $2}')
DATA_PAGES=$($MYSQL_CONN "SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_pages_data'" | awk '{print $2}')
MEMORY_USED_KB=$($MYSQL_CONN "SHOW GLOBAL STATUS LIKE 'Memory_used'" | awk '{print $2}')

# 2. 용량 사전 계산 (GB 변환)
BUFFER_POOL_GB=$(echo "scale=2; ($TOTAL_PAGES * $PAGE_SIZE) / 1024 / 1024 / 1024" | bc)
DATA_GB=$(echo "scale=2; ($DATA_PAGES * $PAGE_SIZE) / 1024 / 1024 / 1024" | bc)
MEMORY_USED_GB=$(echo "scale=2; $MEMORY_USED_KB / 1024 / 1024 / 1024" | bc)

# ==============================================================================
# [핵심 로직] 버전에 따른 Memory_used 계산식 동적 분기
# ==============================================================================
VERSION_STRING=$($MYSQL_CONN "SELECT @@version")
# 메이저, 마이너, 패치 버전 추출 (예: "10.6.16-MariaDB" -> 10, 6, 16)
V_MAJOR=$(echo $VERSION_STRING | cut -d. -f1)
V_MINOR=$(echo $VERSION_STRING | cut -d. -f2)
V_PATCH=$(echo $VERSION_STRING | cut -d. -f3 | cut -d- -f1 | sed 's/[^0-9]//g')

# 10.6.16 이상 버전인지 판별 (Memory_used가 전체를 포함하는 버전)
IS_NEW_MEM_CALC=0
if [[ "$V_MAJOR" -gt 10 ]] || \
   [[ "$V_MAJOR" -eq 10 && "$V_MINOR" -gt 6 ]] || \
   [[ "$V_MAJOR" -eq 10 && "$V_MINOR" -eq 6 && "$V_PATCH" -ge 16 ]]; then
    IS_NEW_MEM_CALC=1
fi

echo "1. MariaDB 버전 및 할당자 정보:"
echo "   - 현재 버전: ${VERSION_STRING}"
echo "   - 메모리 할당자: ${MALLOC_LIB}"

if [ $IS_NEW_MEM_CALC -eq 1 ]; then
    yellow "   [i] 진단 모드: 최신 버전 (Memory_used에 Buffer Pool이 포함된 통합 지표 사용)"
    EXPECTED_TOTAL_GB=$MEMORY_USED_GB
    SESSION_MISC_GB=$(echo "scale=2; $MEMORY_USED_GB - $BUFFER_POOL_GB" | bc)
else
    yellow "   [i] 진단 모드: 10.6.15 이하 구버전 (Buffer Pool + Memory_used 분리 합산 방식 사용)"
    EXPECTED_TOTAL_GB=$(echo "scale=2; $BUFFER_POOL_GB + $MEMORY_USED_GB" | bc)
    SESSION_MISC_GB=$MEMORY_USED_GB
fi
echo ""
# ==============================================================================

# OS RSS 수집 및 계산
RSS_KB=$(ps -o rss= -p $PID)
RSS_GB=$(echo "scale=2; $RSS_KB / 1024 / 1024" | bc)

# pmap 기반 파편화 블록 탐지 (100MB 이상 anon 블록)
PMAP_ANON_COUNT=$(pmap -x $PID | awk -v conf_kb=$((TOTAL_PAGES * PAGE_SIZE / 1024)) '$2 > 102400 && $2 < conf_kb && $5 ~ /anon/ {count++} END {print count+0}')

# RSS와 Expected Total의 격차 계산 (Memory Bloat 판단 기준)
GAP_RSS_MEM=$(echo "scale=2; $RSS_GB - $EXPECTED_TOTAL_GB" | bc)

# 3. 진단 결과 출력
echo "2. 메모리 점유 요약:"
echo "   - [A] 설정된 버퍼풀 (Global):  ${BUFFER_POOL_GB} GB (실 데이터: ${DATA_GB} GB)"
echo "   - [B] 세션/기타 동적 할당량:   ${SESSION_MISC_GB} GB"
echo "   - [A+B] 내부 예상 총 점유량:   ${EXPECTED_TOTAL_GB} GB"
echo "   - [C] OS 실제 점유량 (RSS):    ${RSS_GB} GB"
echo ""

echo "3. 진단 결과:"
if (( $(echo "$GAP_RSS_MEM > 2.0" | bc -l) )); then
    red "   [!] 위험: Memory Bloat (미반환 메모리) 감지됨. (격차: ${GAP_RSS_MEM} GB)"
else
    green "   [v] 정상: OS 점유량(RSS)이 MariaDB 내부 예상치와 일치합니다."
fi

if [ "$PMAP_ANON_COUNT" -gt 5 ]; then
    red "   [!] 경고: OS 레벨 메모리 단편화 의심 (대형 anon 블록 ${PMAP_ANON_COUNT}개)"
else
    green "   [v] 정상: 유의미한 OS 레벨 단편화가 관찰되지 않았습니다."
fi
echo ""

# 4. 단계별 권고 및 조치 사항
echo "4. 권고 및 조치 사항 (Action Items):"
if (( $(echo "$GAP_RSS_MEM > 2.0" | bc -l) )) || [ "$PMAP_ANON_COUNT" -gt 5 ]; then
    yellow "   [Phase 1: 근본/확실한 조치 (Downtime 필요)]"
    echo "   ▶ 서비스 재시작 권장: 현재 ${GAP_RSS_MEM}GB의 메모리가 낭비되고 있습니다."
    echo "      안전한 유지보수 시간대에 'systemctl restart mariadb'를 수행하여 OOM을 예방하세요."
    echo ""
    yellow "   [Phase 2: 무중단 임시 완화 조치 (Zero-downtime Mitigation)]"
    echo "   ▶ 당장 재시작이 어렵고 OOM이 임박했다면 아래 명령어로 내부 캐시 반환을 유도하세요:"
    echo "      1) mysql -e \"FLUSH LOCAL PRIVILEGES; FLUSH HOSTS;\""
    echo "      2) mysql -e \"FLUSH TABLES;\" (주의: 활성 트랜잭션이 적은 시점에 실행 권장)"
    echo "   ▶ 동적 세션 메모리 제한 (단편화 추가 발생 억제):"
    echo "      - mysql -e \"SET GLOBAL tmp_table_size = 67108864;\""
    echo "      - mysql -e \"SET GLOBAL max_heap_table_size = 67108864;\""
    echo ""
    if [[ "$MALLOC_LIB" == *"system"* ]]; then
        yellow "   [Phase 3: 인프라 개선 권고 (Best Practice)]"
        echo "   ▶ jemalloc 적용 권장: 현재 glibc malloc을 사용 중이므로 단편화에 취약합니다."
        echo "      다음 유지보수 시 OS에 jemalloc 설치 후 my.cnf에 아래를 추가하세요."
        echo "      [mysqld_safe]"
        echo "      malloc-lib=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2"
    fi
else
    green "   >>> [상태 양호] 현재 메모리 단편화 수치가 정상 범위 내에 있습니다. 조치가 필요하지 않습니다."
fi
echo "========================================================================="
