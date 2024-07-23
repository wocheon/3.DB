# mysqld_multi 구성 

## 개요 
- 하나의 서버에서 여러 대의 mysql DB를 사용하는 방법
- GCP VM을 기준으로 하며 Alias IP, HAProxy등을 이용하여 구성 
    - Alias IP 는 내부 IP를 여러개 사용하는 경우 사용

## 구성 
- DB1 
    - IP : 192.168.1.102
    - Alias IP : 192.168.1.202

## Alias IP 설정 
- GCP Compute Engine에서 해당 VM에 별칭 IP 대역을 추가 
    - 중지 없이 수정 가능 
    - Alias IP는 기존 IP와 동일대역에서만 가능 

## MYSQL 설치 - 버전 10.5 이상
### MariaDB Repo 추가
```
cat << EOF >> /etc/yum.repos.d/MaraiDB.repo
# MariaDB 10.5 CentOS repository list - created 2021-03-16 03:20 UTC
# http://downloads.mariadb.org/mariadb/repositories/
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.5/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOF 
```

### MariaDB 설치 
```
yum install -y MariaDB-server MariaDB-client
mysql_secure_installation
```


### mysqld 실행 및 접속
```
systemctl restart mysqld 

mysql -u root -p
```

### mysqld_multi 용 계정 생성 
```sql
create user 'multi_admin'@'localhost' identified by 'my_password';
GRANT SHUTDOWN ON *.* TO 'multi_admin'@'localhost';
flush privileges;
```


## mysqld_multi 설정
> vi /etc/my.cnf
```sh
[mysqld]
log-error=/var/log/mysql/mysql.log
user=mysql

[mysqld_multi]
mysqld =/sbin/mysqld
#mysqld = /usr/local/mysql/bin/mysqld_safe
#mysqladmin = /usr/local/mysql/bin/mysqladmin
mysqladmin =/bin/mysqladmin
# 여러개의 mysql을 실행하는 mysql 계정정보
user = multi_admin
password = my_password

# 여러개의 MYSQL을 생성할때에는 [mysqld숫자] 로 시작하며,
# socket, port, pid, datadir 경로가 모두 달라야 함
# HAProxy 사용시 Proxy Protocol networks 옵션이 있어야 프록시로 연결 가능 
[mysqld3307]
socket = /tmp/mysql.sock3307
proxy-protocol-networks=127.0.0.1/32
port = 3307
pid-file = /usr/local/mysql/data_3307/hostname.pid3307
datadir = /usr/local/mysql/data_3307
user = multi_admin

[mysqld3308]
socket = /tmp/mysql.sock3308
proxy-protocol-networks=127.0.0.1/32
port = 3308
pid-file = /usr/local/mysql/data_3308/hostname.pid3308
datadir = /usr/local/mysql/data_3308
user = multi_admin

#
# include *.cnf from the config directory
#
!includedir /etc/my.cnf.d
```

### datadir 생성 및 권한 조정 
```
mkdir -p /usr/local/mysql/data_3307 /usr/local/mysql/data_3308
chown -R mysql.mysql /usr/local/mysql/
```

### mysqld 재시작 
```
systemctl restart mysqld 
```

### mysqld_multi 설정 확인
```
mysqld_multi reload
mysqld_multi report
```

### mysqld_multi 설정 실행 
```
mysqld_multi start 
```
- /etc/my.cnf 에 설정한 대로 다중소켓이 실행 됨

### 소켓별 접속 방법
```
mysql -u root -p -S/tmp/mysql.sock3307
mysql -u root -p -S/tmp/mysql.sock3308
```

### 각 DB별 접속계정 설정 
- DB_1 (Port : 3307)
```sql
create database db_1;

# 로컬에서 접근시 -h 127.0.0.1로 접속 가능하도록 변경
grant ALL PRIVILEGES on *.* to 'root'@'localhost' IDENTIFIED BY 'welcome1';

# DB 접근 계정 생성 
CREATE USER 'dbuser'@'%' IDENTIFIED BY 'welcome1';
GRANT ALL PRIVILEGES ON db_1.* TO 'dbuser'@'%';

flush privileges;
```
- DB_2 (Port : 3308)
```sql
create database db_2;

# 로컬에서 접근시 -h 127.0.0.1로 접속 가능하도록 변경
grant ALL PRIVILEGES on *.* to 'root'@'localhost' IDENTIFIED BY 'welcome1';

# DB 접근 계정 생성 
CREATE USER 'dbuser'@'%' IDENTIFIED BY 'welcome1';
GRANT ALL PRIVILEGES ON db_2.* TO 'dbuser'@'%';
flush privileges;
```

## HAProxy 설정 

### HAProxy 설치
```
yum install -y haproxy 
```

### HAProxy 실행 
```
systemctl enable haproxy --now 
```

### HAProxy 설정파일 수정
> vi /etc/haproxy/haproxy.cfg

```sh
listen db1
        bind 192.168.1.102:3306
        mode tcp
        option forwardfor
        balance first
        server db1 127.0.0.1:3307 send-proxy check
        server db2 127.0.0.1:3308 send-proxy backup

listen db2
        bind 192.168.1.202:3306
        mode tcp
        option forwardfor
        balance first
        server db2 127.0.0.1:3308 send-proxy check
        server db1 127.0.0.1:3307 send-proxy backup                                                 
```

### HAProxy 설정파일 syntax 확인 및 재실행
```
haproxy -f /etc/haproxy/haproxy.cfg -c
systemctl restart haproxy 
```

## DB 접속 후 정상 작동 확인 
- DB_1

```
mysql -u dbuser -pwelcome1 -P 3306 -h 192.168.1.102

MariaDB [(none)]> show databases;
+--------------------+
| Database           |
+--------------------+
| db_1               |
| information_schema |
| test               |
+--------------------+
3 rows in set (0.002 sec)
```

- DB_2

```sql
$ mysql -u dbuser -pwelcome1 -P 3306 -h 192.168.1.202

MariaDB [(none)]> show databases;
+--------------------+
| Database           |
+--------------------+
| db_2               |
| information_schema |
| test               |
+--------------------+
3 rows in set (0.002 sec)
```

## 소켓별로 중지 방법

```
mysqld_multi stop 3307
```

- 중지 불가한경우 mysqladmin으로 진행
```
mysqladmin -h127.0.0.1 -P3307 -uroot -p shutdown
```
