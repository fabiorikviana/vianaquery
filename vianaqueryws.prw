#Include "Totvs.ch"
#Include "restful.ch"
#Include "Apwebex.ch"
#Include "json.ch"

// Desenvolvedor Fábio Viana (fabiorikviana@gmail.com)
// GIT DO PROJETO VIANA QUERY:
// https://github.com/fabiorikviana/vianaquery
//
// ============================================================================
// VIANA QUERY WS
// ----------------------------------------------------------------------------
// Web Service REST mínimo para uso com a extensão VSCode "VIANA QUERY".
//
// Rotas:
//   GET  /vianaquery/ping
//   POST /vianaquery/query
//
// Body POST:
// {
//   "sql": "SELECT A1_COD,A1_NOME FROM SA1010 WHERE D_E_L_E_T_ = ' '",
//   "limit": 100,
//   "dbType": "ORACLE"
// }
//
// dbType suportados:
//   ORACLE     -> aplica ROWNUM
//   SQLSERVER  -> aplica TOP
//   POSTGRESQL -> aplica LIMIT
//
// Observações:
//   - O usuário/senha são os mesmos usados no Basic Auth do REST Protheus.
//   - Este WS NÃO implementa login próprio.
//   - Somente SELECT é permitido.
//   - Comandos de escrita/DDL são bloqueados por segurança básica.
// ============================================================================

WSRESTFUL VIANAQUERY DESCRIPTION "API VIANA QUERY"

	WSMETHOD GET DESCRIPTION "Ping" ;
		WSSYNTAX "/{rota}"

	WSMETHOD POST DESCRIPTION "Executa consulta SQL" ;
		WSSYNTAX "/{rota}"

END WSRESTFUL


// ============================================================================
// GET /vianaquery/ping
// ============================================================================
WSMETHOD GET WSSERVICE VIANAQUERY

	Local cRota := ""

	::SetContentType("application/json; charset=utf-8")

	If Len(::aURLParms) >= 1
		cRota := Lower(AllTrim(::aURLParms[1]))
	EndIf

	If cRota == "ping"
		::SetResponse('{"success":true,"msg":"VIANA QUERY WS ativo"}')
		Return .T.
	EndIf

	::SetResponse('{"success":false,"msg":"Rota GET invalida"}')

Return .T.


// ============================================================================
// POST /vianaquery/query
// ============================================================================
WSMETHOD POST WSSERVICE VIANAQUERY

	Local cRota   := ""
	Local cBody   := ""
	Local cSql    := ""
	Local cDbType := "ORACLE"
	Local cJson   := ""
	Local nLimit  := 100

	::SetContentType("application/json; charset=utf-8")

	If Len(::aURLParms) >= 1
		cRota := Lower(AllTrim(::aURLParms[1]))
	EndIf

	If cRota <> "query"
		::SetResponse('{"success":false,"msg":"Rota POST invalida"}')
		Return .T.
	EndIf

	cBody   := ::GetContent()
	cSql    := JsonGetString(cBody, "sql")
	nLimit  := JsonGetNumber(cBody, "limit", 100)
	cDbType := Upper(AllTrim(JsonGetString(cBody, "dbType")))

	If Empty(cDbType)
		cDbType := "ORACLE"
	EndIf

	If nLimit <= 0
		nLimit := 100
	EndIf

	If nLimit > 5000
		nLimit := 5000
	EndIf

	If Empty(AllTrim(cSql))
		::SetResponse('{"success":false,"msg":"SQL nao informado"}')
		Return .T.
	EndIf

	If !IsSafeSelectSql(cSql)
		::SetResponse('{"success":false,"msg":"Somente consultas SELECT sao permitidas"}')
		Return .T.
	EndIf

	If !(cDbType $ "ORACLE|SQLSERVER|POSTGRESQL")
		::SetResponse('{"success":false,"msg":"Tipo de banco nao suportado"}')
		Return .T.
	EndIf

	cSql := NormalizeSql(cSql)
	cSql := ApplySqlLimit(cSql, nLimit, cDbType)

	ConOut("=== VIANA QUERY WS ===")
	ConOut("DBTYPE: " + cDbType)
	ConOut("LIMIT : " + CValToChar(nLimit))
	ConOut("SQL   : " + cSql)

	cJson := QueryToJson(cSql, nLimit, cDbType)

	::SetResponse(cJson)

Return .T.


