# Oracle TNS 등록방법

## Instant Client 설치 여부 확인 

* Oracle Instant Client 설치
  
  - https://www.oracle.com/downloads/#category-database

## listener.org 변경

* 파일 위치
  
  - C:\app\[사용자명]\product\[오라클버전]\home\[xxxxx]\network\admin\listener.org 

- 해당 파일에 현재 접속하는 서버의 IP주소가 제대로 입력되어있는지 확인 <br>
`LocalHost 로 입력된경우, 외부 접속 불가`

>listener.org 
```sql
LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = [ip주소])(PORT = 1521))
      (ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC1521))
    )
  )
```

## 시스템환경변수 ORACLE_HOME, TNS_ADMIN 추가 

* `TNS_ADMIN` : InstantClient 설치 위치 

* `ORACLE_HOME`  : C:\app\[사용자명]\product\[오라클버전]\dbhome[SID명] 

* `PATH` : `ORACLE_HOME` 과 동일하게 설정

`C:\app\[사용자명]\product\[오라클버전]\home 과 혼동하지 않기`

 
 $\textcolor{orange}{\textsf{* 환경변수가 잘못되었을때 발생가능한 오류}}$ 

- `ORACLE_HOME` : `CMD` - `SQLPLUS` 자체가 실행이 불가능

- `TNS_ADMIN` : 추후 TNS 작동을위해 TNSPING을 하는경우 에러 발생



## tnsname.ora 및 sqlnet.ora 작성

* sqlnet.ora 파일 위치
  - C:\app\[사용자명]\product\[오라클버전]\home\network\admin\sqlnet.ora

```bash
SQLNET.AUTHENTICATION_SERVICES= (NTS)
NAMES.DIRECTORY_PATH= (TNSNAMES, ONAMES, HOSTNAME)
#기존파일에서 EZCONNECT로 되어있던것을 변경
```
* tnsname.ora 파일 위치
  * [InstantClient 설치 위치]\tnsname.ora 


* 다음과 같은 형태로 TNS목록에 추가할 DB의 정보를 작성 <br>
`(YAML파일 처럼 공백을 잘 맞추어서 입력 필요 > 탭키 사용 시 에러발생)`

```json
[ALIAS명] =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = [ip명])(PORT = [포트]))
    (CONNECT_DATA =     
      (SERVICE_NAME = [SERVICE_NAME 입력])
      (SID = [SID 입력])
    )
  )
```

* Service Name
  - 여러개의 인스턴스를 모아 하나의 서버 혹은 시스템을 구성한것

* SID 
  - DB 하나의 인스턴스



## 정상작동 확인 

- sysdba 로 접속 하여 다음 내용을 확인

- `Service_NAME`

```sql
SELECT NAME, DB_UNIQUE_NAME FROM v$database;
```  

- `SID` 
```sql
SELECT instance FROM v$thread;
```

* TNSPING으로 DB 연결가능 확인
```
cmd - TNSPING [TNS ALIAS 명] 
```
- TNSPING 확인 후 SQL DEVELOPER 등을 이용하여 접속 확인.
