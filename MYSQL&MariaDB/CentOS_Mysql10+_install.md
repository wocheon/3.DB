[mysql install - 버전 10.5 이상]

cat << EOF >> /etc/yum.repos.d/MaraiDB.repo
# MariaDB 10.5 CentOS repository list - created 2021-03-16 03:20 UTC
# http://downloads.mariadb.org/mariadb/repositories/
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.5/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOF 

yum install -y MariaDB-server MariaDB-client

systemctl restart mysql 
mysql_secure_installation 
	(root pw : welcome1)
 
mysql -u root -pwelcome1

grant usage on *.* to dbtest_1@'%' IDENTIFIED BY 'welcome1';
flush privileges;
exit;

grant usage on *.* to dbtest_2@'%' IDENTIFIED BY 'welcome1';
flush privileges;
exit;
