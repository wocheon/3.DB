# 오라클 SQL 관련내용 정리

## 테이블 스페이스 사용권한 부여 
```sql
alter user OWN QUOTA UNLIMITED  on TS_TEST_D;
```


## DATAPUMP REMAP 불가능한경우 해결방법 
* 해당하는 테이블스페이스에 권한 부여 필요 
* dba_ts_quotas 테이블 확인하여 해당 계정에 맞는 TS 권한이 있는지 조회 후 권한 부여 필요.
```sql
select * from dba_ts_quotas;
```
## Tablespace에 대한 권한 부여
```sql
alter user OWN QUOTA UNLIMITED on TS_OWN_D;
alter user TDATA QUOTA UNLIMITED  on TS_TRANS_D;
```
## Tablespace에 대한 권한 회수 
```sql
ALTER USER  OWN QUOTA 0 ON TS_OWN_D ;
ALTER USER  TDATA QUOTA 0 ON TS_TRANS_D ;
```
## listtag 함수 사용법
```sql
SELECT TABLE_NAME, listagg(COLUMN_NAME , ',') WITHIN GROUP(ORDER BY COLUMN_ID ) 
FROM DBA_TAB_COLUMNS 
WHERE OWNER = 'OWN' GROUP BY TABLE_NAME;
```

## ENABLE_PARALLEL HINT 관련 내용
- ENABLE_PARALLEL_DML 
	- ALTER SESSION ENABLE PARALLEL DML; 과 동일한 기능
	`(TM LOCK + PARALLEL)`
>EX)
```sql
 INSERT /*+ ENABLE_PARALLEL_DML PARALLEL(16) */ INTO TEST_TBL SELECT * FROM DUAL;
```		
* 대용량 테이블의 경우 INDEX를 타는 것보다 FULL SCAN 이 나을수 있음 <br>
	`(FULL SCAN : 여러블록 INDEX : 한블록씩 스캔)`

## 테이블 용량확인 쿼리 
```sql
SELECT 
	B.TABLE_NAME 
	,SUM(ROUND(A.BYTES/1024/1024,2)) || 'MB' "SIZEMB"
	,SUM(ROUND(A.BYTES/1024/1024/1024,2)) || 'GB' "SIZEGB"
FROM DBA_SEGMENTS A , DBA_TABLES B 
WHERE A.OWNER = 'OWN' 
	AND A.OWNER = B.OWNER 
	AND A.SEGMENT_NAME = B.TABLE_NAME 
GROUP BY B.TABLE_NAME;
```

  
## PK 조회 
```sql
CREATE TABLE PK_TEST_TBL (ID NUMBER , NAME VARCHAR2(10));
CREATE UNIQUE INDEX PK_TEST_TBL_01 ON PK_TEST_TBL(ID);
ALTER TABLE PK_TEST_TBL ADD CONSTRAINTS PK_TEST_TBL_01 PRIMARY KEY (ID);

SELECT
	A.TABLE_NAME 
	,A.CONSTRAINT_NAME
	,B.COLUMN_NAME
	,B.POSITION
FROM DBA_CONSTRAINTS A 
	,DBA_CONS_COLUMNS B 
WHERE 
	A.TABLE_NAME = 'XXX'
	AND A.CONSTRIANT_TYPE = 'P'
	AND A.OWNER = 'OWN'
	AND A.OWNER = B.OWNER 
	AND A.CONSTRAINT_NAME = B.CONSTRAINT_NAME
ORDER BY B.POSITION;	
```	
	
				
## PK 중복 데이터 제거
$\textcolor{orange}{\textsf{* 실제 PK는 달기 전 상태임.}}$ 

1. 중복데이터 중 나중에 INSERT된 데이터를 삭제
```sql
DELETE FROM [테이블명] A 
WHERE ROWID > (SELECT MIN(ROWID) FROM [테이블명] B 
WHERE A.PK1 = B.PK1 AND A.PK2 = B.PK2);
```					
	
2. 중복데이터 중 이전에 INSERT된 데이터를 삭제				
```sql
DELETE FROM [테이블명] A 
WHERE ROWID < (SELECT MAX(ROWID) FROM [테이블명] B 
WHERE A.PK1 = B.PK1 AND A.PK2 = B.PK2);
```
>EX)

* 테스트용 테이블 생성
```sql
 CREATE TABLE TEST_TBL1 (ID NUMBER, NAME VARCHAR2(10));
INSERT INTO TEST_TBL1 SELECT LEVEL , 'A' || LEVEL FROM DUAL CONNECT BY LEVEL <=10;
```
		