// ============================================================================
// Executa Open Query e retorna JSON
// ============================================================================
Static Function QueryToJson(cSql, nLimit, cDbType)

	Local cJson      := ""
	Local cAlias     := GetNextAlias()
	Local cCampo     := ""
	Local cValor     := ""
	Local nCount     := 0
	Local nField     := 0
	Local nFieldMax  := 0
	Local lPriItem   := .T.
	Local lPriCampo  := .T.
	Local aStruct    := {}
	Local lHasMore   := .F.

	Open Query cSql Alias cAlias

	(cAlias)->(DbGoTop())

	aStruct   := (cAlias)->(DbStruct())
	nFieldMax := Len(aStruct)

	cJson := "{"
	cJson += '"success":true,'
	cJson += '"dbType":"' + EscJson(cDbType) + '",'
	cJson += '"limit":' + AllTrim(CValToChar(nLimit)) + ','

	cJson += '"columns":['

	For nField := 1 To nFieldMax

		cCampo := AllTrim(aStruct[nField][1])

		If !lPriCampo
			cJson += ","
		EndIf

		cJson += "{"
		cJson += '"property":"' + EscJson(cCampo) + '",'
		cJson += '"label":"'    + EscJson(cCampo) + '"'
		cJson += "}"

		lPriCampo := .F.

	Next

	cJson += "],"

	cJson += '"items":['

	While (cAlias)->(!EOF()) .And. nCount < nLimit

		If !lPriItem
			cJson += ","
		EndIf

		cJson += "{"

		lPriCampo := .T.

		For nField := 1 To nFieldMax

			cCampo := AllTrim(aStruct[nField][1])

			If !lPriCampo
				cJson += ","
			EndIf

			cValor := FieldToJsonValue(cAlias, nField)

			cJson += '"' + EscJson(cCampo) + '":"' + EscJson(cValor) + '"'

			lPriCampo := .F.

		Next

		cJson += "}"

		lPriItem := .F.
		nCount++

		(cAlias)->(DbSkip())

	EndDo

	If (cAlias)->(!EOF())
		lHasMore := .T.
	EndIf

	cJson += "],"
	cJson += '"count":' + AllTrim(CValToChar(nCount)) + ','
	cJson += '"hasMore":' + IIf(lHasMore, "true", "false")
	cJson += "}"

	Close Query cAlias

Return cJson


// ============================================================================
// Aplica limite conforme banco
// ============================================================================
Static Function ApplySqlLimit(cSql, nLimit, cDbType)

	Local cRet      := AllTrim(cSql)
	Local cChk      := Upper(" " + cRet + " ")
	Local cLimit    := AllTrim(CValToChar(nLimit))
	Local nOrderPos := 0
	Local cBefore   := ""
	Local cAfter    := ""

	cRet := RemoveTrailingSemicolon(cRet)

	Do Case
	Case cDbType == "SQLSERVER"

		If " TOP " $ cChk
			Return cRet
		EndIf

		If Left(Upper(cRet), 15) == "SELECT DISTINCT"
			cRet := "SELECT DISTINCT TOP " + cLimit + " " + SubStr(cRet, 16)
		Else
			cRet := "SELECT TOP " + cLimit + " " + SubStr(cRet, 7)
		EndIf

	Case cDbType == "POSTGRESQL"

		If " LIMIT " $ cChk
			Return cRet
		EndIf

		cRet += " LIMIT " + cLimit

	Case cDbType == "ORACLE"

		If " ROWNUM " $ cChk
			Return cRet
		EndIf

		nOrderPos := RAt(" ORDER BY ", Upper(cRet))

		If nOrderPos > 0
			cBefore := AllTrim(SubStr(cRet, 1, nOrderPos - 1))
			cAfter  := AllTrim(SubStr(cRet, nOrderPos))

			If " WHERE " $ Upper(" " + cBefore + " ")
				cRet := cBefore + " AND ROWNUM <= " + cLimit + " " + cAfter
			Else
				cRet := cBefore + " WHERE ROWNUM <= " + cLimit + " " + cAfter
			EndIf
		Else
			If " WHERE " $ Upper(" " + cRet + " ")
				cRet += " AND ROWNUM <= " + cLimit
			Else
				cRet += " WHERE ROWNUM <= " + cLimit
			EndIf
		EndIf

	EndCase

Return cRet


// ============================================================================
// Segurança básica
// ============================================================================
Static Function IsSafeSelectSql(cSql)

	Local cChk := Upper(AllTrim(cSql))

	cChk := NormalizeSql(cChk)

	If Empty(cChk)
		Return .F.
	EndIf

	If Left(cChk, 6) <> "SELECT"
		Return .F.
	EndIf

	If ";" $ cChk
		Return .F.
	EndIf

	If " DELETE " $ (" " + cChk + " ") .Or. ;
			" UPDATE " $ (" " + cChk + " ") .Or. ;
			" INSERT " $ (" " + cChk + " ") .Or. ;
			" DROP " $ (" " + cChk + " ") .Or. ;
			" ALTER " $ (" " + cChk + " ") .Or. ;
			" TRUNCATE " $ (" " + cChk + " ") .Or. ;
			" EXEC " $ (" " + cChk + " ") .Or. ;
			" EXECUTE " $ (" " + cChk + " ") .Or. ;
			" MERGE " $ (" " + cChk + " ") .Or. ;
			" CREATE " $ (" " + cChk + " ")
		Return .F.
	EndIf

