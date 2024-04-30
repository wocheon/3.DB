# MYSQL Replication 구성하기 

## 구현 환경 
|구분|서버명|IP|
|:-|:-:|:-:|
|master|db-1|192.168.1.101|
|slave|db-2|192.168.1.102|

## MYSQL Replication 구성

### Master (192.168.1.101) 구성 
- 신규 DB 작성 후 replication 용 User 생성 

```sql
MariaDB [(none)]> create database repl_db default character set utf8;

MariaDB [(none)]> grant replication slave on *.* to repl_user@'%' identified by 'test123';

MariaDB [(none)]> flush privileges;
```

- /etc/my.cnf 파일에  다음 라인 추가 

```
[mysqld]
log-bin=mysql-bin
server-id=1
```

- mysqld 재시작 
```
systemctl restart mysqld
```

- master 상태 확인 

```sql
MariaDB [(none)]> show master status;
+------------------+----------+--------------+------------------+
| File             | Position | Binlog_Do_DB | Binlog_Ignore_DB |
+------------------+----------+--------------+------------------+
| mysql-bin.000001 |     1048 |              |                  |
+------------------+----------+--------------+------------------+
1 row in set (0.000 sec)

# 결과 값중 bin 파일 명 , Position는 slave 설정 시 필요하므로 기록필요
```

### Slave (192.168.1.102) 설정 
- 동일하게 repl_db 생성

```sql
MariaDB [(none)]> create database repl_db default character set utf8;
```

- /etc/my.cnf 파일에  다음 라인 추가 

```
[mysqld]
log-bin=mysql-bin
server-id=1
```


 - Slave 설정 적용

```sql
MariaDB [(none)]> change master to master_host='192.168.1.101' , master_user='repl_user' , master_password='test123' , master_log_file='mysql-bin.000001' , master_log_pos=1048;
Query OK, 0 rows affected (0.007 sec)
```

- 설정 확인 

```sql
MariaDB [(none)]> show slave status \G;
*************************** 1. row ***************************
                Slave_IO_State: Waiting for master to send event
                   Master_Host: 192.168.1.101
                   Master_User: repl_user
                   Master_Port: 3306
                 Connect_Retry: 60
               Master_Log_File: mysql-bin.000001
           Read_Master_Log_Pos: 1048
                Relay_Log_File: db-02-relay-bin.000003
                 Relay_Log_Pos: 555
         Relay_Master_Log_File: mysql-bin.000001
         # 아래 두 라인이 yes인지 확인
              Slave_IO_Running: Yes
             Slave_SQL_Running: Yes
               Replicate_Do_DB: repl_db
           Replicate_Ignore_DB:
            Replicate_Do_Table:
        Replicate_Ignore_Table:
       Replicate_Wild_Do_Table:
   Replicate_Wild_Ignore_Table:
                    Last_Errno: 0
                    Last_Error:
                  Skip_Counter: 0
           Exec_Master_Log_Pos: 1048
               Relay_Log_Space: 864
               Until_Condition: None
                Until_Log_File:
                 Until_Log_Pos: 0
            Master_SSL_Allowed: No
            Master_SSL_CA_File:
            Master_SSL_CA_Path:
               Master_SSL_Cert:
             Master_SSL_Cipher:
                Master_SSL_Key:
         Seconds_Behind_Master: 0
 Master_SSL_Verify_Server_Cert: No
                 Last_IO_Errno: 0
                 Last_IO_Error:
                Last_SQL_Errno: 0
                Last_SQL_Error:
   Replicate_Ignore_Server_Ids:
              Master_Server_Id: 1
                Master_SSL_Crl:
            Master_SSL_Crlpath:
                    Using_Gtid: No
                   Gtid_IO_Pos:
       Replicate_Do_Domain_Ids:
   Replicate_Ignore_Domain_Ids:
                 Parallel_Mode: optimistic
                     SQL_Delay: 0
           SQL_Remaining_Delay: NULL
       Slave_SQL_Running_State: Slave has read all relay log; waiting for more updates
              Slave_DDL_Groups: 0
Slave_Non_Transactional_Groups: 0
    Slave_Transactional_Groups: 0
1 row in set (0.000 sec)

```


