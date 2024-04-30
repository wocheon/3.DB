# MYSQL MHA 구성 (In GCP)

## MHA (Master High Availability)

- 특징 
    - Perl 기반의 Auto Failover Opensouce
    - Agentless 방식
    - 하나의 마스터와 Slave로 구성 (Slave는 다수 가능)


### MHA failover 

- MHA 환경 Failover 절차 
    - 마스터 DB가 장애가 나는 경우 마스터와 기존 Slave와의 복제를 끊는다.
    - 나머지 DB들로 복제를 재구성
    - 마스터 DB가 정상 복구 되어도 Replication 설정을 다시 진행해주어야함.

- Failover 대상
    - MHA의 FAILOVER대상은 고정되지 않음 (MMM과 다름)
    - 승격 기준 : 가장 최신의 데이터를 가지고 있는 DB를 마스터로 승격
    - MMM환경에서 발생가능한 복제 Crush 현상을 방지하기 위해서 별도의 절차를 수행
        - 복제 구성 대상 
            - 바이너리 로그, 릴레이 로그 파일
            - 해당 파일을 통해 데이터 비교 후 다른 데이터를 추출


## MHA 환경 구성

### 구현 환경 
- GCP 환경 내에서 구성 하며 Alias IP를 통해 VIP 구현 
    - Failover 발생 시 VIP를 변경하는 방식으로 진행

|구분|서버명|IP|Alias IP(VIP)|
|:-:|:-:|:-:|:-:|
|MHA Manager|mha|192.168.1.100|x|
|Master|db-01|192.168.1.101|192.168.1.201|
|Slave|db-02|192.168.1.102|192.168.1.202|


### MHA 계정 생성 
- DB-01, DB-02 양쪽에 MHA용 계정 생성 및 권한 부여
```sql
grant all privileges on *.* to 'mha'@'%' identified by 'mhapassword';
```



### MHA 설치 
- MHA, 모든 DB에 MHA 도구 설치 
    - MHA Manager는 Manage, Node 모두 설치 
    - DB는 Node만 설치 


- 컴파일을 위한 도구 설치 
```bash
# DB(master/slave)
yum -y install perl-CPAN perl-DBD-MySQL perl-Module-Install git

# MHA Manager
yum -y install perl-CPAN perl-DBD-MySQL perl-Module-Install perl-Config-Tiny perl-Log-Dispatch perl-Parallel-ForkManager git
```

- MHA 설치 
    - 공식 파일을 못 찾아서.. 우선 Github통해서 파일 다운로드 진행 
        - https://github.com/lzimd/mha-rpms.git

```bash
mkdir /root/mha_rpms
cd /root/mha_rpms
git clone https://github.com/lzimd/mha-rpms.git .


ls -l *57*
-rw-r--r-- 1 root root  81080 Apr 30 00:41 mha4mysql-manager-0.57-0.el7.noarch.rpm
-rw-r--r-- 1 root root 118521 Apr 30 00:41 mha4mysql-manager-0.57.tar.gz
-rw-r--r-- 1 root root  35360 Apr 30 00:41 mha4mysql-node-0.57-0.el7.noarch.rpm
-rw-r--r-- 1 root root  54484 Apr 30 00:41 mha4mysql-node-0.57.tar.gz
```


```bash
#DB(master/slave) 
cp mha4mysql-node-0.57.tar.gz /root
tar xvf mha4mysql-node-0.57.tar.gz 

cd mha4mysql-node-0.57
perl Makefile.PL 
make && make install

# MHA Manager - mha4mysql-node
cp mha4mysql-node-0.57.tar.gz /root
tar xvf mha4mysql-node-0.57.tar.gz 

cd mha4mysql-node-0.57
perl Makefile.PL 
make && make install

#  MHA Manager - mha4mysql-manager 
cp mha4mysql-manager-0.57.tar.gz /root
tar xvf mha4mysql-manager-0.57.tar.gz 

cd mha4mysql-manager-0.57
perl Makefile.PL 
make && make install
```

### MHA log Directory 생성 
```
mkdir /var/log/mha
```

### MHA conf 파일 설정 
- sample 파일 복사 후 수정하여 사용

```sh
mkdir -p /etc/mha/scripts
cp /root/mha4mysql-manager-0.57/samples/conf/masterha_default.cnf /etc/mha/

cp /root/mha4mysql-manager-0.57/samples/scripts/* /etc/mha/scripts/
```

- masterha-default.cnf
    - 주석있으면 오류나므로 주의
    - failover 가 발생하면 master_ip_failover 실행 
    - 원복 시 master_ip_online_change 실행
```
[server default]
user=mha
password=mhapassword
manager_workdir=/var/log/mha
manager_log=/var/log/mha/MHA.log
remote_workdir=/var/log/mha
master_ip_failover_script=/etc/mha/scripts/master_ip_failover
master_ip_online_change_script=/etc/mha/scripts/master_ip_online_change

[server1]
hostname=192.168.1.101
master_binlog_dir=/var/lib/mysql
candidate_master=1

[server2]
hostname=192.168.1.102
master_binlog_dir=/var/lib/mysql
candidate_master=1
```

- scripts/master_ip_failover

```perl
#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use Getopt::Long;
use MHA::DBHelper;

my (
  $command,        $ssh_user,         $orig_master_host,
  $orig_master_ip, $orig_master_port, $new_master_host,
  $new_master_ip,  $new_master_port,  $new_master_user,
  $new_master_password
);
GetOptions(
  'command=s'             => \$command,
  'ssh_user=s'            => \$ssh_user,
  'orig_master_host=s'    => \$orig_master_host,
  'orig_master_ip=s'      => \$orig_master_ip,
  'orig_master_port=i'    => \$orig_master_port,
  'new_master_host=s'     => \$new_master_host,
  'new_master_ip=s'       => \$new_master_ip,
  'new_master_port=i'     => \$new_master_port,
  'new_master_user=s'     => \$new_master_user,
  'new_master_password=s' => \$new_master_password,
);

exit &main();

sub main {
  if ( $command eq "stop" || $command eq "stopssh" ) {

    # $orig_master_host, $orig_master_ip, $orig_master_port are passed.
    # If you manage master ip address at global catalog database,
    # invalidate orig_master_ip here.
    my $exit_code = 1;
    eval {

      # updating global catalog, etc
      $exit_code = 0;
    };
    if ($@) {
      warn "Got Error: $@\n";
      exit $exit_code;
    }
    exit $exit_code;
  }
  elsif ( $command eq "start" ) {

    # all arguments are passed.
    # If you manage master ip address at global catalog database,
    # activate new_master_ip here.
    # You can also grant write access (create user, set read_only=0, etc) here.
    my $exit_code = 10;
    eval {
      my $new_master_handler = new MHA::DBHelper();

      # args: hostname, port, user, password, raise_error_or_not
      $new_master_handler->connect( $new_master_ip, $new_master_port,
        $new_master_user, $new_master_password, 1 );

      ## Set read_only=0 on the new master
      $new_master_handler->disable_log_bin_local();
      print "Set read_only=0 on the new master.\n";
      $new_master_handler->disable_read_only();

      ## Creating an app user on the new master
# 아래 4줄 주석처리      
#      print "Creating app user on the new master..\n";
#      FIXME_xxx_create_user( $new_master_handler->{dbh} );
#      $new_master_handler->enable_log_bin_local();
#      $new_master_handler->disconnect();

      ## Update master ip on the catalog database, etc
# 아래 줄 주석처리      
#      FIXME_xxx;

# 스크립트 구문 추가
      if($new_master_ip eq "192.168.1.101"){
        system("/bin/sh /etc/mha/scripts/slave_up.sh");
        }
      elsif($new_master_ip eq "192.168.1.102"){
        system("/bin/sh /etc/mha/scripts/master_up.sh");
        }
# 스크립트 구문 추가

      $exit_code = 0;
    };
    if ($@) {
      warn $@;

      # If you want to continue failover, exit 10.
      exit $exit_code;
    }
    exit $exit_code;
  }
  elsif ( $command eq "status" ) {

    # do nothing
    exit 0;
  }
  else {
    &usage();
    exit 1;
  }
}

sub usage {
  print
"Usage: master_ip_failover --command=start|stop|stopssh|status --orig_master_host=host --orig_master_ip=ip --orig_master_port=port --new_master_host=host --new_master_ip=ip --new_master_port=port\n";
}
```
- scripts/master_ip_online_change

