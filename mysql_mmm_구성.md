# MYSQL MMM (Multi - Master Replication Manager) 구성 

## MMM (Multi - Master Replication Manager)
- Perl 기반의 Auto Failover Open Source
- DB 서버에서 에이전트 실행 이 후 MMM 모니터와 통신을 하는 방식     
    - Health chekc, Failover 수행
- Monitor <-> Agent 통신방식

- MMM의 구조
    - Master (Activce) 와 Master (Standby) 양방향 복제

- 별도 Slave 추가 가능 


### MMM FAILOVER 과정
1. 읽기모드로 변경
2. 세션 킬
3. VIP 회수


### MMM FAILOVER 과정에서 복제가 깨지는 경우

- MMM 구성에서는 Stand By 쪽으로 데이터 복제가 완료되면 Active 쪽에 ACK 신호를 보낸다.

- 데이터 복제는 완료되었으나 ACK 신호가 아직 도달하지 않은 상황에서 Actice 쪽에 장애 발생 시 해당 작업을 재진행하게됨

- 이 과정에서 데이터 정합성 혹은 PK 관련 에러가 발생할 수 있음 


### 참고. GCP등 Public Cloud 환경에서의 MMM 구성 
- MMM은 기본적으로 VIP를 통해 failover가 가능하도록 구성함

- GCP 상에서 VIP 자체는 Alias IP를 통해서 구현가능

- MMM 구성에 VM의 Alias IP를 변경하는 기능을 포함하기는 어려울것으로 보임
    - MMM 환경에서 Failover 가 발생되면 기존 Active 쪽에 붙어있던 Write용 VIP를 Standby로 옮기는 방식으로 진행됨
    
    - Cloud 환경에서 IP는 하나의 Cloud 리소스이므로 VIP를 옮긴다고해서 실제 VM의 Alias IP 가 변경되지는 않음

- 가급적 Cloud 상에서 제공하는 Application LB 등을 사용하여 failover 구성을 진행 


## MMM 구성 

### 구현 환경
- DBMS : MariaDB
    - Version : 10.5.24

|구분|서버명|IP|
|:-:|:-:|:-:|
|Master(Active)|db1|192.168.1.101|
|Master(Standby)|db2|192.168.1.102|
|mmm-Monitor|mmm|192.168.1.103|

### Replication을 통한 Master-Master 구성 
- 모든 DB에 /etc/my.cnf 에 해당 라인 추가 

```sh
#db1
[mysqld]
replicate-do-db='repl_db'
server-id=1
log-bin=mysql-bin


#db2
[mysqld]
replicate-do-db='repl_db'
server-id=2
log-bin=mysql-bin
```

- Replication 용 DB/계정 추가 
```sql
create database repl_db default character set utf8;
grant replication slave on *.* to repl_user@'%' identified by 'test123';
flush privileges;
```

- Master Status 확인

```sql
--db1

MariaDB [(none)]> show master status;
+------------------+----------+--------------+------------------+
| File             | Position | Binlog_Do_DB | Binlog_Ignore_DB |
+------------------+----------+--------------+------------------+
| mysql-bin.000001 |      328 |              |                  |
+------------------+----------+--------------+------------------+
1 row in set (0.000 sec)


--db2 
MariaDB [(none)]> show master status;
+------------------+----------+--------------+------------------+
| File             | Position | Binlog_Do_DB | Binlog_Ignore_DB |
+------------------+----------+--------------+------------------+
| mysql-bin.000001 |      329 |              |                  |
+------------------+----------+--------------+------------------+
1 row in set (0.000 sec)
```



- 각 DB간 Master-Slave 연결 구성 
```sql
--db1
change master to master_host='192.168.1.102' , master_user='repl_user' , master_password='test123' , master_log_file='mysql-bin.000001' , master_log_pos=329;

--db2
change master to master_host='192.168.1.101' , master_user='repl_user' , master_password='test123' , master_log_file='mysql-bin.000001' , master_log_pos=328;
```

- 양 DB 모두 mysql 재시작
    - 재기동 해야 Slave_IO_Running , Slave_SQL_Running 상태가 변경됨

```
systemctl restart mysqld
```


- Master-Master 연결 확인