* 의도적으로 중복데이터 추가 
```sql
INSERT INTO test_tbl1 VALUES ( 10 , 'B10');
COMMIT;
SELECT * FROM TEST_TBL1;
```

* 중복 데이터 삭제 (나중에 Insert 된 데이터 삭제)

```sql				
DELETE FROM TEST_TBL1 A WHERE ROWID > (SELECT MIN(ROWID) FROM TEST_TBL1 B WHERE A.ID = B.ID);
```

* 중복 데이터 삭제 (이전에  Insert 된 데이터 삭제)

```sql		
DELETE FROM TEST_TBL1 A WHERE ROWID < (SELECT MAX(ROWID) FROM TEST_TBL1 B WHERE A.ID = B.ID);

COMMIT;			
```

## LPAD, LTRIM  
* LPAD 
	- 왼쪽부터 특정 자리수만큼 특정문자를 삽입
```sql
SELECT LPAD( '1', 3, '0') FROM DUAL; 
=> 001
```
	
* LTRIM
	- 왼쪽부터 반복되는 특정문자 삭제 
 ```sql
 SELECT LTRIM(LPAD( '1', 3, '0'),'0') FROM DUAL; 
 => 1
```

	
* 반대의 경우 RPAD, RTRIM 사용가능 (오른쪽부터)
```sql
SELECT RPAD( '1', 3, '0') FROM DUAL;
SELECT RTRIM(RPAD( '1', 3, '0'),'0') FROM DUAL;
```

## 현재 접속 유저명, OSUSER, 현재시간 조회 
```sql
SELECT USERNAME, OSUSER, TO_CHAR(SYSDATE, 'YYYY/MM/DD HH24:MI:SS') FROM 
 V$SESSION WHERE USERNAME = (SELECT USER FROM DUAL);	
 ```

## 최근 SCN 확인 
```sql
SELECT DISTINCT ORA_ROWSCN, SCN_TO_TIMESTAMP(ORA_ROWSCN) FROM TEST_TBL1;
SELECT * FROM TEST_TBL1 WHERE ORA_ROWSCN = '2017636';
```

```sql
SELECT COUNT(ID) FROM TEST_TBL1 
WHERE ORA_ROWSCN =(SELECT MAX(ORA_ROWSCN) FROM TEST_TBL1);
```

## 테이블 변경내역 확인 
```sql
SELECT * FROM DBA_TAB_MODIFICATIONS WHERE TABLE_NAME = 'TEST_TBL1';
```

## 테이블 전체 카운트 확인용 
```
SELECT 
	A.OWNER 
	,A.TABLE_NAME
    ,TO_NUMBER(dbms_xmlgen.getxmltype('SELECT COUNT(*) c FROM ' || table_name).Extract('//text()')) CNT
FROM DBA_TABLES A
WHERE A.OWNER ='OWN';
```


## INSERT 작업 HINT별 PLAN 변화 

1. /*+ ENABLE_PARALLEL_DML PARALLEL(16) */ : `LOAD AS SELECT`
2. /*+ APPEND PARALLEL(16) */ : `LOAD AS SELECT`
3. /*+ PARALLEL(16) */ : `LOAD AS CONVENTIONAL`


## LOAD AS CONVENTIONAL, LOAD AS SELECT

### LOAD AS CONVENTIONAL(conventional path load)
- 데이터 insert 시 각각의 데이터를 위한 insert 커맨드가 생성되어 parsing 되는 과정 필요.
- BIN ARRAY BUFFER(DATA BLOCK BUFFER)에 INSERT 하는 데이터 입력 후 DISK에 WRITE 하는 방식.
>사용예시 ) 
```
- INDEX가 존재하는 사이즈가 큰 테이블에 적은수의 데이터를 LOAD 하고자 할때
- 작업시 테이블 LOCK이 걸리면 안되는 경우
```

### LOAD AS SELECT (DIRECT PATH LOAD)
- SQL 문장을 GENERATE 하여 사용 X 

- BIND ARRAY BUFFER를 사용하지않고 <br> 메모리에 DATA BLOCK을 만들어 데이터를 넣은 후 그대로 WRITE

- LOAD 시작시 TABLE LOCK 을 검. REDU LOG FILE 불필요.

- UNDO X(ROLLBACK 불가)

- 병렬사용시 성능 향상 가능.
	  

## 오렌지 PLAN&TRACE 확인 
1. EXPLAIN PLAN FOR 
```sql
EXPLAIN PLAN FOR 
SELECT * FROM DUAL;

SELECT* FROM TABLE(DBMS_XPLAN.DISPLAY);
```

