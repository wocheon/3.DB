/* 윈도우 CMD 예약작업 */
1. 예약작업 생성 
SCHTASKS /create /tn "test" /tr "test.bat" /sc weekly /D MON,TUE,WEN,THU,FRI /ST 18:00

2. 예약작업 확인 
SCHTASKS /tn "test"

3. 예약작업 삭제 
SCHTASKS /delete /TN "test"



/* 엑셀 사용자 정의함수 - 추가기능 연동 */ 
	신규문서 생성 후 alt + f11 로 VBA 창 열기 
	모듈 추가하여 사용자 정의함수 생성 
	ex) 
		Public function TABLE_LIST_IN (TABLE_NAME AS STRING)
			TABLE_LIST_IN = "," & TABLE_NAME & "" 
		END FUNCTION
		
	xlam 파일 형식 지정하면 자동으로 위치가 설정되며 해당위치에 파일 저장.
	
	개발도구 > excel 추가기능에서 찾아보기 선택하여 저장한 파일을 선택
	체크박스 목록에 추가되면 체크 후, 정상동작 확인.
	
	