```sql
--db1
MariaDB [(none)]> show slave status \G
*************************** 1. row ***************************
                Slave_IO_State: Waiting for master to send event
                   Master_Host: 192.168.1.102
                   Master_User: repl_user
                   Master_Port: 3306
                 Connect_Retry: 60
               Master_Log_File: mysql-bin.000002
           Read_Master_Log_Pos: 342
                Relay_Log_File: db-01-relay-bin.000004
                 Relay_Log_Pos: 641
         Relay_Master_Log_File: mysql-bin.000002
              Slave_IO_Running: Yes
             Slave_SQL_Running: Yes
               Replicate_Do_DB: repl_db

--db2
MariaDB [(none)]> show slave status \G
*************************** 1. row ***************************
                Slave_IO_State: Waiting for master to send event
                   Master_Host: 192.168.1.101
                   Master_User: repl_user
                   Master_Port: 3306
                 Connect_Retry: 60
               Master_Log_File: mysql-bin.000002
           Read_Master_Log_Pos: 778
                Relay_Log_File: db-02-relay-bin.000004
                 Relay_Log_Pos: 1077
         Relay_Master_Log_File: mysql-bin.000002
              Slave_IO_Running: Yes
             Slave_SQL_Running: Yes
               Replicate_Do_DB: repl_db
```

- 정상 작동 확인 
```sql
--db1 
MariaDB [repl_db]> select * from test_tbl1;
+------+-------+
| id   | name  |
+------+-------+
|    1 | test1 |
|    2 | test2 |
|    3 | test3 |
|    4 | test4 |
+------+-------+
4 rows in set (0.001 sec)

MariaDB [repl_db]> insert into test_tbl1 values (5, 'test5');
Query OK, 1 row affected (0.003 sec)

MariaDB [repl_db]> commit;
Query OK, 0 rows affected (0.001 sec)



--db2
MariaDB [repl_db]> select * from test_tbl1;
+------+-------+
| id   | name  |
+------+-------+
|    1 | test1 |
|    2 | test2 |
|    3 | test3 |
|    4 | test4 |
|    5 | test5 |
+------+-------+
5 rows in set (0.001 sec)
```


### MMM Agent , MMM Monitor 설치

- db1,db2 
```
yum -y install epel-release
yum -y install mysql-mmm mysql-mmm-agent
```

- mmm (monitor)
```
yum -y install epel-release
yum -y install mysql-mmm mysql-mmm-monitor
```

### mmm_agent, mmm_monitor 용 계정 생성 및 권한 부여 
```sql
create user 'mmm_monitor'@'192.168.1.%' identified by 'test123';
GRANT SUPER, REPLICATION CLIENT, PROCESS ON *.* TO 'mmm_monitor'@'192.168.1.%' ;
flush privileges;

create user 'mmm_agent'@'192.168.1.%' identified by 'test123';
GRANT SUPER, REPLICATION CLIENT, PROCESS ON *.* TO 'mmm_agent'@'192.168.1.%';
flush privileges;
```



### MMM conf 파일 설정
- mmm_common.conf : 모니터링 노드, DB 서버 모두 수정 필요 
    - 모두 동일해야 함
- mmm_agent.conf : DB 서버 수정 필요
- mmm_mon.conf : 모니터링 노드에서 수정필요

- conf 파일 위치 
```
cd /etc/mysql-mmm
```


-  mmm_common.conf (ALL)
```bash
active_master_role      writer

<host default>
    cluster_interface       eth0
    pid_path                /run/mysql-mmm-agent.pid
    bin_path                /usr/libexec/mysql-mmm/
    replication_user        repl_user   #replication용 계정 
    replication_password    test123
    agent_user              mmm_agent   # mmm_agent용 계정
    agent_password          test123
</host>

<host db1>
    ip      192.168.1.101
    mode    master
    peer    db1
</host>

<host db2>
    ip      192.168.1.102
    mode    master
    peer    db2
</host>

#<host db3>
#    ip      192.168.100.51
#    mode    slave
#</host>

# 아래는 VIP이므로 현재 할당된 IP를 제외하고 미사용 IP로 설정할 것
<role writer>
    hosts   db1, db2
    ips     192.168.1.210
    mode    exclusive
</role>

<role reader>
    hosts   db1, db2
    ips     192.168.1.220
    mode    balanced
</role>
```

