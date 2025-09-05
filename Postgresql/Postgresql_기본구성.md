# Postgresql 기본 세팅

## 1.Postgresql 설치 

### 1-1. 기본 저장소로 설치 (권장: 빠르고 간단)
```bash
sudo apt update
sudo apt install postgresql postgresql-contrib
```
- `postgresql-contrib`는 유용한 확장 모듈도 함께 설치합니다.

### 1-2. 공식 저장소로 최신 버전 설치
최신 PostgreSQL 버전을 쓰려면 공식 저장소를 등록 후 설치합니다.
```bash
# 1. 공식 저장소 등록
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt focal-pgdg main" > /etc/apt/sources.list.d/pgdg.list'

# 2. GPG 키 등록
wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -

# 3. 패키지 목록 갱신
sudo apt update

# 4. 원하는 버전 설치 (예: 14버전)
sudo apt install postgresql-14 postgresql-client-14
```
- 버전에 따라 `postgresql-13`, `postgresql-15` 등으로 바꾸어 설치할 수 있습니다.


### 1-3.소스 다운로드 방식

#### 필요 패키지 설치
```bash
sudo apt update
sudo apt install build-essential libreadline-dev zlib1g-dev flex bison libxml2-dev libxslt-dev libssl-dev
```

#### 소스 파일 다운로드
- 공식 사이트에서 최신 버전 tar.gz 파일을 다운로드합니다.
  - 정확한 버전은 다운로드 페이지(https://www.postgresql.org/ftp/source/)에서 확인
```bash
wget https://ftp.postgresql.org/pub/source/v16.2/postgresql-16.2.tar.gz
tar -zxvf postgresql-16.2.tar.gz
cd postgresql-16.2
```

#### 컴파일 및 설치
- --prefix로 지정한 디렉토리에 PostgreSQL이 설치됨
```bash
./configure --prefix=/usr/local/pgsql
make
sudo make install
```


#### 계정 및 디렉토리 준비
```bash
sudo useradd postgres
sudo mkdir /usr/local/pgsql/data
sudo chown postgres /usr/local/pgsql/data
```

#### DB 클러스터 초기화
```bash
sudo -i -u postgres
/usr/local/pgsql/bin/initdb -D /usr/local/pgsql/data
```

#### 서버 실행
```bash
/usr/local/pgsql/bin/pg_ctl -D /usr/local/pgsql/data -l logfile start
```

### PATH 추가 (필요시)
```bash
export PATH=/usr/local/pgsql/bin:$PATH
```
- .bashrc 등에 추가하면 영구적




## 2. 설치 후 확인 및 접속
```bash
# 서비스 상태 확인
sudo systemctl status postgresql

# Postgres 기본 계정 진입
sudo -i -u postgres

# psql 접속
psql
```
- 성공하면 psql 프롬프트(`postgres=#`)가 나타납니다.

## 3. 기본 명령어 정리
- Postgres 버전 확인: `psql --version`
- 서비스 재시작: `sudo systemctl restart postgresql`
- psql 종료: `\q`

## 4. 사용자/DB 생성 예시
```sql
CREATE USER myuser WITH ENCRYPTED PASSWORD 'mypassword';
CREATE DATABASE mydb OWNER=myuser;
GRANT ALL PRIVILEGES ON DATABASE mydb TO myuser;
```

## 5. 외부 접속을 위한 postgresql.conf, pg_hba.conf 파일 설정

### postgresql.conf 설정
- 파일 위치 예시 (버전에 따라 다름):
  - `/etc/postgresql/14/main/postgresql.conf`
  - `/var/lib/pgsql/14/data/postgresql.conf`
- 설정 항목 찾아 아래처럼 수정:
  ```conf
  listen_addresses = '*'
  ```
  - “localhost”에서 “*”로 변경하면 모든 IP에서 접속 가능

### pg_hba.conf 설정
- 파일 위치 예시:
  - `/etc/postgresql/14/main/pg_hba.conf`
  - `/var/lib/pgsql/14/data/pg_hba.conf`
- 하단 또는 # IPv4 local connections: 근처에 다음 줄을 추가:
  ```conf
  host all all 0.0.0.0/0 md5
  ```
  - 모든 IP에서 비밀번호 인증(md5) 방식으로 접속 허용
  - 보안을 위해 실제 운영에서는 특정 IP 대역(e.g., `192.168.0.0/24`)만 허용하는 것이 더 안전

### 서비스 재시작
```bash
sudo systemctl restart postgresql
```

### 방화벽 확인 (Ubuntu 기준)
```bash
sudo ufw allow 5432/tcp
sudo ufw reload
```
- 포트 5432이 열려 있어야 외부 연결 가능.


## Docker Container로 실행

### 설정 파일 구성
- custom_conf/custom-postgresql.conf
```
# PostgreSQL configuration for logical replication
listen_addresses = '*'
wal_level = logical
max_replication_slots = 4
max_wal_senders = 4
wal_keep_size = 64MB
max_worker_processes = 8
```

- custom_conf/custom-pg_hba.conf
```
# Allow replication connections from any IP with password
host    all     postgres        0.0.0.0/0      md5
```

- 컨테이너 실행
```sh
docker run -d --name postgres-main \
  --network=postgre-network \
  -p 5432:5432 \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgrespass \
  -e POSTGRES_DB=connect_test_db \
  -v $(pwd)/custom_conf/custom-postgresql.conf:/etc/postgresql/postgresql.conf \
  -v $(pwd)/custom_conf/custom-pg_hba.conf:/etc/postgresql/pg_hba.conf \
  -v $(pwd)/init.sql:/docker-entrypoint-initdb.d/init.sql \
  postgres:latest \
  -c config_file=/etc/postgresql/postgresql.conf
```