```perl
#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use Getopt::Long;
use MHA::DBHelper;
use MHA::NodeUtil;
use Time::HiRes qw( sleep gettimeofday tv_interval );
use Data::Dumper;

my $_tstart;
my $_running_interval = 0.1;
my (
  $command,              $orig_master_is_new_slave, $orig_master_host,
  $orig_master_ip,       $orig_master_port,         $orig_master_user,
  $orig_master_password, $orig_master_ssh_user,     $new_master_host,
  $new_master_ip,        $new_master_port,          $new_master_user,
  $new_master_password,  $new_master_ssh_user,
);
GetOptions(
  'command=s'                => \$command,
  'orig_master_is_new_slave' => \$orig_master_is_new_slave,
  'orig_master_host=s'       => \$orig_master_host,
  'orig_master_ip=s'         => \$orig_master_ip,
  'orig_master_port=i'       => \$orig_master_port,
  'orig_master_user=s'       => \$orig_master_user,
  'orig_master_password=s'   => \$orig_master_password,
  'orig_master_ssh_user=s'   => \$orig_master_ssh_user,
  'new_master_host=s'        => \$new_master_host,
  'new_master_ip=s'          => \$new_master_ip,
  'new_master_port=i'        => \$new_master_port,
  'new_master_user=s'        => \$new_master_user,
  'new_master_password=s'    => \$new_master_password,
  'new_master_ssh_user=s'    => \$new_master_ssh_user,
);

exit &main();

sub current_time_us {
  my ( $sec, $microsec ) = gettimeofday();
  my $curdate = localtime($sec);
  return $curdate . " " . sprintf( "%06d", $microsec );
}

sub sleep_until {
  my $elapsed = tv_interval($_tstart);
  if ( $_running_interval > $elapsed ) {
    sleep( $_running_interval - $elapsed );
  }
}

sub get_threads_util {
  my $dbh                    = shift;
  my $my_connection_id       = shift;
  my $running_time_threshold = shift;
  my $type                   = shift;
  $running_time_threshold = 0 unless ($running_time_threshold);
  $type                   = 0 unless ($type);
  my @threads;

  my $sth = $dbh->prepare("SHOW PROCESSLIST");
  $sth->execute();

  while ( my $ref = $sth->fetchrow_hashref() ) {
    my $id         = $ref->{Id};
    my $user       = $ref->{User};
    my $host       = $ref->{Host};
    my $command    = $ref->{Command};
    my $state      = $ref->{State};
    my $query_time = $ref->{Time};
    my $info       = $ref->{Info};
    $info =~ s/^\s*(.*?)\s*$/$1/ if defined($info);
    next if ( $my_connection_id == $id );
    next if ( defined($query_time) && $query_time < $running_time_threshold );
    next if ( defined($command)    && $command eq "Binlog Dump" );
    next if ( defined($user)       && $user eq "system user" );
    next
      if ( defined($command)
      && $command eq "Sleep"
      && defined($query_time)
      && $query_time >= 1 );

    if ( $type >= 1 ) {
      next if ( defined($command) && $command eq "Sleep" );
      next if ( defined($command) && $command eq "Connect" );
    }

    if ( $type >= 2 ) {
      next if ( defined($info) && $info =~ m/^select/i );
      next if ( defined($info) && $info =~ m/^show/i );
    }

    push @threads, $ref;
  }
  return @threads;
}

sub main {
  if ( $command eq "stop" ) {
    ## Gracefully killing connections on the current master
    # 1. Set read_only= 1 on the new master
    # 2. DROP USER so that no app user can establish new connections
    # 3. Set read_only= 1 on the current master
    # 4. Kill current queries
    # * Any database access failure will result in script die.
    my $exit_code = 1;
    eval {
      ## Setting read_only=1 on the new master (to avoid accident)
      my $new_master_handler = new MHA::DBHelper();

      # args: hostname, port, user, password, raise_error(die_on_error)_or_not
      $new_master_handler->connect( $new_master_ip, $new_master_port,
        $new_master_user, $new_master_password, 1 );
      print current_time_us() . " Set read_only on the new master.. ";
      $new_master_handler->enable_read_only();
      if ( $new_master_handler->is_read_only() ) {
        print "ok.\n";
      }
      else {
        die "Failed!\n";
      }
      $new_master_handler->disconnect();

      # Connecting to the orig master, die if any database error happens
      my $orig_master_handler = new MHA::DBHelper();
      $orig_master_handler->connect( $orig_master_ip, $orig_master_port,
        $orig_master_user, $orig_master_password, 1 );

      ## Drop application user so that nobody can connect. Disabling per-session binlog beforehand
      $orig_master_handler->disable_log_bin_local();
      print current_time_us() . " Drpping app user on the orig master..\n";
      #FIXME_xxx_drop_app_user($orig_master_handler);

      ## Waiting for N * 100 milliseconds so that current connections can exit
      my $time_until_read_only = 15;
      $_tstart = [gettimeofday];
      my @threads = get_threads_util( $orig_master_handler->{dbh},
        $orig_master_handler->{connection_id} );
      while ( $time_until_read_only > 0 && $#threads >= 0 ) {
        if ( $time_until_read_only % 5 == 0 ) {
          printf
"%s Waiting all running %d threads are disconnected.. (max %d milliseconds)\n",
            current_time_us(), $#threads + 1, $time_until_read_only * 100;
          if ( $#threads < 5 ) {
            print Data::Dumper->new( [$_] )->Indent(0)->Terse(1)->Dump . "\n"
              foreach (@threads);
          }
        }
        sleep_until();
        $_tstart = [gettimeofday];
        $time_until_read_only--;
        @threads = get_threads_util( $orig_master_handler->{dbh},
          $orig_master_handler->{connection_id} );
      }

      ## Setting read_only=1 on the current master so that nobody(except SUPER) can write
      print current_time_us() . " Set read_only=1 on the orig master.. ";
      $orig_master_handler->enable_read_only();
      if ( $orig_master_handler->is_read_only() ) {
        print "ok.\n";
      }
      else {
        die "Failed!\n";
      }

      ## Waiting for M * 100 milliseconds so that current update queries can complete
      my $time_until_kill_threads = 5;
      @threads = get_threads_util( $orig_master_handler->{dbh},
        $orig_master_handler->{connection_id} );
      while ( $time_until_kill_threads > 0 && $#threads >= 0 ) {
        if ( $time_until_kill_threads % 5 == 0 ) {
          printf
"%s Waiting all running %d queries are disconnected.. (max %d milliseconds)\n",
            current_time_us(), $#threads + 1, $time_until_kill_threads * 100;
          if ( $#threads < 5 ) {
            print Data::Dumper->new( [$_] )->Indent(0)->Terse(1)->Dump . "\n"
              foreach (@threads);
          }
        }
        sleep_until();
        $_tstart = [gettimeofday];
        $time_until_kill_threads--;
        @threads = get_threads_util( $orig_master_handler->{dbh},
          $orig_master_handler->{connection_id} );
      }

      ## Terminating all threads
      print current_time_us() . " Killing all application threads..\n";
      $orig_master_handler->kill_threads(@threads) if ( $#threads >= 0 );
      print current_time_us() . " done.\n";
      $orig_master_handler->enable_log_bin_local();
      $orig_master_handler->disconnect();

      ## After finishing the script, MHA executes FLUSH TABLES WITH READ LOCK
      $exit_code = 0;
    };
    if ($@) {
      warn "Got Error: $@\n";
      exit $exit_code;
    }
    exit $exit_code;
  }
  elsif ( $command eq "start" ) {
    ## Activating master ip on the new master
    # 1. Create app user with write privileges
    # 2. Moving backup script if needed
    # 3. Register new master's ip to the catalog database

# We don't return error even though activating updatable accounts/ip failed so that we don't interrupt slaves' recovery.
# If exit code is 0 or 10, MHA does not abort
    my $exit_code = 10;
    eval {
      my $new_master_handler = new MHA::DBHelper();

      # args: hostname, port, user, password, raise_error_or_not
      $new_master_handler->connect( $new_master_ip, $new_master_port,
        $new_master_user, $new_master_password, 1 );

      ## Set read_only=0 on the new master
      $new_master_handler->disable_log_bin_local();
      print current_time_us() . " Set read_only=0 on the new master.\n";
      $new_master_handler->disable_read_only();

      ## Creating an app user on the new master
# 아래 4줄 주석처리      
#      print current_time_us() . " Creating app user on the new master..\n";
#      FIXME_xxx_create_app_user($new_master_handler);
#      $new_master_handler->enable_log_bin_local();
#      $new_master_handler->disconnect();

      ## Update master ip on the catalog database, etc

# 스크립트 구문 추가
      if($new_master_ip eq "192.168.1.101"){
        system("/bin/sh /etc/mha/scripts/slave_up.sh");
        }
      elsif($new_master_ip eq "192.168.1.102"){
        system("/bin/sh /etc/mha/scripts/master_up.sh");
        }
# 스크립트 구문 추가


      $exit_code = 0;
    };
    if ($@) {
      warn "Got Error: $@\n";
      exit $exit_code;
    }
    exit $exit_code;
  }
  elsif ( $command eq "status" ) {

    # do nothing
    exit 0;
  }
  else {
    &usage();
    exit 1;
  }
}

sub usage {
  print
"Usage: master_ip_online_change --command=start|stop|status --orig_master_host=host --orig_master_ip=ip --orig_master_port=port --new_master_host=host --new_master_ip=ip --new_master_port=port\n";
  die;
}
```

