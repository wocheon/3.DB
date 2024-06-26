# mysql install - 버전 10.5 이상
## MariaDB Repo 추가
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

## MariaDB 설치 
```
yum install -y MariaDB-server MariaDB-client
```

## MYSQLD 기동 후 mysql_secure_installation 진행
```
systemctl restart mysql 
mysql_secure_installation 
	(root pw : welcome1)
```

## 외부 접속용 계정 생성
```
mysql -u root -pwelcome1

grant usage on *.* to dbtest_1@'%' IDENTIFIED BY 'welcome1';
flush privileges;
exit;

grant usage on *.* to dbtest_2@'%' IDENTIFIED BY 'welcome1';
flush privileges;
exit;
```

```
# 유저 생성 
CREATE user '{USER_ID}'@'{HOST}' IDENTIFIED BY '{PASSWORD}';

# SELECT 권한 만을 부여
GRANT SELECT ON {DATABASE_NAME}.{TABLE_NAME_or_ALL} TO '{USER_ID}'@'{HOST}';

# 모든 권한을 부여 ( Optional )
GRANT ALL PRIVILEGES ON {DATABASE_NAME}.{TABLE_NAME_or_ALL} TO '{USER_ID}'@'{HOST}';

# 변경된 사항 적용 ( Required )
FLUSH PRIVILEGES;
```
