create or replace PROCEDURE PROC_TRANS (TABLE_NM IN VARCHAR2)
IS
TARGET_TABLE_NM VARCHAR2(100);
META_TABLE_PNM VARCHAR2(100);
META_COLUMN_PNM VARCHAR2(100);
META_DOMAIN_PNM VARCHAR2(100);
DOMAIN_TRANS_YN VARCHAR2(100);
DOMAIN_TRANS_VALUE VARCHAR2(100);
COLUMN_TRANS_YN VARCHAR2(100);
COLUMN_TRANS_VALUE VARCHAR2(100);

column_list varchar2(5000);
SELECT_SQL  varchar2(5000);

list_row_num number;
REP_NUM  number;
EXISTS_CHCK NUMBER;
RULE_CHCK NUMBER;
SQLCHCK NUMBER;

cursor META_LIST_DOMAIN is
SELECT
A.TABLE_PNM
,A.COLUMN_PNM
,A.DOMAIN_PNM
,B.TRANS_YN AS DOMAIN_TRANS_YN
,B.TRANS_VALUE AS DOMAIN_TRANS_VALUE
,C.TRANS_YN AS COLUMN_TRANS_YN
,C.TRANS_VALUE AS COLUMN_TRANS_VALUE
FROM META_LIST A , DOMAIN_RULE B , COLUMN_RULE C
WHERE 1=1
AND a.DOMAIN_LNM = B.DOMAIN_LNM
AND a.column_pnm = C.COLUMN_PNM(+)
AND TABLE_PNM = TARGET_TABLE_NM;

BEGIN
    TARGET_TABLE_NM := TABLE_NM;    
    execute immediate 'SELECT count(*) FROM META_LIST A , DOMAIN_RULE B WHERE A.DOMAIN_LNM = B.DOMAIN_LNM AND A.TABLE_PNM =  ''' || TARGET_TABLE_NM || ''''  into list_row_num;                
    DBMS_OUTPUT.PUT_LINE('--------------'||TARGET_TABLE_NM||'----------------');        
        
        open META_LIST_DOMAIN;        
        FOR REP_NUM IN 1..list_row_num
        LOOP
            fetch META_LIST_DOMAIN into META_TABLE_PNM, META_COLUMN_PNM, META_DOMAIN_PNM,DOMAIN_TRANS_YN ,DOMAIN_TRANS_VALUE, COLUMN_TRANS_YN, COLUMN_TRANS_VALUE;
            exit when META_LIST_DOMAIN%notfound;
            SQLCHCK := INSTR(COLUMN_TRANS_VALUE, '"');
            DBMS_OUTPUT.PUT_LINE(SQLCHCK);
                       
            IF COLUMN_TRANS_YN = 'Y' THEN
                
                IF SQLCHCK = 0 OR SQLCHCK IS NULL THEN
                    META_COLUMN_PNM := CHR(39)|| COLUMN_TRANS_VALUE || CHR(39)||' AS ' || META_COLUMN_PNM;            
                ELSE                    
                    execute immediate 'SELECT REPLACE(''' || COLUMN_TRANS_VALUE || ''', CHR(34), CHR(39)) FROM DUAL' INTO COLUMN_TRANS_VALUE;    
                    META_COLUMN_PNM :=  COLUMN_TRANS_VALUE || ' AS ' || META_COLUMN_PNM ;
                END IF;                    
                                        
            ELSIF COLUMN_TRANS_YN IS NULL AND  DOMAIN_TRANS_YN = 'Y' THEN
                META_COLUMN_PNM := CHR(39)|| DOMAIN_TRANS_VALUE || CHR(39) || ' AS ' || META_COLUMN_PNM;
            END IF;    
            
            IF REP_NUM = 1 THEN
            column_list := column_list || META_COLUMN_PNM;                
            ELSE
            column_list := column_list || chr(10) || ',' || META_COLUMN_PNM;                
            END IF;                                
        end LOOP;     
        close META_LIST_DOMAIN;
    
    
    SELECT_SQL := 'SELECT ' || CHR(10) || column_list || CHR(10) || 'FROM ' || TARGET_TABLE_NM ;    
    DBMS_OUTPUT.PUT_LINE('---------------result---------------');
    DBMS_OUTPUT.PUT_LINE('*column_cnt : ' || list_row_num );            
    DBMS_OUTPUT.PUT_LINE(SELECT_SQL);
    DBMS_OUTPUT.PUT_LINE('------------------------------');
    
    execute immediate 'SELECT COUNT(*) FROM USER_TABLES WHERE TABLE_NAME = '''|| TARGET_TABLE_NM ||'_TRANS''' INTO EXISTS_CHCK;
    IF EXISTS_CHCK <> 0 THEN
        execute immediate 'DROP table ' || TARGET_TABLE_NM ||'_TRANS';
    END IF;
    
    execute immediate 'create table ' || TARGET_TABLE_NM ||'_TRANS AS ' || SELECT_SQL;
    DBMS_OUTPUT.PUT_LINE ('create table ' || TARGET_TABLE_NM ||'_TRANS AS ' || SELECT_SQL);
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('SQL ERROR MESSAGE: ' || SQLERRM);        
END;
[출처] 오라클 프로시저_참고용|작성자 ciw0707