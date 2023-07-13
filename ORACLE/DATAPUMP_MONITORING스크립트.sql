set serveroutput on;
/* DMP 파일을 사용한 EXPDP, IMPDP 의 JOB 진행상황을 확인가능.
	(해당 모니터링 스크립트로는 DB_LINK를 통한 JOB의 파악이 어려움) */	
declare 
	ind number;                                                                                    
	HI NUMBER;
	PRECENT_DONE NUMBER;
	JOB_STATUS VARCHAR2(30);
	JS KU$_JOBSTATUS;
	WS KU$WORKERSTATUSLIST;
	STS KU$STATUS;
	OWNER dba_datapump_jobs.OWNER_NAME%TYPE;
	JOB_NAME dba_datapump_jobs.JOB_NAME%TYPE;
	reps NUMBER;
	
BEGIN
	/*==================================================*/
		OWNER := 'OWN';	
		JOB_NAME := 'SYS_IMPORT_TABLE_02';
	/*==================================================*/
	
		DBMS_OUTPUT.PUT_LINE('OWNER : ' || OWNER );
		DBMS_OUTPUT.PUT_LINE('JOB_NAME : ' || JOB_NAME );
		
		H1 := DBMS_DATAPUMP.ATTACH(job_name, OWNER);
		DBMS_DATAPUMP.GET_STATUS(H1,
					DBMS_DATAPUMP.KU$_STATUS_JOB_ERROR + 
					DBMS_DATAPUMP.KU$_STATUS_JOB_STATUS + 
					DBMS_DATAPUMP.KU$_STATUS_JOB_WIP, 0 , STATUYS , STS);
		JS := STS.JOB_STATUS;
		WS := JS.WORKER_STATUS_LIST;
			DBMS_OUTPUT.PUT_LINE('*** JOB PERCENT DONE : ' || TO_CHAR(JS.PERCENT_DONE) || '%' );
			
			DBMS_OUTPUT.PUT_LINE ('OPERATION : ' || JS.OPERATION );
			DBMS_OUTPUT.PUT_LINE ('MODE : ' || JS.JOB_MODE );
			DBMS_OUTPUT.PUT_LINE ('PARALLEL : ' || JS.DEGREE);
			DBMS_OUTPUT.PUT_LINE ('RESTARTS : ' || JS.RESTART_COUNT || CHR(10));
			
		IND := WS.FIRST;
		
		REPS :=1 ;
			WHILE IND IS NOT NULL LOOP
			IF WS(IND).STATE = 'EXECUTING' THEN 
				DBMS_OUTPUT.PUT_LINE (
									 '============ WORKER NUMBER ' || ws(ind).worker_number 
									 || 'STATUS ============' || chr(10) 
									 || 'State : ' || ws(ind).state || chr(10) 
									 || 'Schema : ' || ws(ind).schema || chr(10) 
									 || 'Objet_name : ' || ws(ind).name || chr(10) 
									 || 'Object_type : ' || ws(ind).object_type || chr(10)
									 || 'DEGREE : ' || ws(ind).degree || chr(10 
									 || 'JOB PRECENT DONE : ' || ws(ind).percent_done || '%' || chr(10)
									 || 'COMPLETED_ROWS : ' || 									 
									 TO_CHAR(ws(ind).COMPLETE_ROWS, 'FM999,999,999,999') || CHR(10) );
			END IF;
			IND := WS.NEXT(IND);
			REPS := reps + 1;
		END LOOP;
	DBMS_DATAPUMP.DETACH(H1);
END;