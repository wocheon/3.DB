!/bin/bash

# ==============================================================================
# MariaDB/MySQL Comprehensive Health Check Script (Ultimate Version)
# ==============================================================================
function red (){ echo -e "\E[;31m$1\E[0m"; }
function green (){ echo -e "\E[;32m$1\E[0m"; }
function yellow (){ echo -e "\E[;33m$1\E[0m"; }
function title (){ echo -e "\n\E[;36m=========================================================================\n   $1 \n=========================================================================\E[0m"; }

# 접속 정보 (필요시 수정)
MYSQL_USER="root"
MYSQL_PASS=""
MYSQL_CONN="mysql -u$MYSQL_USER -N -e"
if [ -n "$MYSQL_PASS" ]; then MYSQL_CONN="mysql -u$MYSQL_USER -p$MYSQL_PASS -N -e"; fi

MYSQL_CONN_WITH_HEADER="mysql -u$MYSQL_USER -e"
if [ -n "$MYSQL_PASS" ]; then MYSQL_CONN_WITH_HEADER="mysql -u$MYSQL_USER -p$MYSQL_PASS -e"; fi

title "Phase 1: OS Infrastructure & Service Status  |  $(date '+%Y-%m-%d %H:%M:%S')"

# ---------------------------------------------------------
# 1. OS 레벨 점검 (Memory & File System)
# ---------------------------------------------------------
echo "[1. OS Memory Status (free -h)]"
free -h | awk 'NR==1 || NR==2'
echo ""
echo "[2. File System Status (df -h)]"
df -hT | egrep -v 'tmpfs|devtmpfs|squashfs|vfat|gcsfuse' | awk '$6+0 > 80 {print "\033[31m"$0"\033[0m"} $6+0 <= 80 {print $0}'

# ---------------------------------------------------------
# 2. 프로세스 및 기본 엔진 정보
# ---------------------------------------------------------
PID=$(pgrep -f "mariadbd|mysqld" | head -n1)
if [ -z "$PID" ]; then red "\n[오류] MariaDB/MySQL 프로세스를 찾을 수 없습니다!"; exit 1; fi

VERSION=$($MYSQL_CONN "SELECT @@version;")
PORT=$($MYSQL_CONN "SELECT @@port;")
UPTIME=$($MYSQL_CONN "SHOW GLOBAL STATUS LIKE 'Uptime';" | awk '{print $2}')
UPTIME_DAYS=$(echo "scale=1; $UPTIME / 86400" | bc)
BINLOG_STATUS=$($MYSQL_CONN "SELECT @@log_bin;")

echo ""
echo "[3. Database Core Information]"
echo " - 엔진 프로세스 : $(ps -o comm= -p $PID) (PID: $PID)"
echo " - 엔진 버전     : $VERSION"
echo " - 수신 포트     : $PORT"
echo " - 가동 시간     : $UPTIME_DAYS 일"
if [ "$BINLOG_STATUS" == "1" ]; then
    green " - Binlog(Archive): ON (정상)"
else
    red " - Binlog(Archive): OFF (주의: 백업/복구 제약)"
fi

title "Phase 2: Database Capacity & Limits Check"

# ---------------------------------------------------------
# 3. 스키마(테이블스페이스) 용량 점검
# ---------------------------------------------------------
echo "[4. Tablespace (Schema) Usage]"
$MYSQL_CONN_WITH_HEADER "
SELECT
    table_schema AS 'DATABASE_NAME',
    ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'TOTAL_SIZE(MB)',
    ROUND(SUM(data_length) / 1024 / 1024, 2) AS 'DATA_SIZE(MB)',
    ROUND(SUM(index_length) / 1024 / 1024, 2) AS 'INDEX_SIZE(MB)'
FROM information_schema.tables
WHERE table_schema NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys')
GROUP BY table_schema
ORDER BY 2 DESC;" | column -t
echo ""