### Replication 동작 확인 
- master(192.168.1.101) 에서 repl_db 내에 테이블 생성 및 데이터 Insert 
```sql
MariaDB [(none)]> use repl_db;
Reading table information for completion of table and column names
You can turn off this feature to get a quicker startup with -A

Database changed
MariaDB [repl_db]> create table test_tbl2 ( id int , name varchar(10));
Query OK, 0 rows affected (0.075 sec)


MariaDB [repl_db]> insert into test_tbl2 values (2, 'test2');
Query OK, 1 row affected (0.016 sec)

MariaDB [repl_db]> commit;
Query OK, 0 rows affected (0.000 sec)

```

- Slave(192.168.1.102)에서 조회했을떄 데이터가 동일한지 확인

```sql
MariaDB [repl_db]> show tables;
+-------------------+
| Tables_in_repl_db |
+-------------------+
| test_tbl2         |
+-------------------+
2 rows in set (0.000 sec)

MariaDB [repl_db]> select * from test_tbl2;
+------+-------+
| id   | name  |
+------+-------+
|    2 | test2 |
+------+-------+
1 row in set (0.000 sec)
```

<br>
<br>

## MYSQL Replication - Master <-> Slave 전환 

### Slave -> Master로 변경

- repl_user 생성
```
MariaDB [mysql]> grant replication slave on *.* to repl_user@'%' identified by 'test123';
```
- Slave 설정 해제 

```sql
MariaDB [repl_db]> stop slave;
Query OK, 0 rows affected (0.039 sec)

MariaDB [mysql]> reset slave all;
Query OK, 0 rows affected (0.000 sec)

MariaDB [mysql]> show slave status \G
Empty set (0.000 sec)
```


- /etc/my.cnf 변경
    - log-bin 항목 추가
```
[mysqld]
replicate-do-db='repl_db'
server-id=2
log-bin=mysql-bin
```

- master status 확인 
```sql
MariaDB [(none)]> show master status
    -> ;
+------------------+----------+--------------+------------------+
| File             | Position | Binlog_Do_DB | Binlog_Ignore_DB |
+------------------+----------+--------------+------------------+
| mysql-bin.000005 |      342 |              |                  |
+------------------+----------+--------------+------------------+
1 row in set (0.000 sec)

```

### Master -> Slave 로 변경
- Master 지정 
```sql
MariaDB [(none)]>  change master to master_host='192.168.1.102' , master_user='repl_user' , master_password='test123' , master_log_file='mysql-bin.000005' , master_log_pos=342;
Query OK, 0 rows affected (0.009 sec)
```

-  Slave Status 확인 
    - 재기동 전에는 Slave_IO_Running,Slave_SQL_Running 가  No로 되어있으므로 재기동 필요
```sql
MariaDB [(none)]> show slave status \G
*************************** 1. row ***************************
                Slave_IO_State:
                   Master_Host: 192.168.1.102
                   Master_User: repl_user
                   Master_Port: 3306
                 Connect_Retry: 60
               Master_Log_File: mysql-bin.000005
           Read_Master_Log_Pos: 342
                Relay_Log_File: db-01-relay-bin.000001
                 Relay_Log_Pos: 4
         Relay_Master_Log_File: mysql-bin.000005
              Slave_IO_Running: No
             Slave_SQL_Running: No
               Replicate_Do_DB: repl_db
           Replicate_Ignore_DB:
            Replicate_Do_Table:
        Replicate_Ignore_Table:
       Replicate_Wild_Do_Table:
   Replicate_Wild_Ignore_Table:
                    Last_Errno: 0
                    Last_Error:
                  Skip_Counter: 0
           Exec_Master_Log_Pos: 342
               Relay_Log_Space: 256
               Until_Condition: None
                Until_Log_File:
                 Until_Log_Pos: 0
            Master_SSL_Allowed: No
            Master_SSL_CA_File:
            Master_SSL_CA_Path:
               Master_SSL_Cert:
             Master_SSL_Cipher:
                Master_SSL_Key:
         Seconds_Behind_Master: NULL
 Master_SSL_Verify_Server_Cert: No
                 Last_IO_Errno: 0
                 Last_IO_Error:
                Last_SQL_Errno: 0
                Last_SQL_Error:
   Replicate_Ignore_Server_Ids:
              Master_Server_Id: 0
                Master_SSL_Crl:
            Master_SSL_Crlpath:
                    Using_Gtid: No
                   Gtid_IO_Pos:
       Replicate_Do_Domain_Ids:
   Replicate_Ignore_Domain_Ids:
                 Parallel_Mode: optimistic
                     SQL_Delay: 0
           SQL_Remaining_Delay: NULL
       Slave_SQL_Running_State:
              Slave_DDL_Groups: 0
Slave_Non_Transactional_Groups: 0
    Slave_Transactional_Groups: 0
1 row in set (0.000 sec)
```