2. DBMS_XPLAN.DISPLAY_CURSOR 

```sql
DBMS_XPLAN.DISPLAY_CURSOR 
SELECT /*+ GATHER_PLAN_STATISTICS */ * FROM 	  
( 
[ 확인 쿼리문 ]
);

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL,NULL,'ADVANCED ALLSTATS LAST'));
```

## SQLPLUS PLAN&TRACE 확인 
- 실제 수행 및 출력
```sql
SET AUTOTRACE ON;
```

- 실제수행 X 출력 O
```sql
SET AUTOTRACE TRACEONLY; 
```

## AS OF TIMESTAMP 
- 특정 시점의 데이터를 조회하는 용도로 사용.
- TRUNCATE 혹은 테이블 구조가 변경(DDL)이 발생한경우 이전 시점에대한 조회 불가
```sql
SELECT * FROM OWN.TEST_TBL1 AS OF TIMESTAMP(TO_DATE('20230608 1300' , 'YYYYMMDD HH24MI'));
```

## DB LINK 생성 구문 
```
CREATE DATABASE LINK DL_TEST CONNECT TO OWN IDENTIFIED BY "Test1234" USING '' ;
```
- USING 뒤쪽에는 SID 혹은 TNS 정보 입력.
 

## RECYCLEBIN 정리 ($BIN 테이블 정리) 
* RECYCLEBIN 조회
```sql
select * from DBA_RECYCLEBIN;
```
* 본인 계정의 $BIN 테이블만 삭제
```sql
purge recyclebin;
```

* 모든 $BIN 테이블 삭제 
	- SYS로만 가능
```sql
purge dba_recyclebin;
```

* 특정 스키마에 포함된 $BIN 테이블중 특정 테이블스페이스를 지정하여 삭제.
```sql
purge tablespace TS_OWN_D user own; 
```

## 테이블 스페이스 MOVE 
- 일반 테이블 스페이스 변경 
```sql
ALTER TABLE TEST_TBL1 MOVE TABLESPACE TS_TEST_D;
```

## Partition 테이블 테이블스페이스 변경

* 테스트용 테이블 생성
```sql
CREATE TABLE PARTITION_TEST 
    (ID NUMBER 
    , ST_YEAR VARCHAR2(10)
    , ST_MONTH VARCHAR2(10)
    )
    PARTITION BY RANGE ( ST_YEAR, ST_MONTH)
    ( PARTITION PR202301 VALUES LESS THAN ('2023','02')
     ,PARTITION PR202302 VALUES LESS THAN ('2023','03')
     ,PARTITION PR202303 VALUES LESS THAN ('2023','04')    
     ,PARTITION PR202304 VALUES LESS THAN ('2023','05')    
     ,PARTITION PR202305 VALUES LESS THAN ('2023','06')    
     ,PARTITION PR202306 VALUES LESS THAN ('2023','07')    
     ,PARTITION PR202307 VALUES LESS THAN ('2023','08')    
     ,PARTITION PR202308 VALUES LESS THAN ('2023','09')    
     ,PARTITION PR202309 VALUES LESS THAN ('2023','10')    
     ,PARTITION PR202310 VALUES LESS THAN ('2023','11')    
     ,PARTITION PR202311 VALUES LESS THAN ('2023','12')    
     ,PARTITION PR202312 VALUES LESS THAN ('2024','01')
    -- ,PARTITION PRMAX VALUES LESS THAN (MAXVALUE, MAXVALUE)
     );
```

* 데이터 입력
```sql
INSERT INTO PARTITION_TEST VALUES ( 1, '2023', '01');
INSERT INTO PARTITION_TEST VALUES ( 1, '2023', '05');
INSERT INTO PARTITION_TEST VALUES ( 1, '2023', '12');
INSERT INTO PARTITION_TEST VALUES ( 1, '2024', '01');
COMMIT;
```

* 입력된 데이터 조회
```sql
SELECT * FROM PARTITION_TEST PARTITION (PR202301);
SELECT * FROM PARTITION_TEST PARTITION (PR202305);
SELECT * FROM PARTITION_TEST PARTITION (PR202312);
SELECT * FROM PARTITION_TEST PARTITION (PRMAX);
```

* 파티션별로 테이블 스페이스 move
```sql
alter table PARTITION_TEST move partition PR202301 tablespace TS_TEST_D;
alter table PARTITION_TEST move partition PR202302 tablespace TS_TEST_D;
alter table PARTITION_TEST move partition PR202303 tablespace TS_TEST_D;
...
alter table PARTITION_TEST move partition PR202312 tablespace TS_TEST_D;
```