# ---------------------------------------------------------
# 4. 시퀀스 (AUTO_INCREMENT) 고갈 점검
# ---------------------------------------------------------
echo "[5. Auto-Increment (Sequence) Exhaustion Check]"
AI_RESULT=$($MYSQL_CONN "
SELECT c.TABLE_SCHEMA, c.TABLE_NAME, c.COLUMN_NAME, t.AUTO_INCREMENT,
ROUND((t.AUTO_INCREMENT / CASE c.DATA_TYPE
    WHEN 'tinyint' THEN 255 WHEN 'smallint' THEN 65535 WHEN 'mediumint' THEN 16777215
    WHEN 'int' THEN 2147483647 WHEN 'bigint' THEN 9223372036854775807 END) * 100, 2) AS RATIO
FROM information_schema.COLUMNS c
JOIN information_schema.TABLES t ON c.TABLE_SCHEMA = t.TABLE_SCHEMA AND c.TABLE_NAME = t.TABLE_NAME
WHERE c.EXTRA LIKE '%auto_increment%' AND t.AUTO_INCREMENT IS NOT NULL
HAVING RATIO > 70.00;")

if [ -n "$AI_RESULT" ]; then
    red "   [!] 주의: 한계치에 근접한(70% 초과) 컬럼이 존재합니다! (PK 타입 변경 고려)"
    $MYSQL_CONN_WITH_HEADER "
    SELECT c.TABLE_SCHEMA AS 'SCHEMA', c.TABLE_NAME AS 'TABLE', c.COLUMN_NAME AS 'COLUMN',
    t.AUTO_INCREMENT AS 'CURRENT_VAL',
    ROUND((t.AUTO_INCREMENT / CASE c.DATA_TYPE WHEN 'tinyint' THEN 255 WHEN 'smallint' THEN 65535 WHEN 'mediumint' THEN 16777215
    WHEN 'int' THEN 2147483647 WHEN 'bigint' THEN 9223372036854775807 END) * 100, 2) AS 'USED_RATIO(%)'
    FROM information_schema.COLUMNS c JOIN information_schema.TABLES t ON c.TABLE_SCHEMA = t.TABLE_SCHEMA AND c.TABLE_NAME = t.TABLE_NAME
    WHERE c.EXTRA LIKE '%auto_increment%' AND t.AUTO_INCREMENT IS NOT NULL
    HAVING \`USED_RATIO(%)\` > 70.00;" | column -t
else
    green "   [v] 정상: 고갈 위험이 있는 Auto-Increment 컬럼이 없습니다."
fi

title "Phase 3: Performance & Resource Monitoring"

# ---------------------------------------------------------
# 5. 세션 및 커넥션 상태
# ---------------------------------------------------------
MAX_CONN=$($MYSQL_CONN "SELECT @@max_connections;")
MAX_USED_CONN=$($MYSQL_CONN "SHOW GLOBAL STATUS LIKE 'Max_used_connections';" | awk '{print $2}')
TH_CONN=$($MYSQL_CONN "SHOW GLOBAL STATUS LIKE 'Threads_connected';" | awk '{print $2}')
TH_RUN=$($MYSQL_CONN "SHOW GLOBAL STATUS LIKE 'Threads_running';" | awk '{print $2}')
CONN_RATIO=$(echo "scale=2; ($MAX_USED_CONN / $MAX_CONN) * 100" | bc)

echo "[6. 현재 세션 및 커넥션 상태]"
echo " - 연결된 세션(Connected) : $TH_CONN 개"
echo " - 실행 중인 세션(Running): $TH_RUN 개"
echo " - 커넥션 풀 최대 사용률  : $CONN_RATIO % (최대 허용: $MAX_CONN)"
if (( $(echo "$CONN_RATIO > 80.0" | bc -l) )); then
    red "   [!] 경고: 커넥션 풀 사용률이 80%를 초과했습니다. max_connections 증설이 필요할 수 있습니다."
else
    green "   [v] 정상: 커넥션 여유가 충분합니다."
fi
echo ""

# ==============================================================================
# 6. DB 메모리 점유 현황 (버전 자동 감지 + Memory Bloat)
# ==============================================================================
PAGE_SIZE=$($MYSQL_CONN "SELECT @@innodb_page_size;")
TOTAL_PAGES=$($MYSQL_CONN "SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_pages_total';" | awk '{print $2}')
MEM_USED_KB=$($MYSQL_CONN "SHOW GLOBAL STATUS LIKE 'Memory_used';" 2>/dev/null | awk '{print $2}')
if [ -z "$MEM_USED_KB" ]; then MEM_USED_KB=0; fi

BUFFER_POOL_GB=$(echo "scale=2; ($TOTAL_PAGES * $PAGE_SIZE) / 1024 / 1024 / 1024" | bc)
MEM_USED_GB=$(echo "scale=2; $MEM_USED_KB / 1024 / 1024 / 1024" | bc)

# [수정됨] OS RSS 메모리를 안전하게 합산 (다중 PID 및 공백 문자 에러 방지)
PIDS=$(pgrep -d ',' -f "mariadbd|mysqld")
RSS_KB_TOTAL=$(ps -o rss= -p $PIDS 2>/dev/null | awk '{sum+=$1} END {print sum}')
if [ -z "$RSS_KB_TOTAL" ]; then RSS_KB_TOTAL=0; fi
RSS_GB=$(echo "scale=2; $RSS_KB_TOTAL / 1024 / 1024" | bc)

# MariaDB 10.6.16+ 버퍼풀 이중합산 방지 로직
V_MAJOR=$(echo $VERSION | cut -d. -f1); V_MINOR=$(echo $VERSION | cut -d. -f2); V_PATCH=$(echo $VERSION | cut -d. -f3 | cut -d- -f1 | sed 's/[^0-9]//g')
IS_NEW_MEM_CALC=0
if [[ "$V_MAJOR" -gt 10 ]] || [[ "$V_MAJOR" -eq 10 && "$V_MINOR" -gt 6 ]] || [[ "$V_MAJOR" -eq 10 && "$V_MINOR" -eq 6 && "$V_PATCH" -ge 16 ]]; then
    IS_NEW_MEM_CALC=1
fi

echo "[7. 메모리 점유 현황 (Memory Bloat Check)]"

if [ $IS_NEW_MEM_CALC -eq 1 ]; then
    yellow "   [i] 진단 모드: 최신 버전 (Memory_used에 Buffer Pool이 포함된 통합 지표 사용)"
    EXPECTED_TOTAL_GB=$MEM_USED_GB
    SESSION_MISC_GB=$(echo "scale=2; $MEM_USED_GB - $BUFFER_POOL_GB" | bc)
else
    yellow "   [i] 진단 모드: 10.6.15 이하 구버전 (Buffer Pool + Memory_used 분리 합산 방식 사용)"
    EXPECTED_TOTAL_GB=$(echo "scale=2; $BUFFER_POOL_GB + $MEM_USED_GB" | bc)
    SESSION_MISC_GB=$MEM_USED_GB
fi

# RSS와 Expected Total의 격차 계산 (Memory Bloat 판단 기준)
GAP_RSS_MEM=$(echo "scale=2; $RSS_GB - $EXPECTED_TOTAL_GB" | bc)

echo " - 설정된 버퍼풀 (Global): $BUFFER_POOL_GB GB"
echo " - 세션/기타 동적 할당량 : $SESSION_MISC_GB GB"
echo " - 내부 예상 총 점유량   : $EXPECTED_TOTAL_GB GB"
echo " - OS 실제 점유량 (RSS)  : $RSS_GB GB"

if (( $(echo "$GAP_RSS_MEM > 2.0" | bc -l) )); then
    red "   [!] 위험: Memory Bloat (미반환 메모리) 감지됨. (격차: ${GAP_RSS_MEM} GB)"
else
    green "   [v] 정상: OS 점유량(RSS)이 MariaDB 내부 예상치와 일치합니다."
fi

# pmap 기반 파편화 블록 탐지 (100MB 이상 anon 블록)
# PID는 메인 데몬 기준 1개만 추출하여 검사
MAIN_PID=$(pgrep -f "mariadbd|mysqld" | head -n 1)
PMAP_ANON_COUNT=$(pmap -x $MAIN_PID 2>/dev/null | awk -v conf_kb=$((TOTAL_PAGES * PAGE_SIZE / 1024)) '$2 > 102400 && $2 < conf_kb && $5 ~ /anon/ {count++} END {print count+0}')

if [ "$PMAP_ANON_COUNT" -gt 5 ]; then
    red "   [!] 경고: OS 레벨 메모리 단편화 의심 (대형 anon 블록 ${PMAP_ANON_COUNT}개)"
else
    green "   [v] 정상: 유의미한 OS 레벨 단편화가 관찰되지 않았습니다."
fi
echo ""


# ---------------------------------------------------------
# 7. 임시 테이블 사용 효율
# ---------------------------------------------------------
TMP_TABLES=$($MYSQL_CONN "SHOW GLOBAL STATUS LIKE 'Created_tmp_tables';" | awk '{print $2}')
TMP_DISK_TABLES=$($MYSQL_CONN "SHOW GLOBAL STATUS LIKE 'Created_tmp_disk_tables';" | awk '{print $2}')

if [ "$TMP_TABLES" -gt 0 ]; then
    TMP_DISK_RATIO=$(echo "scale=2; ($TMP_DISK_TABLES / $TMP_TABLES) * 100" | bc)
else
    TMP_DISK_RATIO=0
fi

echo "[8. 임시 테이블 사용 효율]"
echo " - 메모리 내 생성됨 : $TMP_TABLES 회"
echo " - 디스크에 생성됨  : $TMP_DISK_TABLES 회"
echo " - 디스크 전환 비율 : $TMP_DISK_RATIO %"
if (( $(echo "$TMP_DISK_RATIO > 10.0" | bc -l) )); then
    yellow "   [!] 주의: 디스크 기반 임시 테이블 비율이 10%를 초과합니다."
    echo "       (조치: 쿼리 튜닝 또는 tmp_table_size, max_heap_table_size 상향 검토)"
else
    green "   [v] 정상: 임시 테이블이 효율적으로 처리되고 있습니다."
fi
echo ""

# ---------------------------------------------------------
# 8. 성능 지표 및 트랜잭션 락 (Performance & Locks)
# ---------------------------------------------------------
READ_REQS=$($MYSQL_CONN "SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_read_requests';" | awk '{print $2}')
READS=$($MYSQL_CONN "SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_reads';" | awk '{print $2}')
SLOW_Q=$($MYSQL_CONN "SHOW GLOBAL STATUS LIKE 'Slow_queries';" | awk '{print $2}')
ROW_LOCKS=$($MYSQL_CONN "SHOW GLOBAL STATUS LIKE 'Innodb_row_lock_current_waits';" | awk '{print $2}')

if [ "$READ_REQS" -gt 0 ]; then
    HIT_RATIO=$(echo "scale=4; 100 - (($READS / $READ_REQS) * 100)" | bc | awk '{printf "%.2f", $0}')
else
    HIT_RATIO="100.00"
fi

echo "[9. 성능 지표 및 트랜잭션 락 (Performance & Locks)]"
echo " - 버퍼풀 캐시 히트율 : $HIT_RATIO % (권장: 95% 이상)"
if (( $(echo "$HIT_RATIO < 95.0" | bc -l) )); then
    red "   [!] 경고: 버퍼풀 히트율이 낮아 디스크 I/O가 발생하고 있습니다."
else
    green "   [v] 정상: 버퍼풀 적중률이 우수합니다."
fi

echo " - 누적 슬로우 쿼리   : $SLOW_Q 건"
echo " - 현재 트랜잭션 락   : $ROW_LOCKS 건 대기 중"
if [ "$ROW_LOCKS" -gt 0 ]; then
    red "   [!] 경고: 현재 트랜잭션 경합(Lock Wait)이 발생 중입니다! (데드락 확인 요망)"
else
    green "   [v] 정상: 트랜잭션 지연이 없습니다."
fi

title "Phase 4: Logs & Master/Slave Replication Status"

# ---------------------------------------------------------
# 9. DB Error Log 점검 (최근 100줄)
# ---------------------------------------------------------
echo "[10. Error Log Check (Recent 100 lines)]"
LOG_PATH=$($MYSQL_CONN "SELECT @@log_error;")
if [ -z "$LOG_PATH" ] || [ ! -f "$LOG_PATH" ]; then
    LOG_PATH="/var/log/mariadb/mariadb.log"
    [ ! -f "$LOG_PATH" ] && LOG_PATH="/var/log/mysql/error.log"
fi

if [ -f "$LOG_PATH" ]; then
#    ERRORS=$(tail -100 "$LOG_PATH" | egrep -i 'error|warning|ora-')
    ERRORS=$(tail -100 "$LOG_PATH" | egrep -i 'error|ora-')
    if [ -n "$ERRORS" ]; then
        yellow "$ERRORS"
    else
        green "   [v] 최근 100줄 내에 특이사항(Error/Warning)이 발견되지 않았습니다. ($LOG_PATH)"
    fi
else
    echo "   [?] 에러 로그 파일을 찾을 수 없거나 권한이 없습니다. ($LOG_PATH)"
fi
echo ""

# ---------------------------------------------------------
# 10. Master/Slave 복제 상태 점검
# ---------------------------------------------------------
echo "[11. Master / Slave Replication Status Check]"
REPLICA_STATUS=$($MYSQL_CONN "SHOW SLAVE STATUS\G" 2>/dev/null)

if [ -z "$REPLICA_STATUS" ]; then
    echo "   [i] 정보: 이 서버는 Slave(Replica)로 구성되어 있지 않습니다. (Standalone or Master)"
else
    IO_RUNNING=$(echo "$REPLICA_STATUS" | grep -w "Slave_IO_Running:" | awk '{print $2}')
    SQL_RUNNING=$(echo "$REPLICA_STATUS" | grep -w "Slave_SQL_Running:" | awk '{print $2}')
    SEC_BEHIND=$(echo "$REPLICA_STATUS" | grep -w "Seconds_Behind_Master:" | awk '{print $2}')
    MASTER_HOST=$(echo "$REPLICA_STATUS" | grep -w "Master_Host:" | awk '{print $2}')
    LAST_ERROR=$(echo "$REPLICA_STATUS" | grep -w "Last_SQL_Error:" | awk -F': ' '{print $2}')

    echo " - 연결된 Master Host : $MASTER_HOST"

    if [ "$IO_RUNNING" == "Yes" ]; then green " - IO_Running Thread  : YES (정상)"; else red " - IO_Running Thread  : NO (네트워크 단절 확인)"; fi

    if [ "$SQL_RUNNING" == "Yes" ]; then
        green " - SQL_Running Thread : YES (정상)"
    else
        red " - SQL_Running Thread : NO (복제 중단 상태!)"
        [ -n "$LAST_ERROR" ] && red "   -> [상세 에러]: $LAST_ERROR"
    fi

    if [ "$SEC_BEHIND" == "NULL" ]; then
        red " - Seconds Behind     : NULL (복제 중단됨)"
    elif [ "$SEC_BEHIND" -eq 0 ]; then
        green " - Seconds Behind     : 0 초 (완벽하게 동기화됨)"
    elif [ "$SEC_BEHIND" -lt 60 ]; then
        yellow " - Seconds Behind     : $SEC_BEHIND 초 (약간의 지연 발생)"
    else
        red " - Seconds Behind     : $SEC_BEHIND 초 (심각한 동기화 지연!)"
    fi
fi


title "Phase 5: Database Object Integrity (Invalid/Orphaned Check)"

# ---------------------------------------------------------
# 11. Invalid / Broken Views Check
# ---------------------------------------------------------
echo "[12. Invalid Views Check]"
# 뷰가 참조하는 원본 테이블/컬럼이 삭제되어 깨진(Invalid) 뷰를 찾습니다.
INVALID_VIEWS=$($MYSQL_CONN "
SELECT table_schema, table_name, table_comment
FROM information_schema.tables
WHERE table_type = 'VIEW'
  AND table_schema NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys')
  AND table_comment LIKE '%invalid%';")

if [ -n "$INVALID_VIEWS" ]; then
    red "   [!] 경고: 참조 테이블/컬럼이 삭제되어 깨진(Invalid) 뷰가 발견되었습니다!"
    $MYSQL_CONN_WITH_HEADER "
    SELECT table_schema AS 'SCHEMA', table_name AS 'VIEW_NAME', table_comment AS 'ERROR_REASON'
    FROM information_schema.tables
    WHERE table_type = 'VIEW'
      AND table_schema NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys')
      AND table_comment LIKE '%invalid%';" | column -t
else
    green "   [v] 정상: 깨진 뷰(Invalid View)가 존재하지 않습니다."
fi
echo ""

# ---------------------------------------------------------
# 12. Orphaned Procedures & Functions (Definer Check)
# ---------------------------------------------------------
echo "[13. Orphaned Procedures & Functions Check]"
# 루틴을 생성한 계정(Definer)이 DB에서 삭제되어 실행 권한이 깨진 프로시저/펑션을 찾습니다.
ORPHANED_ROUTINES=$($MYSQL_CONN "
SELECT r.ROUTINE_SCHEMA, r.ROUTINE_NAME, r.ROUTINE_TYPE, r.DEFINER
FROM information_schema.routines r
LEFT JOIN mysql.user u ON SUBSTRING_INDEX(r.DEFINER, '@', 1) = u.user
  AND SUBSTRING_INDEX(r.DEFINER, '@', -1) = u.host
WHERE u.user IS NULL
  AND r.ROUTINE_SCHEMA NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys');")

if [ -n "$ORPHANED_ROUTINES" ]; then
    red "   [!] 주의: 생성자(Definer) 계정이 삭제되어 권한 오류가 발생할 수 있는 고아 루틴이 발견되었습니다!"
    $MYSQL_CONN_WITH_HEADER "
    SELECT r.ROUTINE_SCHEMA AS 'SCHEMA', r.ROUTINE_NAME AS 'NAME', r.ROUTINE_TYPE AS 'TYPE', r.DEFINER AS 'MISSING_DEFINER'
    FROM information_schema.routines r
    LEFT JOIN mysql.user u ON SUBSTRING_INDEX(r.DEFINER, '@', 1) = u.user AND SUBSTRING_INDEX(r.DEFINER, '@', -1) = u.host
    WHERE u.user IS NULL AND r.ROUTINE_SCHEMA NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys');" | column -t
else
    green "   [v] 정상: 권한이 깨진(Orphaned) 프로시저 및 펑션이 없습니다."
fi
echo ""

# ---------------------------------------------------------
# 13. Ignored / Disabled Indexes Check (MariaDB 10.6+ 호환)
# ---------------------------------------------------------
echo "[14. Ignored / Invisible Indexes Check]"
# 개발자가 의도적으로 껐거나(Invisible/Ignored) 비활성화된 인덱스를 찾습니다.
# 버전에 따라 컬럼명이 다르므로(MySQL 8.0: IS_VISIBLE, MariaDB: IGNORED) 에러를 방지하기 위해 쿼리 조정

INDEX_COL_CHECK=$($MYSQL_CONN "SELECT count(*) FROM information_schema.columns WHERE table_name='STATISTICS' AND column_name='IGNORED';")
if [ "$INDEX_COL_CHECK" -eq 1 ]; then
    IGNORED_INDEXES=$($MYSQL_CONN "
    SELECT INDEX_SCHEMA, TABLE_NAME, INDEX_NAME
    FROM information_schema.statistics
    WHERE IGNORED = 'YES' AND INDEX_SCHEMA NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys');")

    if [ -n "$IGNORED_INDEXES" ]; then
        yellow "   [i] 정보: 옵티마이저가 사용하지 않도록 비활성화(Ignored)된 인덱스가 있습니다."
        $MYSQL_CONN_WITH_HEADER "
        SELECT INDEX_SCHEMA AS 'SCHEMA', TABLE_NAME AS 'TABLE', INDEX_NAME AS 'IGNORED_INDEX'
        FROM information_schema.statistics
        WHERE IGNORED = 'YES' AND INDEX_SCHEMA NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys');" | column -t
    else
        green "   [v] 정상: 비활성화된 인덱스가 없습니다."
    fi
else
    echo "   [i] 이 데이터베이스 버전은 인덱스 비활성화(Ignored/Invisible) 기능을 지원하지 않아 점검을 건너뜁니다."
fi
echo ""

echo -e "\n==================== 점검 종료 ===================="