### GCP VIP 변경용 스크립트 
- gcloud 명령어를 사용해야하므로 mha VM의 서비스계정 지정 및 Cloud API 액세스 범위 조정 필요 
    - gcloud init으로 로그인 후 gcloud 명령어 실행여부 확인

- slave_up.sh
    - failover 발생시 사용할 스크립트
```
#!/bin/bash
gcloud compute instances network-interfaces update db-01 --zone asia-northeast3-a --aliases ""
gcloud compute instances network-interfaces update db-02 --zone asia-northeast3-a --aliases ""
gcloud compute instances network-interfaces update db-01 --zone asia-northeast3-a --aliases 192.168.1.201
gcloud compute instances network-interfaces update db-02 --zone asia-northeast3-a --aliases 192.168.1.202
```
- master_up.sh 
    - 원복시 사용할 스크립트
```
#!/bin/bash
gcloud compute instances network-interfaces update db-01 --zone asia-northeast3-a --aliases ""
gcloud compute instances network-interfaces update db-02 --zone asia-northeast3-a --aliases ""
gcloud compute instances network-interfaces update db-01 --zone asia-northeast3-a --aliases 192.168.1.202
gcloud compute instances network-interfaces update db-02 --zone asia-northeast3-a --aliases 192.168.1.201
```


### SSH 키 교환 
- MHA 환경 구성 시 SSH 키를 통해 패스워드없이 SSH 접속이 가능하도록 설정해야함 

```sh
 ssh-keygen -b 2048 -t rsa -f ~/.ssh/id_rsa -q -N ""
```

- Manager 
    - 모든 DB + 자기자신의 공개 키를 Authorized_keys에 추가 
- DB-01
    - DB-02 공개 키를 Authorized_keys에 추가  
- DB-02
    - DB-01 공개 키를 Authorized_keys에 추가     


### DB Replication 설정 
- DB-01은 Master DB-02는 Slave로 구성되도록 Replication 설정 진행

- /etc/my.cnf
```sh
#DB-01
[mysqld]
server-id=1
log-bin=mysql-bin

#DB-02
[mysqld]
server-id=2
log-bin=mysql-bin
```

- mysqld 재기동 (모든DB)
```
systemctl restart mysqld
```

- Replication 용 계정 생성 (모든DB)
```
grant replication slave on *.* to repl_user@'%' identified by 'test123';
```

- Replication 진행
```sql
--DB-01
MariaDB [(none)]> show master status;
+------------------+----------+--------------+------------------+
| File             | Position | Binlog_Do_DB | Binlog_Ignore_DB |
+------------------+----------+--------------+------------------+
| mysql-bin.000005 |      342 |              |                  |
+------------------+----------+--------------+------------------+
1 row in set (0.000 sec)

--DB-02
MariaDB [(none)]> change master to master_host='192.168.1.101' , master_user='repl_user' , master_password='test123' , master_log_file='mysql-bin.000005' , master_log_pos=342;

MariaDB [(none)]> start slave;

MariaDB [(none)]> show slave status \G
*************************** 1. row ***************************
                Slave_IO_State: Waiting for master to send event
                   Master_Host: 192.168.1.101
                   Master_User: repl_user
                   Master_Port: 3306
                 Connect_Retry: 60
               Master_Log_File: mysql-bin.000005
           Read_Master_Log_Pos: 342
                Relay_Log_File: db-02-relay-bin.000002
                 Relay_Log_Pos: 555
         Relay_Master_Log_File: mysql-bin.000005
              Slave_IO_Running: Yes
             Slave_SQL_Running: Yes
```


###  MHA 연결 확인 
```sh
$ masterha_check_ssh --conf=/etc/mha/masterha-default.cnf
Tue Apr 30 07:19:43 2024 - [warning] Global configuration file /etc/masterha_default.cnf not found. Skipping.
Tue Apr 30 07:19:43 2024 - [info] Reading application default configuration from /etc/mha/masterha-default.cnf..
Tue Apr 30 07:19:43 2024 - [info] Reading server configuration from /etc/mha/masterha-default.cnf..
Tue Apr 30 07:19:43 2024 - [info] Starting SSH connection tests..
Tue Apr 30 07:19:43 2024 - [debug]
Tue Apr 30 07:19:43 2024 - [debug]  Connecting via SSH from root@192.168.1.101(192.168.1.101:22) to root@192.168.1.102(192.168.1.102:22)..
Tue Apr 30 07:19:43 2024 - [debug]   ok.
Tue Apr 30 07:19:44 2024 - [debug]
Tue Apr 30 07:19:43 2024 - [debug]  Connecting via SSH from root@192.168.1.102(192.168.1.102:22) to root@192.168.1.101(192.168.1.101:22)..
Tue Apr 30 07:19:44 2024 - [debug]   ok.
Tue Apr 30 07:19:44 2024 - [info] All SSH connection tests passed successfully.
```