## 파티션 추가 
```sql
alter table PARTITION_TEST ADD PARTITION PRMAX VALUES LESS THAN (MAXVALUE, MAXVALUE) tablespace TS_OWN_D;
```

## 테이블 DDL 추출 구문 
```sql
select * from dbms_metadata.get_ddl('TABLE', 'TEST_TBL1', 'OWN') from dual;
```

## DATAPUMP QUERY 옵션 사용법 
- 형식 
	-  QUERY=[테이블명]:"조건문"

- 리눅스에서 사용시 특수문자 앞에 백슬래시를 붙여야 정상적으로 인식함.

>EX) 
```sql
nohup expdp own/test1234 dictonary=DIR_PUMP COMPRESSION=ALL parallel=16 
TABLES=OWN.TEST_TBL1
QUERY=OWN.TETST_TBL1:\"where NAME like \'A\%\'\"
DUMPFILE= TESTTBL_EXP.dmp 
LOGFILE=TESTTBL_EXP.log 
INCLUDE=TABLE_EXPORT/TABLE/TABLE,TABLE_EXPORT/TABLE/TABLE_DATA,TABLE_EXPORT/TABLE/TABLE/COMMENT
> TESTTBL_EXP.out &
```


## 테이블 스페이스 삭제 
```
DROP TABLESPACE TS_TEST_D INCLUDING CONTENTS AND DATAFILES;
```

## Datapump Partition 테이블 log sort
```bash
cat PUMP_TEST_20230609.out | grep ported | gawk -F '"'  '{print $4}' | sort -u
cat PUMP_TEST_20230609.out | grep ported | gawk -F '"'  '{print $4}' | gawk '!x[$0]++'
```


## table reorg 작업 

### Query 예시
```sql
alter tablE [ table_name ] move ONLINE
```
### MOVE 
- SEGMENT_SIZE를 REORG 하는 작업. 
- DELETE를 한다고해도 사용중인 SEGMENT_SIZE가 변하진않음 (SHINK)
- 그러므로 비어있는만큼 SEGMENT_SIZE를 줄일때 해당 방식을 사용.
- 단 ONLINE을 사용하지않으면 TM LOCK이 발생	
- 완료 후 ROWID가 변경되어 인덱스가 INVALID 상태로 변경
- INVALID 된 인덱스를 재설정 하기 위해 <br> `ALTER INDEX [ 인덱스명 ] REBUILD` 구문을 추가로 실행  <br>
	 
   
### MOVE ONLINE
- `move`와 동일한 형태로 작업이 진행되나 TM락을 거는 것을 방지함.
- 자체적으로 INDEX REBUILD 수행.


>EX) 

* 테스트용 테이블 생성
```sql
CREATE TABLE TEST_TBL1 AS SELECT * FROM TDATA.TEST_TBL1 WHERE 1=2;
CREATE UNIQUE INDEX PK_TEST_TBL1 ON  TEST_TBL1(ID);

ALTER TABLE TEST_TBL1 ADD CONSTRAINT PK_TEST_TBL1 PRIMARY KEY (ID);

INSERT INTO TEST_TBL1 SELECT LEVEL , 'Z' || LEVEL FROM DUAL CONNECT BY LEVEL <= 600000 ;

COMMIT;
```

* 테이블 Size 및 인덱스 상태 확인
	- SIZE : 12MB, INDEX VAILD 상태 확인
```sql
SELECT OWNER, SEGMENT_NAME, BYTES/1024/1024 FROM DBA_SEGMENTS WHERE SEGMENT_NAME = 'TEST_TBL1' AND OWNER = 'OWN';
SELECT OWNER, INDEX_NAME, TABLE_NAME, STATUS FROM DBA_INDEXES WHERE TABLE_NAME = 'TEST_TBL1';
```

* 일부 데이터 삭제
```sql
DELETE FROM TEST_TBL1 WHERE NAME NOT LIKE 'Z%' OR ID > 100;
COMMIT;
--> 삭제 후에도 사이즈는 12MB로 동일. INDEX도 정상.
```

* move로 reorg 실행
```sql
alter TABLE TEST_TBL1 MOVE;
--> 사이즈 0.0625MB 로 감소. INDEX UNUSABLE 상태로 변경됨.
```

* index REBUILD 진행
```sql
ALTER INDEX PK_TEST_TBL1 REBUILD;
--> INDEX VAILD 상태로 변경됨.
```

* move online으로 테이블 reorg 진행

```sql
alter TABLE TEST_TBL1 MOVE ONLINE;
--> MOVE ONLINE으로 진행 시 사이즈 0.0625MB 로 감소. INDEX VAILD 상태 유지.
```


