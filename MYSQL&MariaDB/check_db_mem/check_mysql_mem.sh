#!/bin/bash

# ==============================================================================
# MySQL 전용(5.7, 8.0, 8.4 등) 메모리 단편화/누수 정밀 진단 스크립트
# ==============================================================================

function red (){ echo -e "\E[;31m$1\E[0m"; }
function green (){ echo -e "\E[;32m$1\E[0m"; }
function yellow (){ echo -e "\E[;33m$1\E[0m"; }

MYSQL_USER="root"
MYSQL_PASS="" # 필요시 입력
MYSQL_CONN="mysql -u$MYSQL_USER -N -e"
if [ -n "$MYSQL_PASS" ]; then MYSQL_CONN="mysql -u$MYSQL_USER -p$MYSQL_PASS -N -e"; fi

echo "========================================================================="
echo "   MySQL Memory Fragmentation & Bloat Analysis Report"
echo "   점검 일시: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================================="

# 1. MySQL 프로세스 확인
PID=$(pgrep -f mysqld | head -n1)
if [ -z "$PID" ]; then red "[오류] MySQL (mysqld) 프로세스를 찾을 수 없습니다."; exit 1; fi

# 2. 버전 확인 및 명령어 분기 설정
VERSION_STRING=$($MYSQL_CONN "SELECT @@version;")
V_MAJOR=$(echo $VERSION_STRING | cut -d. -f1)
V_MINOR=$(echo $VERSION_STRING | cut -d. -f2)
V_PATCH=$(echo $VERSION_STRING | cut -d. -f3 | cut -d- -f1)

FLUSH_CMD="FLUSH HOSTS;"
if [[ "$V_MAJOR" -ge 8 ]]; then
    if [[ "$V_MAJOR" -gt 8 ]] || [[ "$V_PATCH" -ge 23 ]]; then
        # MySQL 8.0.23 이상에서는 FLUSH HOSTS가 삭제됨
        FLUSH_CMD="TRUNCATE TABLE performance_schema.host_cache;"
    fi
fi

# 3. Performance Schema 기반 메모리 계산
PFS_ON=$($MYSQL_CONN "SELECT @@performance_schema;")
if [ "$PFS_ON" != "1" ]; then
    red "[!] 오류: Performance Schema가 비활성화되어 메모리 추적이 불가능합니다."
    exit 1
fi

PFS_MEM_BYTES=$($MYSQL_CONN "SELECT SUM(CURRENT_NUMBER_OF_BYTES_USED) FROM performance_schema.memory_summary_global_by_event_name;" 2>/dev/null)

if [ -z "$PFS_MEM_BYTES" ] || [ "$PFS_MEM_BYTES" == "NULL" ]; then
    red "[!] 경고: MySQL 5.7 등에서 메모리 계측(Instrumentation)이 OFF 상태일 수 있습니다."
    echo "    (조치: my.cnf에 performance_schema_instrument='memory/%=ON' 추가 필요)"
    exit 1
fi

EXPECTED_TOTAL_GB=$(echo "scale=2; $PFS_MEM_BYTES / 1024 / 1024 / 1024" | bc)

# 4. 버퍼풀 설정값 (참고용)
PAGE_SIZE=$($MYSQL_CONN "SELECT @@innodb_page_size;")
TOTAL_PAGES=$($MYSQL_CONN "SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_pages_total';" | awk '{print $2}')
DATA_PAGES=$($MYSQL_CONN "SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_pages_data';" | awk '{print $2}')
BUFFER_POOL_GB=$(echo "scale=2; ($TOTAL_PAGES * $PAGE_SIZE) / 1024 / 1024 / 1024" | bc)
DATA_GB=$(echo "scale=2; ($DATA_PAGES * $PAGE_SIZE) / 1024 / 1024 / 1024" | bc)