### MHA Manager 실행 
```sh
$ nohup masterha_manager --conf=/etc/mha/masterha-default.cnf &

$ tail -f /etc/mha/MHA.log
Tue Apr 30 07:26:57 2024 - [info] MHA::MasterMonitor version 0.57.
Tue Apr 30 07:26:59 2024 - [info] GTID failover mode = 0
Tue Apr 30 07:26:59 2024 - [info] Dead Servers:
Tue Apr 30 07:26:59 2024 - [info] Alive Servers:
Tue Apr 30 07:26:59 2024 - [info]   192.168.1.101(192.168.1.101:3306)
Tue Apr 30 07:26:59 2024 - [info]   192.168.1.102(192.168.1.102:3306)
Tue Apr 30 07:26:59 2024 - [info] Alive Slaves:
Tue Apr 30 07:26:59 2024 - [info]   192.168.1.102(192.168.1.102:3306)  Version=10.5.24-MariaDB-log (oldest major version between slaves) log-bin:enabled
Tue Apr 30 07:26:59 2024 - [info]     Replicating from 192.168.1.101(192.168.1.101:3306)
Tue Apr 30 07:26:59 2024 - [info]     Primary candidate for the new Master (candidate_master is set)
Tue Apr 30 07:26:59 2024 - [info] Current Alive Master: 192.168.1.101(192.168.1.101:3306)
Tue Apr 30 07:26:59 2024 - [info] Checking slave configurations..
Tue Apr 30 07:26:59 2024 - [info] Checking replication filtering settings..
Tue Apr 30 07:26:59 2024 - [info]  binlog_do_db= , binlog_ignore_db=
Tue Apr 30 07:26:59 2024 - [info]  Replication filtering check ok.
Tue Apr 30 07:26:59 2024 - [info] GTID (with auto-pos) is not supported
Tue Apr 30 07:26:59 2024 - [info] Starting SSH connection tests..
Tue Apr 30 07:27:00 2024 - [info] All SSH connection tests passed successfully.
Tue Apr 30 07:27:00 2024 - [info] Checking MHA Node version..
Tue Apr 30 07:27:00 2024 - [info]  Version check ok.
Tue Apr 30 07:27:00 2024 - [info] Checking SSH publickey authentication settings on the current master..
Tue Apr 30 07:27:00 2024 - [info] HealthCheck: SSH to 192.168.1.101 is reachable.
Tue Apr 30 07:27:00 2024 - [info] Master MHA Node version is 0.57.
Tue Apr 30 07:27:00 2024 - [info] Checking recovery script configurations on 192.168.1.101(192.168.1.101:3306)..
Tue Apr 30 07:27:00 2024 - [info]   Executing command: save_binary_logs --command=test --start_pos=4 --binlog_dir=/var/lib/mysql --output_file=/var/log/mha/save_binary_logs_test --manager_version=0.57 --start_file=mysql-bin.000005
Tue Apr 30 07:27:00 2024 - [info]   Connecting to root@192.168.1.101(192.168.1.101:22)..
  Creating /var/log/mha if not exists..    ok.
  Checking output directory is accessible or not..
   ok.
  Binlog found at /var/lib/mysql, up to mysql-bin.000005
Tue Apr 30 07:27:00 2024 - [info] Binlog setting check done.
Tue Apr 30 07:27:00 2024 - [info] Checking SSH publickey authentication and checking recovery script configurations on all alive slave servers..
Tue Apr 30 07:27:00 2024 - [info]   Executing command : apply_diff_relay_logs --command=test --slave_user='mha' --slave_host=192.168.1.102 --slave_ip=192.168.1.102 --slave_port=3306 --workdir=/var/log/mha --target_version=10.5.24-MariaDB-log --manager_version=0.57 --relay_log_info=/var/lib/mysql/relay-log.info  --relay_dir=/var/lib/mysql/  --slave_pass=xxx
Tue Apr 30 07:27:00 2024 - [info]   Connecting to root@192.168.1.102(192.168.1.102:22)..
  Checking slave recovery environment settings..
    Opening /var/lib/mysql/relay-log.info ... ok.
    Relay log found at /var/lib/mysql, up to db-02-relay-bin.000002
    Temporary relay log file is /var/lib/mysql/db-02-relay-bin.000002
    Testing mysql connection and privileges.. done.
    Testing mysqlbinlog output.. done.
    Cleaning up test file(s).. done.
Tue Apr 30 07:27:01 2024 - [info] Slaves settings check done.
Tue Apr 30 07:27:01 2024 - [info]
192.168.1.101(192.168.1.101:3306) (current master)
 +--192.168.1.102(192.168.1.102:3306)

Tue Apr 30 07:27:01 2024 - [info] Checking master_ip_failover_script status:
Tue Apr 30 07:27:01 2024 - [info]   /etc/mha/scripts/master_ip_failover --command=status --ssh_user=root --orig_master_host=192.168.1.101 --orig_master_ip=192.168.1.101 --orig_master_port=3306
Tue Apr 30 07:27:01 2024 - [info]  OK.
Tue Apr 30 07:27:01 2024 - [warning] shutdown_script is not defined.
Tue Apr 30 07:27:01 2024 - [info] Set master ping interval 3 seconds.
Tue Apr 30 07:27:01 2024 - [warning] secondary_check_script is not defined. It is highly recommended setting it to check master reachability from two or more routes.
Tue Apr 30 07:27:01 2024 - [info] Starting ping health check on 192.168.1.101(192.168.1.101:3306)..
Tue Apr 30 07:27:01 2024 - [info] Ping(SELECT) succeeded, waiting until MySQL doesn't respond..

```

- 정상동작 확인 
    - master(db-01) Helth-check를 진행
    - master(db-01)에 문제 발생하기 전까지 대기

```sh
$ ps -ef | grep mha
root      3275  1168  0 07:26 pts/0    00:00:00 perl /usr/local/bin/masterha_manager --conf=/etc/mha/masterha-default.cnf
```


## Failover Test 진행 
- 현재 Master인 DB-01의 mysqld를 중지 
```
systemctl stop mysqld
```

- failover 발생 
    - 5번 연결확인 후 Failover 진행 
    - 지정된 스크립트를 실행 (VIP 변경용 스크립트)
        - GCP Alias IP 변경 
            - db-01(down) : 192.168.1.201 -> 192.168.1.202
            - db-02(alive) : 192.168.1.202 -> 192.168.1.201
    - 기존 Slave를 Master로 승격 
        - Replication 구성 해제

    - failover 조치 완료 후 masterha_manager 종료됨