- 새로 Slave로 지정한 DB 재기동 진행 
```
systemctl restart mysql
```

- 재기동 완료 후 설정확인

```sql
MariaDB [(none)]> show slave status \G
*************************** 1. row ***************************
                Slave_IO_State: Waiting for master to send event
                   Master_Host: 192.168.1.102
                   Master_User: repl_user
                   Master_Port: 3306
                 Connect_Retry: 60
               Master_Log_File: mysql-bin.000005
           Read_Master_Log_Pos: 342
                Relay_Log_File: db-01-relay-bin.000003
                 Relay_Log_Pos: 555
         Relay_Master_Log_File: mysql-bin.000005
              Slave_IO_Running: Yes
             Slave_SQL_Running: Yes
               Replicate_Do_DB: repl_db
           Replicate_Ignore_DB:
            Replicate_Do_Table:
        Replicate_Ignore_Table:
       Replicate_Wild_Do_Table:
   Replicate_Wild_Ignore_Table:
                    Last_Errno: 0
                    Last_Error:
                  Skip_Counter: 0
           Exec_Master_Log_Pos: 342
               Relay_Log_Space: 864
               Until_Condition: None
                Until_Log_File:
                 Until_Log_Pos: 0
            Master_SSL_Allowed: No
            Master_SSL_CA_File:
            Master_SSL_CA_Path:
               Master_SSL_Cert:
             Master_SSL_Cipher:
                Master_SSL_Key:
         Seconds_Behind_Master: 0
 Master_SSL_Verify_Server_Cert: No
                 Last_IO_Errno: 0
                 Last_IO_Error:
                Last_SQL_Errno: 0
                Last_SQL_Error:
   Replicate_Ignore_Server_Ids:
              Master_Server_Id: 2
                Master_SSL_Crl:
            Master_SSL_Crlpath:
                    Using_Gtid: No
                   Gtid_IO_Pos:
       Replicate_Do_Domain_Ids:
   Replicate_Ignore_Domain_Ids:
                 Parallel_Mode: optimistic
                     SQL_Delay: 0
           SQL_Remaining_Delay: NULL
       Slave_SQL_Running_State: Slave has read all relay log; waiting for more updates
              Slave_DDL_Groups: 0
Slave_Non_Transactional_Groups: 0
    Slave_Transactional_Groups: 0
1 row in set (0.000 sec)
```


### 정상 작동 확인 

- 현재 설정 
    - Master : 192.168.1.102
    - Slave : 192.168.1.101

- Master(192.168.1.102) 에서 테이블 생성 및 insert 
```sql
MariaDB [repl_db]> create table test_tbl3 (id int , name varchar(10));
Query OK, 0 rows affected (0.096 sec)

MariaDB [repl_db]> insert into test_tbl3 values ( 3, 'test');
Query OK, 1 row affected (0.019 sec)

MariaDB [repl_db]> commit;
Query OK, 0 rows affected (0.000 sec)
```

- Slave(192.168.1.101) 에서 확인 
```sql
MariaDB [repl_db]> select * from test_tbl3;
+------+------+
| id   | name |
+------+------+
|    3 | test |
+------+------+
1 row in set (0.000 sec)
```


## Master-Master 관계로 변경하기 

- 기존 Slave(192.168.1.101) 를 Master(192.168.1.102)의 Master로 지정하기 

### Slave(192.168.1.101)
```
MariaDB [(none)]> show master status;
+------------------+----------+--------------+------------------+
| File             | Position | Binlog_Do_DB | Binlog_Ignore_DB |
+------------------+----------+--------------+------------------+
| mysql-bin.000008 |      655 |              |                  |
+------------------+----------+--------------+------------------+
1 row in set (0.000 sec)
```

### Master(192.168.1.102)
- Slave를 master로 지정 
```sql
change master to master_host='192.168.1.101' , master_user='repl_user' , master_password='test123' , master_log_file='mysql-bin.000007' , master_log_pos=655;
```

- mysqld 재기동 후 연결 확인 
```
systemctl restart mysqld 
```

### 결과 
- 기존 Master-Slave 형태와 다르게 양쪽 모두에서 R/W 작업이 가능
- multi-master 구성에서 auto-increment 값이 겹쳐서 충돌나면 안되기 때문에 master 끼리는 auto-increment 증가값을 다르게 설정필요
