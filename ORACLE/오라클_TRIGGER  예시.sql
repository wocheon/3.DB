create or REPLACE trigger trig_test
before 
    INSERT ON TBL1
BEGIN
    DBMS_OUTPUT.PUT_LINE('======================');
    DBMS_OUTPUT.PUT_LINE('DATA INSERTED ON TBL1!');
    DBMS_OUTPUT.PUT_LINE('======================');
END;    

    
----------
SELECT * FROM TBL1;
SET SERVEROUTPUT ON;
INSERT INTO TBL1 VALUES ('A','B','C','D');