```sh
Tue Apr 30 07:32:04 2024 - [warning] Got error on MySQL select ping: 2006 (MySQL server has gone away)
Tue Apr 30 07:32:04 2024 - [info] Executing SSH check script: save_binary_logs --command=test --start_pos=4 --binlog_dir=/var/lib/mysql --output_file=/var/log/mha/save_binary_logs_test --manager_version=0.57 --binlog_prefix=mysql-bin
Tue Apr 30 07:32:04 2024 - [info] HealthCheck: SSH to 192.168.1.101 is reachable.
Tue Apr 30 07:32:07 2024 - [warning] Got error on MySQL connect: 2003 (Can't connect to MySQL server on '192.168.1.101' (111))
Tue Apr 30 07:32:07 2024 - [warning] Connection failed 2 time(s)..
Tue Apr 30 07:32:10 2024 - [warning] Got error on MySQL connect: 2003 (Can't connect to MySQL server on '192.168.1.101' (111))
Tue Apr 30 07:32:10 2024 - [warning] Connection failed 3 time(s)..
Tue Apr 30 07:32:13 2024 - [warning] Got error on MySQL connect: 2003 (Can't connect to MySQL server on '192.168.1.101' (111))
Tue Apr 30 07:32:13 2024 - [warning] Connection failed 4 time(s)..
Tue Apr 30 07:32:13 2024 - [warning] Master is not reachable from health checker!
Tue Apr 30 07:32:13 2024 - [warning] Master 192.168.1.101(192.168.1.101:3306) is not reachable!
Tue Apr 30 07:32:13 2024 - [warning] SSH is reachable.
Tue Apr 30 07:32:13 2024 - [info] Connecting to a master server failed. Reading configuration file /etc/masterha_default.cnf and /etc/mha/masterha-default.cnf again, and trying to connect to all servers to check server status..
Tue Apr 30 07:32:13 2024 - [warning] Global configuration file /etc/masterha_default.cnf not found. Skipping.
Tue Apr 30 07:32:13 2024 - [info] Reading application default configuration from /etc/mha/masterha-default.cnf..
Tue Apr 30 07:32:13 2024 - [info] Reading server configuration from /etc/mha/masterha-default.cnf..
Tue Apr 30 07:32:14 2024 - [info] GTID failover mode = 0
Tue Apr 30 07:32:14 2024 - [info] Dead Servers:
Tue Apr 30 07:32:14 2024 - [info]   192.168.1.101(192.168.1.101:3306)
Tue Apr 30 07:32:14 2024 - [info] Alive Servers:
Tue Apr 30 07:32:14 2024 - [info]   192.168.1.102(192.168.1.102:3306)
Tue Apr 30 07:32:14 2024 - [info] Alive Slaves:
Tue Apr 30 07:32:14 2024 - [info]   192.168.1.102(192.168.1.102:3306)  Version=10.5.24-MariaDB-log (oldest major version between slaves) log-bin:enabled
Tue Apr 30 07:32:14 2024 - [info]     Replicating from 192.168.1.101(192.168.1.101:3306)
Tue Apr 30 07:32:14 2024 - [info]     Primary candidate for the new Master (candidate_master is set)
Tue Apr 30 07:32:14 2024 - [info] Checking slave configurations..
Tue Apr 30 07:32:14 2024 - [info] Checking replication filtering settings..
Tue Apr 30 07:32:14 2024 - [info]  Replication filtering check ok.
Tue Apr 30 07:32:14 2024 - [info] Master is down!
Tue Apr 30 07:32:14 2024 - [info] Terminating monitoring script.
Tue Apr 30 07:32:14 2024 - [info] Got exit code 20 (Master dead).
Tue Apr 30 07:32:14 2024 - [info] MHA::MasterFailover version 0.57.
Tue Apr 30 07:32:14 2024 - [info] Starting master failover.
Tue Apr 30 07:32:14 2024 - [info]
Tue Apr 30 07:32:14 2024 - [info] * Phase 1: Configuration Check Phase..
Tue Apr 30 07:32:14 2024 - [info]
Tue Apr 30 07:32:15 2024 - [info] GTID failover mode = 0
Tue Apr 30 07:32:15 2024 - [info] Dead Servers:
Tue Apr 30 07:32:15 2024 - [info]   192.168.1.101(192.168.1.101:3306)
Tue Apr 30 07:32:15 2024 - [info] Checking master reachability via MySQL(double check)...
Tue Apr 30 07:32:15 2024 - [info]  ok.
Tue Apr 30 07:32:15 2024 - [info] Alive Servers:
Tue Apr 30 07:32:15 2024 - [info]   192.168.1.102(192.168.1.102:3306)
Tue Apr 30 07:32:15 2024 - [info] Alive Slaves:
Tue Apr 30 07:32:15 2024 - [info]   192.168.1.102(192.168.1.102:3306)  Version=10.5.24-MariaDB-log (oldest major version between slaves) log-bin:enabled
Tue Apr 30 07:32:15 2024 - [info]     Replicating from 192.168.1.101(192.168.1.101:3306)
Tue Apr 30 07:32:15 2024 - [info]     Primary candidate for the new Master (candidate_master is set)
Tue Apr 30 07:32:15 2024 - [info] Starting Non-GTID based failover.
Tue Apr 30 07:32:15 2024 - [info]
Tue Apr 30 07:32:15 2024 - [info] ** Phase 1: Configuration Check Phase completed.
Tue Apr 30 07:32:15 2024 - [info]
Tue Apr 30 07:32:15 2024 - [info] * Phase 2: Dead Master Shutdown Phase..
Tue Apr 30 07:32:15 2024 - [info]
Tue Apr 30 07:32:15 2024 - [info] Forcing shutdown so that applications never connect to the current master..
Tue Apr 30 07:32:15 2024 - [info] Executing master IP deactivation script:
Tue Apr 30 07:32:15 2024 - [info]   /etc/mha/scripts/master_ip_failover --orig_master_host=192.168.1.101 --orig_master_ip=192.168.1.101 --orig_master_port=3306 --command=stopssh --ssh_user=root
Tue Apr 30 07:32:15 2024 - [info]  done.
Tue Apr 30 07:32:15 2024 - [warning] shutdown_script is not set. Skipping explicit shutting down of the dead master.
Tue Apr 30 07:32:15 2024 - [info] * Phase 2: Dead Master Shutdown Phase completed.
Tue Apr 30 07:32:15 2024 - [info]
Tue Apr 30 07:32:15 2024 - [info] * Phase 3: Master Recovery Phase..
Tue Apr 30 07:32:15 2024 - [info]
Tue Apr 30 07:32:15 2024 - [info] * Phase 3.1: Getting Latest Slaves Phase..
Tue Apr 30 07:32:15 2024 - [info]
Tue Apr 30 07:32:15 2024 - [info] The latest binary log file/position on all slaves is mysql-bin.000005:342
Tue Apr 30 07:32:15 2024 - [info] Latest slaves (Slaves that received relay log files to the latest):
Tue Apr 30 07:32:15 2024 - [info]   192.168.1.102(192.168.1.102:3306)  Version=10.5.24-MariaDB-log (oldest major version between slaves) log-bin:enabled
Tue Apr 30 07:32:15 2024 - [info]     Replicating from 192.168.1.101(192.168.1.101:3306)
Tue Apr 30 07:32:15 2024 - [info]     Primary candidate for the new Master (candidate_master is set)
Tue Apr 30 07:32:15 2024 - [info] The oldest binary log file/position on all slaves is mysql-bin.000005:342
Tue Apr 30 07:32:15 2024 - [info] Oldest slaves:
Tue Apr 30 07:32:15 2024 - [info]   192.168.1.102(192.168.1.102:3306)  Version=10.5.24-MariaDB-log (oldest major version between slaves) log-bin:enabled
Tue Apr 30 07:32:15 2024 - [info]     Replicating from 192.168.1.101(192.168.1.101:3306)
Tue Apr 30 07:32:15 2024 - [info]     Primary candidate for the new Master (candidate_master is set)
Tue Apr 30 07:32:15 2024 - [info]
Tue Apr 30 07:32:15 2024 - [info] * Phase 3.2: Saving Dead Master's Binlog Phase..
Tue Apr 30 07:32:15 2024 - [info]
Tue Apr 30 07:32:15 2024 - [info] Fetching dead master's binary logs..
Tue Apr 30 07:32:15 2024 - [info] Executing command on the dead master 192.168.1.101(192.168.1.101:3306): save_binary_logs --command=save --start_file=mysql-bin.000005  --start_pos=342 --binlog_dir=/var/lib/mysql --output_file=/var/log/mha/saved_master_binlog_from_192.168.1.101_3306_20240430073214.binlog --handle_raw_binlog=1 --disable_log_bin=0 --manager_version=0.57
  Creating /var/log/mha if not exists..    ok.
 Concat binary/relay logs from mysql-bin.000005 pos 342 to mysql-bin.000005 EOF into /var/log/mha/saved_master_binlog_from_192.168.1.101_3306_20240430073214.binlog ..
 Binlog Checksum enabled
  Dumping binlog format description event, from position 0 to 256.. ok.
  Dumping effective binlog data from /var/lib/mysql/mysql-bin.000005 position 342 to tail(365).. ok.
 Binlog Checksum enabled
 Concat succeeded.
Tue Apr 30 07:32:16 2024 - [info] scp from root@192.168.1.101:/var/log/mha/saved_master_binlog_from_192.168.1.101_3306_20240430073214.binlog to local:/var/log/mha/saved_master_binlog_from_192.168.1.101_3306_20240430073214.binlog succeeded.
Tue Apr 30 07:32:16 2024 - [info] HealthCheck: SSH to 192.168.1.102 is reachable.
Tue Apr 30 07:32:16 2024 - [info]
Tue Apr 30 07:32:16 2024 - [info] * Phase 3.3: Determining New Master Phase..
Tue Apr 30 07:32:16 2024 - [info]
Tue Apr 30 07:32:16 2024 - [info] Finding the latest slave that has all relay logs for recovering other slaves..
Tue Apr 30 07:32:16 2024 - [info] All slaves received relay logs to the same position. No need to resync each other.
Tue Apr 30 07:32:16 2024 - [info] Searching new master from slaves..
Tue Apr 30 07:32:16 2024 - [info]  Candidate masters from the configuration file:
Tue Apr 30 07:32:16 2024 - [info]   192.168.1.102(192.168.1.102:3306)  Version=10.5.24-MariaDB-log (oldest major version between slaves) log-bin:enabled
Tue Apr 30 07:32:16 2024 - [info]     Replicating from 192.168.1.101(192.168.1.101:3306)
Tue Apr 30 07:32:16 2024 - [info]     Primary candidate for the new Master (candidate_master is set)
Tue Apr 30 07:32:16 2024 - [info]  Non-candidate masters:
Tue Apr 30 07:32:16 2024 - [info]  Searching from candidate_master slaves which have received the latest relay log events..
Tue Apr 30 07:32:16 2024 - [info] New master is 192.168.1.102(192.168.1.102:3306)
Tue Apr 30 07:32:16 2024 - [info] Starting master failover..
Tue Apr 30 07:32:16 2024 - [info]
From:
192.168.1.101(192.168.1.101:3306) (current master)
 +--192.168.1.102(192.168.1.102:3306)

To:
192.168.1.102(192.168.1.102:3306) (new master)
Tue Apr 30 07:32:16 2024 - [info]
Tue Apr 30 07:32:16 2024 - [info] * Phase 3.3: New Master Diff Log Generation Phase..
Tue Apr 30 07:32:16 2024 - [info]
Tue Apr 30 07:32:16 2024 - [info]  This server has all relay logs. No need to generate diff files from the latest slave.
Tue Apr 30 07:32:16 2024 - [info] Sending binlog..
Tue Apr 30 07:32:16 2024 - [info] scp from local:/var/log/mha/saved_master_binlog_from_192.168.1.101_3306_20240430073214.binlog to root@192.168.1.102:/var/log/mha/saved_master_binlog_from_192.168.1.101_3306_20240430073214.binlog succeeded.
Tue Apr 30 07:32:16 2024 - [info]
Tue Apr 30 07:32:16 2024 - [info] * Phase 3.4: Master Log Apply Phase..
Tue Apr 30 07:32:16 2024 - [info]
Tue Apr 30 07:32:16 2024 - [info] *NOTICE: If any error happens from this phase, manual recovery is needed.
Tue Apr 30 07:32:16 2024 - [info] Starting recovery on 192.168.1.102(192.168.1.102:3306)..
Tue Apr 30 07:32:16 2024 - [info]  Generating diffs succeeded.
Tue Apr 30 07:32:16 2024 - [info] Waiting until all relay logs are applied.
Tue Apr 30 07:32:16 2024 - [info]  done.
Tue Apr 30 07:32:16 2024 - [info] Getting slave status..
Tue Apr 30 07:32:16 2024 - [info] This slave(192.168.1.102)'s Exec_Master_Log_Pos equals to Read_Master_Log_Pos(mysql-bin.000005:342). No need to recover from Exec_Master_Log_Pos.
Tue Apr 30 07:32:16 2024 - [info] Connecting to the target slave host 192.168.1.102, running recover script..
Tue Apr 30 07:32:16 2024 - [info] Executing command: apply_diff_relay_logs --command=apply --slave_user='mha' --slave_host=192.168.1.102 --slave_ip=192.168.1.102  --slave_port=3306 --apply_files=/var/log/mha/saved_master_binlog_from_192.168.1.101_3306_20240430073214.binlog --workdir=/var/log/mha --target_version=10.5.24-MariaDB-log --timestamp=20240430073214 --handle_raw_binlog=1 --disable_log_bin=0 --manager_version=0.57 --slave_pass=xxx
Tue Apr 30 07:32:17 2024 - [info]
MySQL client version is 10.5.24. Using --binary-mode.
Applying differential binary/relay log files /var/log/mha/saved_master_binlog_from_192.168.1.101_3306_20240430073214.binlog on 192.168.1.102:3306. This may take long time...
Applying log files succeeded.
Tue Apr 30 07:32:17 2024 - [info]  All relay logs were successfully applied.
Tue Apr 30 07:32:17 2024 - [info] Getting new master's binlog name and position..
Tue Apr 30 07:32:17 2024 - [info]  mysql-bin.000003:342
Tue Apr 30 07:32:17 2024 - [info]  All other slaves should start replication from here. Statement should be: CHANGE MASTER TO MASTER_HOST='192.168.1.102', MASTER_PORT=3306, MASTER_LOG_FILE='mysql-bin.000003', MASTER_LOG_POS=342, MASTER_USER='repl_user', MASTER_PASSWORD='xxx';
Tue Apr 30 07:32:17 2024 - [info] Executing master IP activate script:
Tue Apr 30 07:32:17 2024 - [info]   /etc/mha/scripts/master_ip_failover --command=start --ssh_user=root --orig_master_host=192.168.1.101 --orig_master_ip=192.168.1.101 --orig_master_port=3306 --new_master_host=192.168.1.102 --new_master_ip=192.168.1.102 --new_master_port=3306 --new_master_user='mha'   --new_master_password=xxx
Set read_only=0 on the new master.
Updating network interface [nic0] of instance [db-01]...
.....done.
Updating network interface [nic0] of instance [db-01]...

Updating network interface [nic0] of instance [db-02]...
.............done.
Updating network interface [nic0] of instance [db-02]...
..............done.
Tue Apr 30 07:32:34 2024 - [info]  OK.
Tue Apr 30 07:32:34 2024 - [info] ** Finished master recovery successfully.
Tue Apr 30 07:32:34 2024 - [info] * Phase 3: Master Recovery Phase completed.
Tue Apr 30 07:32:34 2024 - [info]
Tue Apr 30 07:32:34 2024 - [info] * Phase 4: Slaves Recovery Phase..
Tue Apr 30 07:32:34 2024 - [info]
Tue Apr 30 07:32:34 2024 - [info] * Phase 4.1: Starting Parallel Slave Diff Log Generation Phase..
Tue Apr 30 07:32:34 2024 - [info]
Tue Apr 30 07:32:34 2024 - [info] Generating relay diff files from the latest slave succeeded.
Tue Apr 30 07:32:34 2024 - [info]
Tue Apr 30 07:32:34 2024 - [info] * Phase 4.2: Starting Parallel Slave Log Apply Phase..
Tue Apr 30 07:32:34 2024 - [info]
Tue Apr 30 07:32:34 2024 - [info] All new slave servers recovered successfully.
Tue Apr 30 07:32:34 2024 - [info]
Tue Apr 30 07:32:34 2024 - [info] * Phase 5: New master cleanup phase..
Tue Apr 30 07:32:34 2024 - [info]
Tue Apr 30 07:32:34 2024 - [info] Resetting slave info on the new master..
Tue Apr 30 07:32:34 2024 - [info]  192.168.1.102: Resetting slave info succeeded.
Tue Apr 30 07:32:34 2024 - [info] Master failover to 192.168.1.102(192.168.1.102:3306) completed successfully.
Tue Apr 30 07:32:34 2024 - [info]

----- Failover Report -----

masterha-default: MySQL Master failover 192.168.1.101(192.168.1.101:3306) to 192.168.1.102(192.168.1.102:3306) succeeded

Master 192.168.1.101(192.168.1.101:3306) is down!

Check MHA Manager logs at mha:/var/log/mha/MHA.log for details.

Started automated(non-interactive) failover.
Invalidated master IP address on 192.168.1.101(192.168.1.101:3306)
The latest slave 192.168.1.102(192.168.1.102:3306) has all relay logs for recovery.
Selected 192.168.1.102(192.168.1.102:3306) as a new master.
192.168.1.102(192.168.1.102:3306): OK: Applying all logs succeeded.
192.168.1.102(192.168.1.102:3306): OK: Activated master IP address.
Generating relay diff files from the latest slave succeeded.
192.168.1.102(192.168.1.102:3306): Resetting slave info succeeded.
Master failover to 192.168.1.102(192.168.1.102:3306) completed successfully.

^C
[1]+  Done                    nohup masterha_manager --conf=/etc/mha/masterha-default.cnf
```