Return .T.


// ============================================================================
// Normalização
// ============================================================================
Static Function NormalizeSql(cSql)

	cSql := AllTrim(cSql)
	cSql := StrTran(cSql, Chr(13), " ")
	cSql := StrTran(cSql, Chr(10), " ")
	cSql := StrTran(cSql, Chr(9),  " ")

	Do While "  " $ cSql
		cSql := StrTran(cSql, "  ", " ")
	EndDo

Return cSql

Static Function RemoveTrailingSemicolon(cSql)

	cSql := AllTrim(cSql)

	Do While Right(cSql, 1) == ";"
		cSql := AllTrim(SubStr(cSql, 1, Len(cSql) - 1))
	EndDo

Return cSql


// ============================================================================
// JSON helpers simples
// ============================================================================
Static Function JsonGetString(cJson, cProp)

	Local cRet    := ""
	Local cFind   := '"' + Lower(AllTrim(cProp)) + '"'
	Local cLower  := Lower(cJson)
	Local nPos    := 0
	Local nIni    := 0
	Local nFim    := 0
	Local cChar   := ""
	Local lEscape := .F.

	nPos := At(cFind, cLower)

	If nPos <= 0
		Return ""
	EndIf

	nIni := At(":", SubStr(cJson, nPos))

	If nIni <= 0
		Return ""
	EndIf

	nIni := nPos + nIni

	Do While nIni <= Len(cJson) .And. SubStr(cJson, nIni, 1) <> '"'
		nIni++
	EndDo

	If nIni > Len(cJson)
		Return ""
	EndIf

	nIni++
	nFim := nIni

	While nFim <= Len(cJson)

		cChar := SubStr(cJson, nFim, 1)

		If cChar == "\\" .And. !lEscape
			lEscape := .T.
		ElseIf cChar == '"' .And. !lEscape
			Exit
		Else
			lEscape := .F.
		EndIf

		nFim++
	EndDo

	cRet := SubStr(cJson, nIni, nFim - nIni)
	cRet := JsonUnescape(cRet)

Return cRet

Static Function JsonGetNumber(cJson, cProp, nDefault)

	Local nRet    := nDefault
	Local cFind   := '"' + Lower(AllTrim(cProp)) + '"'
	Local cLower  := Lower(cJson)
	Local nPos    := 0
	Local nIni    := 0
	Local nFim    := 0
	Local cChar   := ""
	Local cNum    := ""

	nPos := At(cFind, cLower)

	If nPos <= 0
		Return nDefault
	EndIf

	nIni := At(":", SubStr(cJson, nPos))

	If nIni <= 0
		Return nDefault
	EndIf

	nIni := nPos + nIni

	Do While nIni <= Len(cJson) .And. SubStr(cJson, nIni, 1) $ " :"
		nIni++
	EndDo

	nFim := nIni

	While nFim <= Len(cJson)

		cChar := SubStr(cJson, nFim, 1)

		If !(cChar $ "0123456789")
			Exit
		EndIf

		nFim++
	EndDo

	cNum := SubStr(cJson, nIni, nFim - nIni)

	If !Empty(cNum)
		nRet := Val(cNum)
	EndIf

Return nRet

Static Function JsonUnescape(cTxt)

	cTxt := StrTran(cTxt, '\\"', '"')
	cTxt := StrTran(cTxt, '\\/', '/')
	cTxt := StrTran(cTxt, '\\n', Chr(10))
	cTxt := StrTran(cTxt, '\\r', Chr(13))
	cTxt := StrTran(cTxt, '\\t', Chr(9))
	cTxt := StrTran(cTxt, '\\\\', '\\')

Return cTxt


// ============================================================================
// Conversão campo -> texto JSON
// ============================================================================
Static Function FieldToJsonValue(cAlias, nField)

	Local xValue := (cAlias)->(FieldGet(nField))
	Local cRet   := ""

	Do Case
	Case ValType(xValue) == "C"
		cRet := AllTrim(xValue)

	Case ValType(xValue) == "N"
		cRet := AllTrim(CValToChar(xValue))

	Case ValType(xValue) == "D"
		cRet := IIf(Empty(xValue), "", DToC(xValue))

	Case ValType(xValue) == "L"
		cRet := IIf(xValue, "true", "false")

	Otherwise
		cRet := AllTrim(CValToChar(xValue))
	EndCase

	cRet := EncodeUTF8(cRet, "cp1252")

Return cRet

Static Function EscJson(cTxt)

	cTxt := AllTrim(CValToChar(cTxt))
	cTxt := StrTran(cTxt, "\", "\\")
	cTxt := StrTran(cTxt, '"', '\"')
	cTxt := StrTran(cTxt, Chr(13), "")
	cTxt := StrTran(cTxt, Chr(10), "")
	cTxt := StrTran(cTxt, Chr(9), " ")

Return cTxt
