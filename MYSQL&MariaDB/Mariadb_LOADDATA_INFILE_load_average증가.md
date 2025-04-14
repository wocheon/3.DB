# MariaDB General Log 백업시 Load Average 증가 문제


## 개요
- general_log를 백업하는 스크립트 동작중 발생하는 Load Average 증가 문제 관련사항
    - 스크립트 동작시 Load Average가 증가하나 CPU 사용률이 늘어나지는 않고 Disk I/O 만 증가하는 현상 발생
    - 스크립트 상에서는 기본 general_log를 txt로 백업 후 별도 스키마의 테이블에 Insert하는 작업을 수행

- 모든 DB는 general_log 를 테이블에 저장하도록 옵션 지정 


##  DB 별 General_log 백업 구성
- 모든 DB의 General_log 백업은 백업용 bash 스크립트를 Crontab에 등록하여 동작

### 개발 DB 
1. 동작 전 general_log off `(SET global general_log = OFF)`
2. 개발 DB의 mysql.general_log 테이블을 백업 `(SELECT INTO OUTFILE)`
3. 기존 개발DB mysql.general_log는 Truncate
4. general_log on `(SET global general_log = ON, global log_output = 'TABLE' )`
5. 매주 일요일 monitoring.general_log, monitoring.general_log_201 테이블 Truncate
6. 개발 DB의 monitoring.general_log 테이블에 Insert `(LOAD DATA INFILE)`
7. 운영 DB의 general_log 백업파일을 scp로 전달받아 개발DB monitoring.general_log_201 테이블에 insert `(LOAD DATA INFILE)`
8. 해당 파일을 백업용 버킷에 복사 
9. 백업 스크립트 동작 로그 테이블에 결과 기록 `(일자,백업종류,hostname)`

### 수집 DB
1. 동작 전 general_log off `(SET global general_log = OFF)`
2. 수집 DB의 mysql.general_log 테이블을 백업 `(SELECT INTO OUTFILE)`
3. 기존 수집DB mysql.general_log는 Truncate
4. 매주 일요일 monitoring.general_log 테이블 Truncate
5. general_log on `(SET global general_log = ON, global log_output = 'TABLE' )`
6. 수집 DB의 monitoring.general_log 테이블에 Insert `(LOAD DATA INFILE)`
7. 해당 파일을 백업용 버킷에 복사 
8. 백업 스크립트 동작 로그 테이블에 결과 기록 `(일자,백업종류,hostname)`

### 운영 DB
1. 동작 전 general_log off `(SET global general_log = OFF)`
2. 개발 DB의 mysql.general_log 테이블을 백업 `(SELECT INTO OUTFILE)`
3. 기존 개발DB mysql.general_log는 Truncate
4. general_log on `(SET global general_log = ON, global log_output = 'TABLE' )`
5. scp를 통해 general_log 백업 파일을 개발DB로 복사
6. 해당 파일을 백업용 버킷에 복사 
7. 백업 스크립트 동작 로그 테이블에 결과 기록 `(일자,백업종류,hostname)`

## 해당 스크립트 동작 중 이상 알림 발생
- 백업 스크립트 동작시에 Load Average 가 갑자기 증가하여 알림이 발생 
    - Load Average 값은 코어 수의 약 3배까지 올라감
    - CPU 사용률은 30%이하로 유지됨
    - 해당 현상 발생시 DB상에 이상 없음 
    - 해당 현상 발생시 Disk 부하가 크게 발생하는 것을 확인하였음

- 해당 서버 내 DB외 다른 프로세스 동작하지 않음 
    - pidstat으로 프로세스 확인 결과 디스크 I/O를 유발하는 다른 프로세스가 존재하지 않는 것을 확인 
    - 테스트 결과, DB 상에서 LOAD DATA INFILE 쿼리로 많은 데이터를 한번에 넣는경우 Load Average 가 증가하는 것을 확인하였음 


## 해결 방안 
1. 백업 파일 분할
    - 기존 하나의 백업파일만을 사용하던 방식에서 백업파일을 분할하여 저장하는 방식으로 변경
    - LOAD DATA INFILE로 한번에 불러오는 데이터를 나누어 부하를 최소화 
    - 적용 결과
        - 이전에 비해 부하 발생 빈도가 줄어들었으나, 완전히 사라지지않아 다른방법을 적용

2. monitoring.general_log 테이블의 엔진 변경 
    - 백업용 monitoring.general_log 테이블의 엔진을 MyISAM으로 변경
    
    - 테이블 엔진 별 차이점

    | 항목 | InnoDB | MyISAM |
    |:---|:---|:---|
    | 트랜잭션 지원 | O (롤백 가능) | X (롤백 불가) |
    | 잠금 방식 | 레코드 잠금 (그러나 LOAD는 테이블 잠금) | 테이블 잠금 |
    | 성능 | 조금 느릴 수 있음 | 빠름 |
    | 복구 | 충돌 복구 가능 | 충돌 복구 어려움 |
    | 제약조건 | 외래키, 유니크 검사 | 유니크만 검사 |

    - 해당 테이블의 용도가 기록 용도로만 사용되므로 엔진을 변경하여도 동작에 이상없는것으로 확인 
    
    - 적용 결과
        - `테이블 엔진 변경 후 더이상 해당 현상 발생 하지 않음`