## 원복조치 테스트 
- 장애 발생한 DB-01이 살아난 경우 Replication 재설정 후 Switch 작업 필요 
- 먼저 DB-02(master) - DB-01(Slave) 형태로 Replication 구성 후 mha_manager를 통해 Switch 작업을 수행 

### Replication 구성 

```sql
--DB-02
MariaDB [(none)]> show master status;
+------------------+----------+--------------+------------------+
| File             | Position | Binlog_Do_DB | Binlog_Ignore_DB |
+------------------+----------+--------------+------------------+
| mysql-bin.000003 |      626 |              |                  |
+------------------+----------+--------------+------------------+
1 row in set (0.000 sec)


--DB-01
MariaDB [(none)]> change master to master_host='192.168.1.102' , master_user='repl_user' , master_password='test123' , master_log_file='mysql-bin.000003' , master_log_pos=626;
Query OK, 0 rows affected (0.123 sec)

MariaDB [(none)]>
MariaDB [(none)]> start slave
    -> ;
Query OK, 0 rows affected (0.002 sec)

MariaDB [(none)]> show slave status \G
*************************** 1. row ***************************
                Slave_IO_State: Waiting for master to send event
                   Master_Host: 192.168.1.102
                   Master_User: repl_user
                   Master_Port: 3306
                 Connect_Retry: 60
               Master_Log_File: mysql-bin.000003
           Read_Master_Log_Pos: 626
                Relay_Log_File: db-01-relay-bin.000002
                 Relay_Log_Pos: 555
         Relay_Master_Log_File: mysql-bin.000003
              Slave_IO_Running: Yes
             Slave_SQL_Running: Yes
               Replicate_Do_DB:
           Replicate_Ignore_DB:
            Replicate_Do_Table:
        Replicate_Ignore_Table:
       Replicate_Wild_Do_Table:
   Replicate_Wild_Ignore_Table:
                    Last_Errno: 0
                    Last_Error:
                  Skip_Counter: 0
           Exec_Master_Log_Pos: 626
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


### Switch 작업 수행 
- MHA Manager 서버에서 다음 작업 수행 
```sh
# 해당 파일을 지워야 Switch 작업 수행 가능 
rm -f /var/log/masterha/masterha-default.failover.complete

