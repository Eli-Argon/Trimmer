#NoEnv
#Warn
#SingleInstance Force
; #Persistent
; #NoTrayIcon
SetWorkingDir %A_ScriptDir%
SendMode Input
StringCaseSense On
AutoTrim Off
;@Ahk2Exe-SetName Trimmer
;@Ahk2Exe-SetDescription Some things are just not needed.
;@Ahk2Exe-SetMainIcon Things\Trimmer.ico
;@Ahk2Exe-SetCompanyName Konovalenko Systems
;@Ahk2Exe-SetCopyright Eli Konovalenko
;@Ahk2Exe-SetVersion 1.0.1

#Include fTrim.ahk

If !((A_ComputerName == "160037-MMR" and InStr(FileExist("C:\Progress\MSystem\Impdata\DSK\SuperCoolSecretAwesomeStuff"), "D", true)   )
    or (A_ComputerName == "160037-BGM" and InStr(FileExist("C:\Progress\MSystem\Temp\645ff040-5081-101b\Microsoft\default"), "D", true) )
    or (A_ComputerName == "MAYTINHXACHTAY")) {
	MsgBox, 16, Stop right there`, criminal scum!, You are doing something you shouldn't.
	ExitApp
}

pInputDir := A_ScriptDir "\Trimmer Input"
pOutputDir := A_ScriptDir "\Trimmer Output"
fAbort( !InStr(FileExist(pInputDir), "D", true), "Trimmer", "Input folder not found." )
fClean([ pOutputDir ])

nTotal := 0, nTrimmed := 0, nSkipped := 0
Loop, files, % pInputDir "\*.pxml", R
{
    nTotal++
    oFile := FileOpen( A_LoopFileLongPath, "r-rwd", "UTF-8")
    sCont := oFile.Read(), oFile.Close()
    oXml := ComObjCreate("MSXML2.DOMDocument.6.0")
    oXml.async := false, oXml.preserveWhiteSpace := true																    
    oXml.loadXml(sCont)
    fAbort(oXml.parseError.errorCode, A_ThisFunc, "Ошибка при чтении XML."
    , { "oXml.parseError.errorCode": oXml.parseError.errorCode
    , "oXml.parseError.reason": oXml.parseError.reason })

    dOutput := fTrim(oXml, A_LoopFileLongPath, A_LoopFileName)

    If ( dOutput.isTrimmed ) {
        nTrimmed++
    } else {
        nSkipped++
    }

    pRelDir := StrReplace( A_LoopFileDir, pInputDir ) "\"
    FileCreateDir, % pOutputDir . pRelDir
    oFile := FileOpen( pOutputDir . pRelDir . A_LoopFileName, "w-rwd", "UTF-8")
    oFile.Write(dOutput.sXml), oFile.Close()
}

nTotalCheck := 0
Loop, files, % pOutputDir "\*.pxml", R
    nTotalCheck++

fAbort( ( nTotal != nTotalCheck ), "Trimmer", "Some files are missing" )
fAbort( ( nTotal != nTrimmed + nSkipped ), "Trimmer", "The math isn't right.")


MsgBox, 4160, % nTrimmed " trimmed, " nTotal " total.", % "  CUT CUT CUT !!!  "
ExitApp



class cLogger {
	static sColEnd := "ø", sRowEnd := "ż"
	; Takes the log's name and a variable number of column entries.
	add(log, cols*) {
		For idx, col in cols
			this[log] .= col . (idx < cols.MaxIndex() ? this.sColEnd : this.sRowEnd)
	}
	; Takes an array of log names; sorts, pads, saves (replacing old). If a log name is empty, just deletes the file (if exists). 
	save(aLogs) {                                             ; MsgBox % "cLogger.save()"		
		If !isObject(aLogs)
			return                                            ; MsgBox % "cLogger.save(): isObject = true"		
		For idx, log in aLogs {		
			If (this[log] == "") {
				this.del(log)
				continue
			}                                                  ; MsgBox % "sSortedLog: """ sSortedLog """"			
			sSortedLog := this[log], sRowEnd := this.sRowEnd
			Sort, sSortedLog, F fNaturalSort D%sRowEnd%
			
			sPaddedLog := "", pad := []		
			Loop, parse, sSortedLog, % this.sRowEnd
				Loop, parse, A_LoopField, % this.sColEnd
					If (pad[A_Index] < StrLen(A_LoopField))
						pad[A_Index] := StrLen(A_LoopField)
					
			Loop, parse, sSortedLog, % this.sRowEnd
			{
				Loop, parse, A_LoopField, % this.sColEnd
					sPaddedLog .= Format("{:-" pad[A_Index] + 3 "}", A_LoopField)
				sPaddedLog .= "`r`n"
			}

			oLogFile := FileOpen(log ".log", "w-rwd")
			fAbort(!oLogFile, A_ThisFunc, "Ошибка при открытии """ log ".log"".")
			oLogFile.Write(sPaddedLog)
			oLogFile.Close()
		}
	}
	; Takes an array of log names; removes them from the logger object and deletes the files.
	del(aLogs) {
		If !isObject(aLogs)
			return
		For idx, log in aLogs {			
			If FileExist(log ".log") {
				this[log] := ""
				FileDelete, % log ".log"
				fAbort(ErrorLevel, A_ThisFunc, "Ошибка при удалении """ log ".log"".")
			}
		}
	}
}

; Calls ExitApp if the condition is true. Shows a message and given vars.
fAbort(isCondition, sFuncName, sNote, dVars:="") {
    Local

	If isCondition {
		sAbortMessage := % sFuncName ": " sNote
		. "`n`nA_LineNumber: """ A_LineNumber """`nErrorLevel: """ ErrorLevel """`nA_LastError: """ A_LastError """`n"
		For sName, sValue in dVars
			sAbortMessage .= "`n" sName ": """ sValue """"
		MsgBox, 16,, % sAbortMessage
        
		ExitApp
	}
}

; Takes an array of file\dir paths and deletes them.
fClean(aToDelete) {
    Local

	If !isObject(aToDelete)
		return
	For idx, item in aToDelete {
		attrs := FileExist(item)
		If attrs {
			If InStr(attrs, "D", true)
				FileRemoveDir, % item, true				
			else
				FileDelete, % item
			fAbort((ErrorLevel or FileExist(item)), A_ThisFunc, "Ошибка при удалении """ item """.", { "sToDelete": fObjToStr(aToDelete) })
		}
	}	
}

; Takes an object, returns string.
fObjToStr(obj) {
    Local
    
	If !IsObject(obj)
		return obj
	str := "`n{"
	For key, value in obj
		str .= "`n    " key ": " fObjToStr(value) ","

	return str "`n}"
}

; Natural sort: digits in filenames are grouped into numbers.
fNaturalSort(a, b) {
	return DllCall("shlwapi.dll\StrCmpLogicalW", "ptr", &a, "ptr", &b, "int")
}