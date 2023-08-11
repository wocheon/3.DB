# PLSQL 작성시 참고사항

## 개별 Exception 처리
* raise 를 이용하여 원하는상황별로 exception 처리가 가능함.
```sql
set serveroutput on;

declare 
    --id varchar2(10) := 'id';
    id nubmer := 2; -- 해당변수의 기본값을 설정
    over_count EXCEPTION;  
begin
    if id >3 then 
        raise over_count; -- id 값이 3이상이면 over_count 예외처리 발동
    end if;
    
    DBMS_OUTPUT.put_line(id);
    
exception 
    when over_count then 
        DBMS_OUTPUT.put_line('ERROR : COUNT OVER');
    when others then -- 기타 오류 발생시 에러메세지 출력
      DBMS_OUTPUT.PUT_LINE('오류가 발생했습니다');
      DBMS_OUTPUT.PUT_LINE('SQL ERROR CODE: ' || SQLCODE);
      DBMS_OUTPUT.PUT_LINE('SQL ERROR MESSAGE: ' || SQLERRM);  -- 매개변수 없는 SQLERRM
      DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
end;
```


## serveroutput 출력시 buffer 사이즈 최대로 변경
```sql
dbms_output.enable (buffer_size = null)
```


## deterministic, enable_parallel

* deterministic: subquery 기능을 제공하는 옵션
* enable_parallel : 해당옵션이 없으면 parallel로 수행되지않음
```sql
create or replace function aa ( id in varchar2) return varchar2
deterministic  
enable_parallel
is 
name varchar2
begin
end;
```

## SQL 조회 조건 별 DML 구문 작성법 

1. SQL의 where조건이 변하는경우
    
    - cursor에 입력하여 사용

>ex)
```sql
declare 
I nubmer;
res varchar2(10);
begin
    FOR I IN 1..9
    LOOP
    
    select name into res 
    from employee 
    where id = i; --결과를 변수 res에 입력

    dbms_output.put_line( res );
    END LOOP;
end;
```

2. 테이블명이 변해야 하는 경우
>ex)
```sql
select id from tbl_1 

-----
ID
-----
a1
-----
```


```sql
select id from tbl_2
-----
ID
-----
a2
-----
```

```sql
set serveroutput on;

declare 
res varchar2(10);
table_nm varchar2(10);

cursor select_sql is 
select 'tbl' || '_' || level from dual connect by level <3;

begin
   
    open select_sql;
    LOOP
    fetch select_sql into table_nm;
    exit when select_sql%NOTFOUND;
    execute immediate 'select id from ' || table_nm into res; -- 결과는 1개 행만 나와야함    
    END LOOP;
    close select_sql;
end;
```

`OR`

```sql
declare 
res varchar2(10);
select_sql varchar2(500);
table_nm varchar2(10);

type cur_type is REF CURSOR; -- 커서 타입 선언
test_cur cur_type; --커서 변수 선언

begin
    select_sql := 'select ''tbl''|| ''_'' || level from dual connect by level <3';
    
    
    open test_cur FOR  select_sql;
    LOOP
    fetch test_cur into table_nm;
    exit when test_cur%NOTFOUND;
        execute immediate 'select id from ' || table_nm into res;
        dbms_output.put_line( res );
    END LOOP;
    close test_cur;
end;
```