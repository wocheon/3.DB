/* ORACLE */
SELECT 
/*+ no_merge(v) ordered */
	decode(v.hold_sid, null , ' ' , '(' || v.inst_id || ') ' || v.hold_sid)    "HOLD SID"
	,decode(v.wait_sid, null, ' ' , '^' , ' ☆', '(' || v.inst_id || ')' || v.wait_sid )   "Wait SID"
	,v. gb  "HW type"
	,v.inst_id "Instance"
	,sw.seconds_in_wait    "Wait Time"
	,v.type    "Lock Type"
	,decode ( v.lmode ,0, 'None', 1, 'Null',2, 'Row Sh',3, 'Row Ex',4, 'Share' ,5, 'Sh R X',6, 'Ex',to_char( v.lmode) ) LOCK_MODE
	,decode ( v.request ,0, 'None',1, 'Null',2, 'Row Sh',3, 'Row Ex',4, 'Share',5, 'Sh R X',6,' Ex',to_char( v.request) ) request
	,(select object_name || ' (' || substr(object_type ,1, 1) || ') ' from dba_objects do where do.object_id = s.row_wait_obj#) locked_obj
	,substr(s.username, 1,8)  username
	,to_char(s.sid) || ',' || to_char(s.serial#) "(SID,SERIAL#)"
	,substr(status, 1,1) status
	,substr(s.sql_trace,1,2) || '/' || substr(s.sql_trace_waits ,1, 1) || '/' || substr(s.sql_trace_binds,1,1)  as SQL_TRACE1
	--,trunc(p.pga_alloc_mem/1024/1024) as pga1
	,decode(substr(s.action,1,4) , 'FRM:', s.module || ' (Form) ', 'Onli', s.module || ' (Form)', 'Conc', s.module || ' (Conc) ', s.module ) program
	,substr(decode(sign(lengthb(s.program) -13), 1, substr(s.program,1,13) || '..' , s.program) ,1,4) as module1
	--,decode(s.blocking_session, null , ' ' , substr(s.blocking_session_status, 1,3) || '(' || s.blocking_instance || ')' || (s.blocking_sesion -1 )  as blocking1
	,s.seconds_in_wait as seconds_in_wait1
	,substr(s.event,1,25) as wait_event1
	,last_call_et as lce1
	,trim((select substr(sql_text,1,20) from gv$sql sq where sq.inst_id = s.inst_id and sq.sql_id = s.sql_id and rownum = 1 )) as sql_text1
	, s.machine as machine1
	,s.osuser as osuser1
	,s.terminal as user_info1
	,to_char(logon_time , 'yyyymmdd HH24:MI:SS') as logon1
	--,s.process as cpid1
	,p.spid as spid1
	,'kill -9 '|| p.spid as kill1
	,'alter system kill session ' || '''' || s.sid || ',' || s.serial# || '''' || ' ; ' as kill2
from
	(select rownum, inst_id, decode(request, 0 , to_char(sid)) hold_sid, 
	decode(request,0,'^',to_char(sid)) wait_sid ,sid,
	decode(request,0,'holding', 'waiting') gb,
	id1,id2,lmode,request, type
	from gv$lock
	where (id1,id2,type ) in (select id1,id2,type from gv$lock where lmode = 0 )) v,
	gv$session s,
	gv$session_wait sw,
	gv$process p
where 
	v.sid = s.sid
	and v.inst_id = s.inst_id
	and s.sid = sw.sid
	and s.inst_id = sw.inst_id
	and s.paddr = p.addr
	and s.inst_id = p.inst_id
order by v.id1, v.request, sw.seconds_in_wait desc;

/* TIBERO */
select 
case when S.SID = W.WAIT_SID then 'WAIT(' || HOLD_SID ||')'  else ' ' end "HOLD"
,S.STATE
,'ALTER SYSTEM KILL SESSION ''' || S.SID || ',' || S.SERIAL# || ''';' "KILL_SESSION"
,S.*, W.*
FROM GV$session S, GV$WAITER_SESSION W
where S.SID =W.WAIT_SID or S.SID = W.HOLD_SID;
