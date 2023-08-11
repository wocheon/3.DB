Select  /*+ ORDERED */  
    TOT.TABLESPACE_NAME AS T_NAME
        ,se.inst_id
        ,se.username
        ,se.sid, se.serial#
        ,'alter system kill session '''||se.sid||','||se.SERIAL#||''' immediate ;' as "Kill(SQL)"
        ,sp.spid
        ,'kill -9 '||sp.spid as "Kill(OS)"
        ,segtype
        ,NVL(se.sql_id,se.prev_sql_id) AS SQL_INFO_SESS
        ,NVL(SU.SQL_ID,se.prev_sql_id) AS SQL_INFO_SORT
        ,se.status
        ,se.event
        ,se.wait_time AS WAIT_T
        ,se.seconds_in_wait AS WAIT_T_S
        ,se.module
        ,se.action
        ,se.MACHINE
        ,sum(su.extents)
        ,sum(su.blocks * to_number(rtrim(8192)))/1024/1024 as Space     
        ,SUM(TOT.MB) AS "TEMP_TOT(MB)"
        ,SUM(sum(su.blocks * to_number(rtrim(8192)))/1024/1024) OVER() AS UTIL_TEMP
        ,ROUND(((sum(su.blocks * to_number(rtrim(8192)))/1024/1024)/(SUM(TOT.MB))*100),1) AS "RATIO(%)"
        ,sum(lob.CACHE_LOBS) as cache_lobs
        ,sum(lob.NOCACHE_LOBS) as nocache_lobs
from     gv$sort_usage   su
        ,( SELECT /*+ NO_MERGE */ TABLESPACE_NAME, SUM(MAXBYTES/1024/1024) MB
           FROM   DBA_TEMP_FILES
           GROUP BY TABLESPACE_NAME ) TOT
        ,gv$session      se
        ,gv$process      sp
        ,gv$temporary_lobs lob
where    SU.TABLESPACE = TOT.TABLESPACE_NAME
and      su.session_addr = se.saddr
and      su.session_num  = se.serial#
and      su.inst_id = se.inst_id
and      se.type ='USER'
and      se.inst_id = sp.inst_id
and      se.paddr = sp.addr
and      se.sid= lob.sid
and      se.inst_id= lob.inst_id
group by TOT.TABLESPACE_NAME, se.inst_id, se.username, se.sid, se.SERIAL#, sp.spid, segtype, su.extents
       , NVL(se.sql_id,se.prev_sql_id), NVL(SU.SQL_ID,se.prev_sql_id)
       , se.status, se.event, se.wait_time, se.seconds_in_wait, se.module, se.action, se.MACHINE, tablespace, segtype
-- having    sum(su.blocks * to_number(rtrim(8192)))/1024/1024 > 10
order by SPACE desc, TABLESPACE, se.username, se.sid ;


/* TEMP 사용 쿼리 확인 */

select a.username, a.sid, a.serial#, b.blocks, a.program, a.module, a.action, a.machine, a.status, a.event, d.sql_Text ,
      b.blocks*8192/1024/1024 mb
 from v$session a,
      v$sort_usage b,
      v$process c,
      v$sqlarea d
where  a.saddr = b.session_addr
and a.paddr = c.addr
and a.sql_hash_value= d.hash_value
and b.tablespace like 'TEMP%'
--and a.username ='MIG_ADM'
ORDER BY A.MACHINE, SQL_TEXT