## PARTITION TRUNCATE 
```sql
 ALTER TABLE [TABLE_NAME] TRUNCATE PARTITION [PARTITION_NAME] UPDATE INDEXES;	
 ```
 
* UPDATE INDEXES
	- PARTITION TRUNCATE 진행시 인덱스 깨지는것을 방지.
 
 
 ## TIBERO SESSION KILL 옵션  
 - ABORT 옵션 
	- 강제 종료
 ```sql
 ALTER SYSTEM KIL SESSION (SID, SERIAL#) ABORT; 
 ```


 ## 여러 컬럼 한번에 삭제 처리 
 ```sql
 ALTER TABLE [TABLE_NAME ] DROP (COL1, COL2);
 ```
  ## NOT NULL NOVALIDATE 처리방법 
 ```sql
 ALTER TABLE TEST_TBL1 MODIFY (NAME NOT NULL NOVALIDATE);
 ```
- 기존 NULL값은 유지하면서 이후에 들어오는 값만 NOT NULL인지 확인함.
- 확인방법 : DBA_CONSTRAINTS의 VALIDATED에 NOT VALIDATE 로 표기됨
 
## 일반 인덱스 생성후 UNIQUE ENABLE (UK생성) 
- 기존 데이터가 중복값이 들어있어서 UNIQUE 처리가 불가한 경우 사용
-  일반 인덱스 생성 > NOVALIDATE로 등록 

>EX)
* 중복값이 포함된 테이블 생성
```sql
SELECT ID, COUNT(*) FROM TEST_TBL1 
GROUP BY ID 
HAVING COUNT(*) >1;

-- ID  | COUNT(*) 
-----------------
-- 100 | 2
```

* 일반 인덱스 생성 후, Unique 인덱스로 변경
```sql
CREATE INDEX UK_TEST_TBL1 ON TEST_TBL1 (ID);
ALTER TABLE TEST_TBL1 ADD CONSTRAINT UK_TEST_TBL1 UNIQUE (ID) USING INDEX ;
--> 중복값이 존재하여 오류 발생
```

* NOVALIDATE 처리
```sql
ALTER TABLE TEST_TBL1 ADD CONSTRAINT UK_TEST_TBL1 UNIQUE (ID) USING INDEX NOVALIDATE;  
```

* NOVALIDATE 인덱스 삭제
```sql
DROP INDEX UK_TEST_TBL1;
--> ORA-02429: 고유/기본 키 적용을 위한 인덱스를 삭제할 수 없습니다.
```
* CONSTRAINT 먼저 삭제후 진행 필요.

```sql
ALTER TABLE TEST_TBL1 DROP CONSTRAINT UK_TEST_TBL1;
DROP INDEX UK_TEST_TBL1;
```  
 

## PARALLEL HINT에 사용가능한 최대 DEGREE 값 계산 
```sql
select 
    A.* ,
    case when A. parallel_degree_limit = 'CPU' then 
        to_char(parallel_threads_per_cpu * cpu_count * cluster_database_instances)
    else parallel_degree_policy end DEGREE_LIMIT
from 
    (select 
    (select value from v$parameter where name = 'parallel_degree_limit') parallel_degree_limit,
    (select value from v$parameter where name = 'parallel_degree_policy') parallel_degree_policy,
    (select value from v$parameter where name = 'parallel_threads_per_cpu') parallel_threads_per_cpu,
    (select value from v$parameter where name = 'cpu_count') cpu_count,
    (select value from v$parameter where name = 'cluster_database_instances') cluster_database_instances
    from dual) A;
 ```
 
  ##  데이터파일 이름변경
1. TABLESPACE를 OFFLINE으로 변경 
2. 변경할 데이터 파일 복사 혹은 이름 변경 (cp or mv)
3. alter 문을 통해  데이터파일명을 재설정 => TABLESPACE ONLINE으로 변경 

```sql
alter tablespace TS_OWN_D OFFLINE;
alter database rename file 'C:\ORACLE\ORADATA\ORCL\TS_OWN_D.DBF' to 'C:\ORACLE\ORADATA\ORCL\TS_OWN_D_01.DBF';
alter tablespace TS_OWN_D ONLINE;


alter tablespace TS_trans_D OFFLINE;
alter tablespace TS_trans_D rename datafile 'C:\ORACLE\ORADATA\ORCL\TS_TRANS_D.DBF' to 'C:\ORACLE\ORADATA\ORCL\TS_TRANS_D_01.DBF';
alter tablespace TS_trans_D ONLINE;
```	