$ masterha_master_switch --master_state=alive --conf=/etc/mha/masterha-default.cnf

Tue Apr 30 07:57:11 2024 - [info] MHA::MasterRotate version 0.57.
Tue Apr 30 07:57:11 2024 - [info] Starting online master switch..
Tue Apr 30 07:57:11 2024 - [info]
Tue Apr 30 07:57:11 2024 - [info] * Phase 1: Configuration Check Phase..
Tue Apr 30 07:57:11 2024 - [info]
Tue Apr 30 07:57:11 2024 - [warning] Global configuration file /etc/masterha_default.cnf not found. Skipping.
Tue Apr 30 07:57:11 2024 - [info] Reading application default configuration from /etc/mha/masterha-default.cnf..
Tue Apr 30 07:57:11 2024 - [info] Reading server configuration from /etc/mha/masterha-default.cnf..
Tue Apr 30 07:57:12 2024 - [info] GTID failover mode = 0
Tue Apr 30 07:57:12 2024 - [info] Current Alive Master: 192.168.1.102(192.168.1.102:3306)
Tue Apr 30 07:57:12 2024 - [info] Alive Slaves:
Tue Apr 30 07:57:12 2024 - [info]   192.168.1.101(192.168.1.101:3306)  Version=10.5.24-MariaDB-log (oldest major version between slaves) log-bin:enabled
Tue Apr 30 07:57:12 2024 - [info]     Replicating from 192.168.1.102(192.168.1.102:3306)
Tue Apr 30 07:57:12 2024 - [info]     Primary candidate for the new Master (candidate_master is set)

It is better to execute FLUSH NO_WRITE_TO_BINLOG TABLES on the master before switching. Is it ok to execute on 192.168.1.102(192.168.1.102:3306)? (YES/no): yes
Tue Apr 30 07:57:15 2024 - [info] Executing FLUSH NO_WRITE_TO_BINLOG TABLES. This may take long time..
Tue Apr 30 07:57:15 2024 - [info]  ok.
Tue Apr 30 07:57:15 2024 - [info] Checking MHA is not monitoring or doing failover..
Tue Apr 30 07:57:15 2024 - [info] Checking replication health on 192.168.1.101..
Tue Apr 30 07:57:15 2024 - [info]  ok.
Tue Apr 30 07:57:15 2024 - [info] Searching new master from slaves..
Tue Apr 30 07:57:15 2024 - [info]  Candidate masters from the configuration file:
Tue Apr 30 07:57:15 2024 - [info]   192.168.1.101(192.168.1.101:3306)  Version=10.5.24-MariaDB-log (oldest major version between slaves) log-bin:enabled
Tue Apr 30 07:57:15 2024 - [info]     Replicating from 192.168.1.102(192.168.1.102:3306)
Tue Apr 30 07:57:15 2024 - [info]     Primary candidate for the new Master (candidate_master is set)
Tue Apr 30 07:57:15 2024 - [info]   192.168.1.102(192.168.1.102:3306)  Version=10.5.24-MariaDB-log log-bin:enabled
Tue Apr 30 07:57:15 2024 - [info]  Non-candidate masters:
Tue Apr 30 07:57:15 2024 - [info]  Searching from candidate_master slaves which have received the latest relay log events..
Tue Apr 30 07:57:15 2024 - [info]
From:
192.168.1.102(192.168.1.102:3306) (current master)
 +--192.168.1.101(192.168.1.101:3306)