# 5. OS RSS 및 pmap 수집 (메모리 단편화 감지)
RSS_KB=$(ps -o rss= -p $PID)
RSS_GB=$(echo "scale=2; $RSS_KB / 1024 / 1024" | bc)
PMAP_ANON_COUNT=$(pmap -x $PID 2>/dev/null | awk -v conf_kb=$((TOTAL_PAGES * PAGE_SIZE / 1024)) '$2 > 102400 && $2 < conf_kb && $5 ~ /anon/ {count++} END {print count+0}')
GAP_RSS_MEM=$(echo "scale=2; $RSS_GB - $EXPECTED_TOTAL_GB" | bc)

# 6. 할당자(Allocator) 확인 (OS smaps)
if grep -q "jemalloc" /proc/$PID/smaps 2>/dev/null; then
    MALLOC_LIB="jemalloc"
else
    MALLOC_LIB="system (glibc)"
fi

# ==============================================================================
# 출력부
# ==============================================================================
echo "1. MySQL 환경 정보:"
echo "   - 버전: ${VERSION_STRING}"
echo "   - 메모리 할당자: ${MALLOC_LIB}"
echo ""

echo "2. 메모리 점유 요약:"
echo "   - [A] 설정된 버퍼풀 (Global):  ${BUFFER_POOL_GB} GB (실 데이터: ${DATA_GB} GB)"
echo "   - [B] MySQL 내부 예상 총 점유: ${EXPECTED_TOTAL_GB} GB (Performance Schema 기반)"
echo "   - [C] OS 실제 점유량 (RSS):    ${RSS_GB} GB"
echo ""

echo "3. 진단 결과:"
if (( $(echo "$GAP_RSS_MEM > 2.0" | bc -l) )); then
    red "   [!] 위험: Memory Bloat (미반환 메모리) 감지됨. (격차: ${GAP_RSS_MEM} GB)"
else
    green "   [v] 정상: OS 점유량(RSS)이 MySQL 내부 예상치와 거의 일치합니다."
fi

if [ "$PMAP_ANON_COUNT" -gt 5 ]; then
    red "   [!] 경고: OS 레벨 메모리 단편화 의심 (대형 anon 블록 ${PMAP_ANON_COUNT}개)"
else
    green "   [v] 정상: 유의미한 OS 레벨 단편화가 관찰되지 않았습니다."
fi
echo ""

echo "4. 권고 및 조치 사항 (Action Items):"
if (( $(echo "$GAP_RSS_MEM > 2.0" | bc -l) )) || [ "$PMAP_ANON_COUNT" -gt 5 ]; then
    yellow "   [Phase 1: 근본/확실한 조치 (Downtime 필요)]"
    echo "   ▶ 서비스 재시작 권장: 현재 ${GAP_RSS_MEM}GB의 메모리가 미반환 상태입니다."
    echo "      - 명령어: systemctl restart mysqld"
    echo ""
    yellow "   [Phase 2: 무중단 임시 완화 조치 (Zero-downtime Mitigation)]"
    echo "   ▶ 당장 OOM이 임박했다면 아래 명령어로 내부 캐시 반환을 유도하세요:"
    echo "      1) mysql -e \"FLUSH LOCAL PRIVILEGES; ${FLUSH_CMD}\""
    echo "      2) mysql -e \"FLUSH TABLES;\""
    echo ""
    if [[ "$MALLOC_LIB" == *"system"* ]]; then
        yellow "   [Phase 3: 인프라 개선 권고 (Best Practice)]"
        echo "   ▶ jemalloc 적용 권장: 현재 glibc malloc을 사용하여 누수에 취약합니다."
        echo "      mysqld_safe 설정 또는 systemd의 Environment=\"LD_PRELOAD=...\"에 jemalloc을 추가하세요."
    fi
else
    green "   >>> [상태 양호] 현재 메모리 단편화 수치가 정상 범위 내에 있습니다."
fi
echo "========================================================================="