- mmm_agent.conf (DB)

```sh
# DB1 
include mmm_common.conf
# The 'this' variable refers to this server.  Proper operation requires
# that 'this' server (db1 by default), as well as all other servers, have the
# proper IP addresses set in mmm_common.conf.
this db1


# DB2
include mmm_common.conf
# The 'this' variable refers to this server.  Proper operation requires
# that 'this' server (db1 by default), as well as all other servers, have the
# proper IP addresses set in mmm_common.conf.
this db2
```

- mmm_mon.conf (Monitor)
```sh
include mmm_common.conf

<monitor>
    ip                  127.0.0.1
    pid_path            /run/mysql-mmm-monitor.pid
    bin_path            /usr/libexec/mysql-mmm
    status_path         /var/lib/mysql-mmm/mmm_mond.status
    ping_ips            192.168.1.101, 192.168.1.102    # VIP가 아닌 실제 IP만 입력
    auto_set_online     60

    # The kill_host_bin does not exist by default, though the monitor will
    # throw a warning about it missing.  See the section 5.10 "Kill Host
    # Functionality" in the PDF documentation.
    #
    # kill_host_bin     /usr/libexec/mysql-mmm/monitor/kill_host
    #
</monitor>

<host default>
    monitor_user        mmm_monitor # mmm_monitor용 계정
    monitor_password    test123
</host>

debug 0
```


### MMM Agent 및 MMM Monitor 기동 
```bash
#db1, db2
cd /etc/mysql-mmm
mmm_agentd start

#monitor
cd /etc/mysql-mmm
mmm_mond start 

$ mmm_control show
  db1(192.168.1.101) master/AWAITING_RECOVERY. Roles:
  db2(192.168.1.102) master/AWAITING_RECOVERY. Roles:
# 60 초 간격으로 Helth_check 진행하므로 잠시 후 확인

$ mmm_control checks all
db2  ping         [last change: 2024/04/29 07:17:40]  OK
db2  mysql        [last change: 2024/04/29 07:17:40]  OK
db2  rep_threads  [last change: 2024/04/29 07:17:40]  OK
db2  rep_backlog  [last change: 2024/04/29 07:17:40]  OK: Backlog is null
db1  ping         [last change: 2024/04/29 07:17:40]  OK
db1  mysql        [last change: 2024/04/29 07:17:40]  OK
db1  rep_threads  [last change: 2024/04/29 07:17:40]  OK
db1  rep_backlog  [last change: 2024/04/29 07:17:40]  OK: Backlog is null

$ mmm_control show
  db1(192.168.1.101) master/ONLINE. Roles: writer(192.168.1.210)
  db2(192.168.1.102) master/ONLINE. Roles: reader(192.168.1.220)
```


### Failover 테스트 
- DB1 서버(Active) mysqld 중지 시 failover 동작 여부 확인
```sh
#db1 
systemctl stop mysqld 

$ mmm_control show
  db1(192.168.1.101) master/HARD_OFFLINE. Roles:
  db2(192.168.1.102) master/ONLINE. Roles: reader(192.168.1.220), writer(192.168.1.210)
# Write 용 VIP가 db2(Standby)로 이동 

#db1 재기동
systemctl start mysqld 


 mmm_control show
  db1(192.168.1.101) master/ONLINE. Roles: reader(192.168.1.220)
  db2(192.168.1.102) master/ONLINE. Roles: writer(192.168.1.210)
# 재기동되면 다시 원복
```


### mmm_agent, monitor 중지 불가한 경우 
- 해당 오류 발생하면서 중지/실행이 안되는 경우 강제로 프로세스 종료 후 재실행
    - 혹은 해당 demon 파일에서 문제되는 라인을 주석처리후 종료 혹은 실행 
```sh
$ mmm_agentd stop
Can`t run second copy of mmm_agentd at /usr/sbin/mmm_agentd line 75

$  ps -ef | grep mmm | grep -v grep
root      1827     1  0 07:17 ?        00:00:00 mmm_agentd
root      1828  1827  0 07:17 ?        00:00:03 mmm_agentd

kill -9 1827 1828
```