To:
192.168.1.101(192.168.1.101:3306) (new master)

Starting master switch from 192.168.1.102(192.168.1.102:3306) to 192.168.1.101(192.168.1.101:3306)? (yes/NO): yes
Tue Apr 30 07:57:18 2024 - [info] Checking whether 192.168.1.101(192.168.1.101:3306) is ok for the new master..
Tue Apr 30 07:57:18 2024 - [info]  ok.
Tue Apr 30 07:57:18 2024 - [info] ** Phase 1: Configuration Check Phase completed.
Tue Apr 30 07:57:18 2024 - [info]
Tue Apr 30 07:57:18 2024 - [info] * Phase 2: Rejecting updates Phase..
Tue Apr 30 07:57:18 2024 - [info]
Tue Apr 30 07:57:18 2024 - [info] Executing master ip online change script to disable write on the current master:
Tue Apr 30 07:57:18 2024 - [info]   /etc/mha/scripts/master_ip_online_change --command=stop --orig_master_host=192.168.1.102 --orig_master_ip=192.168.1.102 --orig_master_port=3306 --orig_master_user='mha' --new_master_host=192.168.1.101 --new_master_ip=192.168.1.101 --new_master_port=3306 --new_master_user='mha' --orig_master_ssh_user=root --new_master_ssh_user=root   --orig_master_password=xxx --new_master_password=xxx
Tue Apr 30 07:57:18 2024 450584 Set read_only on the new master.. ok.
Tue Apr 30 07:57:18 2024 452914 Drpping app user on the orig master..
Tue Apr 30 07:57:18 2024 453301 Set read_only=1 on the orig master.. ok.
Tue Apr 30 07:57:18 2024 454276 Killing all application threads..
Tue Apr 30 07:57:18 2024 454297 done.
Tue Apr 30 07:57:18 2024 - [info]  ok.
Tue Apr 30 07:57:18 2024 - [info] Locking all tables on the orig master to reject updates from everybody (including root):
Tue Apr 30 07:57:18 2024 - [info] Executing FLUSH TABLES WITH READ LOCK..
Tue Apr 30 07:57:18 2024 - [info]  ok.
Tue Apr 30 07:57:18 2024 - [info] Orig master binlog:pos is mysql-bin.000003:626.
Tue Apr 30 07:57:18 2024 - [info]  Waiting to execute all relay logs on 192.168.1.101(192.168.1.101:3306)..
Tue Apr 30 07:57:18 2024 - [info]  master_pos_wait(mysql-bin.000003:626) completed on 192.168.1.101(192.168.1.101:3306). Executed 0 events.
Tue Apr 30 07:57:18 2024 - [info]   done.
Tue Apr 30 07:57:18 2024 - [info] Getting new master's binlog name and position..
Tue Apr 30 07:57:18 2024 - [info]  mysql-bin.000006:342
Tue Apr 30 07:57:18 2024 - [info]  All other slaves should start replication from here. Statement should be: CHANGE MASTER TO MASTER_HOST='192.168.1.101', MASTER_PORT=3306, MASTER_LOG_FILE='mysql-bin.000006', MASTER_LOG_POS=342, MASTER_USER='repl_user', MASTER_PASSWORD='xxx';
Tue Apr 30 07:57:18 2024 - [info] Executing master ip online change script to allow write on the new master:
Tue Apr 30 07:57:18 2024 - [info]   /etc/mha/scripts/master_ip_online_change --command=start --orig_master_host=192.168.1.102 --orig_master_ip=192.168.1.102 --orig_master_port=3306 --orig_master_user='mha' --new_master_host=192.168.1.101 --new_master_ip=192.168.1.101 --new_master_port=3306 --new_master_user='mha' --orig_master_ssh_user=root --new_master_ssh_user=root   --orig_master_password=xxx --new_master_password=xxx
Tue Apr 30 07:57:18 2024 565666 Set read_only=0 on the new master.
Updating network interface [nic0] of instance [db-01]...done.
Updating network interface [nic0] of instance [db-02]...done.
Updating network interface [nic0] of instance [db-01]...done.
Updating network interface [nic0] of instance [db-02]...done.
Tue Apr 30 07:57:39 2024 - [info]  ok.
Tue Apr 30 07:57:39 2024 - [info]
Tue Apr 30 07:57:39 2024 - [info] * Switching slaves in parallel..
Tue Apr 30 07:57:39 2024 - [info]
Tue Apr 30 07:57:39 2024 - [info] Unlocking all tables on the orig master:
Tue Apr 30 07:57:39 2024 - [info] Executing UNLOCK TABLES..
Tue Apr 30 07:57:39 2024 - [info]  ok.
Tue Apr 30 07:57:39 2024 - [info] All new slave servers switched successfully.
Tue Apr 30 07:57:39 2024 - [info]
Tue Apr 30 07:57:39 2024 - [info] * Phase 5: New master cleanup phase..
Tue Apr 30 07:57:39 2024 - [info]
Tue Apr 30 07:57:40 2024 - [info]  192.168.1.101: Resetting slave info succeeded.
Tue Apr 30 07:57:40 2024 - [info] Switching master to 192.168.1.101(192.168.1.101:3306) completed successfully.
```
- VIP 변경 스크립트가 동작하면서 GCP Alias IP 변경 
    - DB-01 : 192.168.1.202 -> 192.168.1.201
    - DB-02 : 192.168.1.201 -> 192.168.1.202

### Replication 재구성 
- 기존 Replication 구성은 Switch 작업 시 해제됨
- Replication 재구성 작업은 수동으로 진행 필요 
- Replication 재구성 완료 후 MHA_Manager 재실행


#### Replication 재구성 
- DB-01(Master) - DB-02(Slave)

```sql
--DB-01
MariaDB [(none)]> show master status;
+------------------+----------+--------------+------------------+
| File             | Position | Binlog_Do_DB | Binlog_Ignore_DB |
+------------------+----------+--------------+------------------+
| mysql-bin.000006 |      342 |              |                  |
+------------------+----------+--------------+------------------+
1 row in set (0.000 sec)


--DB-02
MariaDB [(none)]> change master to master_host='192.168.1.101' , master_user='repl_user' , master_password='test123' , master_log_file='mysql-bin.000006' , master_log_pos=342;
Query OK, 0 rows affected (0.112 sec)

MariaDB [(none)]>
MariaDB [(none)]> start slave;
Query OK, 0 rows affected (0.001 sec)

MariaDB [(none)]>
MariaDB [(none)]> show slave status \G
*************************** 1. row ***************************
                Slave_IO_State: Waiting for master to send event
                   Master_Host: 192.168.1.101
                   Master_User: repl_user
                   Master_Port: 3306
                 Connect_Retry: 60
               Master_Log_File: mysql-bin.000006
           Read_Master_Log_Pos: 342
                Relay_Log_File: db-02-relay-bin.000002
                 Relay_Log_Pos: 555
         Relay_Master_Log_File: mysql-bin.000006
              Slave_IO_Running: Yes
             Slave_SQL_Running: Yes

```

#### MHA Manager 재실행
- 다시 대기상태로 변경된것을 확인
```sh
$ nohup masterha_manager --conf=/etc/mha/masterha-default.cnf &

$ tail -f /var/log/mha/MHA.log
Tue Apr 30 08:05:48 2024 - [info] Ping(SELECT) succeeded, waiting until MySQL doesn't respond..
```
