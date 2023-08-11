#!/bin/sh
ORACLE_BASE=/ora19/app/oracle
HOSTNAME=oracle.myguest.virtualbox.org
ORACLE_SID=oracle19
ORACLE_UNQNAME=oracle19
ORACLE_HOSTNAME=oracle
ORACLE_HOME=/ora19/app/oracle/product/19.0.0/db_home_1
PATH=/ora19/app/oracle/product/19.0.0/db_home_1/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/root/bin



echo "#################################"
echo "###        DB_STATUS          ###"
echo "#################################"
ps -ef | grep pmon | grep -v grep


echo ""
echo "#################################"
echo "###       listner_STATUS      ###"
echo "#################################"
ps -ef | egrep 'tns|listner' | grep -v grep | grep -v '\['

echo ""
echo "#################################"
echo "###       Memory_STATUS       ###"
echo "#################################"
free -h

echo ""
echo "#################################"
echo "###    File_System STATUS     ###"
echo "#################################"
df -h

echo ""
echo "#################################"
echo "###    	ORACLE DBMS LOG     ###"
echo "#################################"
tail -1000 /ora19/app/oracle/diag/rdbms/oracle19/oracle19/trace/alert_oracle19.log | egrep -e 'ORA\-|error'


echo ""
echo "#################################"
echo "###   ArchaiveLOG Mode Check  ###"
echo "#################################"
su - oracle -c '
sqlplus -S OWN/Test1234 << EOF
set lines 200;
select NAME, LOG_MODE from v\$database;
EXIT
EOF'

echo ""
echo "#################################"
echo "###   TABLESPACE USAGE CHECK  ###"
echo "#################################"
su - oracle -c '
sqlplus -S OWN/Test1234 << EOF
set lines 200;
SELECT 
	A.TABLESPACE_NAME,
	A.TOTAL,
	NVL(ROUND((A.TOTAL - B.FREE), 2),A.TOTAL) "USED_MB",
	NVL(ROUND(B.FREE,2),0) "FREE_MB",
	NVL(ROUND((A.TOTAL - B.FREE) / A.TOTAL * 100 ,2) , 100) "USE_RATIO%"
FROM 
	(SELECT TABLESPACE_NAME, 
			SUM(BYTES) /1024/1024 "TOTAL" 
		FROM DBA_DATA_FILES  
		GROUP BY TABLESPACE_NAME ) A, 
	(SELECT TABLESPACE_NAME,
			SUM(BYTES) /1024/1024 "FREE" 
		FROM DBA_FREE_SPACE 
		GROUP BY TABLESPACE_NAME ) B 
WHERE A.TABLESPACE_NAME = B.TABLESPACE_NAME(+) 	
    --and NVL(ROUND((A.TOTAL - B.FREE) / A.TOTAL * 100 ,2) , 100) > 50
ORDER BY TABLESPACE_NAME;
EXIT
EOF'


echo ""
echo "#################################"
echo "###     LOCKED USER LIST	    ###"
echo "#################################"
su - oracle -c "
sqlplus -S OWN/Test1234 << EOF
set lines 200;
col USERNAME FORMAT A15;
col ACCOUNT_STATUS FORMAT A10;
select USERNAME,ACCOUNT_STATUS, LOCK_DATE  
from DBA_USERS
where ACCOUNT_STATUS = 'LOCKED'
and USERNAME NOT LIKE '%SYS%'
and AUTHENTICATION_TYPE <> 'NONE';
EXIT 
EOF"


echo ""
echo "#################################"
echo "###   INVALID OBJECT CHECK  	###"
echo "#################################"
su - oracle -c "
sqlplus -S OWN/Test1234 << EOF
set lines 200;
col OWNER format a20;
col OBJECT_NAME format a30;
col OBJECT_TYPE format a15;
select OWNER, OBJECT_NAME, OBJECT_TYPE ,STATUS ,last_DDL_TIME
from dba_objects where status <> 'VALID';
EXIT
EOF"



echo ""
echo "#################################"
echo "### INDEX LOGGING DEGREE CHECK###"
echo "#################################"
su - oracle -c "
sqlplus -S OWN/Test1234 << EOF
set lines 200;
SELECT OWNER, INDEX_NAME ,DEGREE, LOGGING FROM DBA_INDEXES
WHERE OWNER IN ('OWN', 'TDATA')
AND (DEGREE >1 OR LOGGING <> 'YES');
EXIT
EOF"


echo ""
echo "#################################"
echo "###	INDEX INVAILD CHECK		###"
echo "#################################"
su - oracle -c "
sqlplus -S OWN/Test1234 << EOF
set lines 200;
SELECT OWNER, INDEX_NAME , STATUS FROM DBA_INDEXES
WHERE OWNER IN ('OWN', 'TDATA')
AND STATUS <> 'VALID';
EXIT
EOF"



echo ""
echo "####################################"
echo "###TABLE NOLOGGING PARALLEL CHECK###"
echo "####################################"
su - oracle -c "
sqlplus -S OWN/Test1234 << EOF
set lines 200;
SELECT  OWNER, TABLE_NAME ,DEGREE, LOGGING  FROM DBA_TABLES 
WHERE OWNER IN ('OWN', 'TDATA')
AND DEGREE >1 
UNION ALL
SELECT  OWNER, TABLE_NAME ,DEGREE, LOGGING FROM DBA_TABLES 
WHERE OWNER IN ('OWN', 'TDATA')
AND LOGGING <> 'YES';
EXIT
EOF"


echo ""
echo "####################################"
echo "###SEQUENCE LAST_NUMBER OVER 70% ###"
echo "####################################"
su - oracle -c "
sqlplus -S OWN/Test1234 << EOF
set lines 200;
SELECT SEQUENCE_OWNER, SEQUENCE_NAME, LAST_NUMBER, MAX_VALUE, CYCLE_FLAG
FROM DBA_SEQUENCES 
WHERE SEQUENCE_OWNER <> 'PUBLIC' 
    AND LAST_NUMBER > MAX_VALUE *0.7;
EXIT
EOF"


echo ""
echo "####################################"
echo "###  		LOCK MONITOR 		   ###"
echo "####################################"
su - oracle -c '
sqlplus -S OWN/Test1234 << EOF
set lines 200;
@"/work/db_check/lock_mon.sql"
EXIT
EOF'
	