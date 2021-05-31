fTrim(oPanelXML, pFile, sPanel) {
    Local
    isTrimmed := false
    nSteelNodes := 0, hasFlat := false, hasBent := false, hasExtra := false
    dBarsBent := {}, dBarsFlat := {}

    ; ##############################  vvv  GETTING BAR DATA  vvv  ############################ ;
    For oSteel in oPanelXml.selectNodes("/" ns("PXML_Document","Order","Product","Slab","Steel")) {
        nSteelNodes++
        ;============================ vvv An extra reinforcement node vvv =====================;
        If (oSteel.getAttribute("Type") == "none") {
            fAbort(hasExtra, A_ThisFunc, "Два комплекта усилении̌ в """ sPanel """?", { "pFile": pFile }) 
            hasExtra := true
        } ;============================ ^^^ An extra reinforcement node ^^^ ===================;
        
        If (oSteel.getAttribute("Type") == "mesh") { ;====== vvv A mesh node vvv ==============;
            isBent := false ; True if this particular mesh has bent bars
            aHorizontal := [], aVertical := []

            For oBar in oSteel.selectNodes( ns("Bar") ) { ; Iterate through bars.
                dSingleBar := { elRef: oBar, nLength: 0 }
                
                For _, name in [ "X", "Y", "Z", "RotZ" ] {
                    dSingleBar[name] := oBar.selectSingleNode( ns( name ) ).text
                    dSingleBar[name] := dSingleBar[name] ? dSingleBar[name] : 0
                }
                
                dSingleBar.nDiam := oBar.selectSingleNode( ns("Diameter") ).text
                dSingleBar.nCount := oBar.selectSingleNode( ns("PieceCount") ).text

                For oSegment in oBar.selectNodes( ns("Segment") ) { ; Iterate throught bar segments.
                    oL := oSegment.selectSingleNode( ns("L") )
                    dSingleBar.nLength += oL.text
                    If ( !isBent and ( oSegment.selectSingleNode( ns("BendY") ).text > 0 ) ) {
                        fAbort(hasBent, A_ThisFunc, "Две гнутых сетки в """ sPanel """?", { "pFile": pFile })
                        isBent := true, hasBent := true
                    }
                }
                
                If ( dSingleBar.RotZ == 90 ) {
                    dSingleBar.nLeftX := dSingleBar.x, dSingleBar.nRightX := dSingleBar.x
                    dSingleBar.nBotY := dSingleBar.y
                    dSingleBar.nTopY := dSingleBar.y + dSingleBar.nLength
                    aVertical.Push( dSingleBar )
                } else if ( dSingleBar.RotZ == 0 ) {
                    dSingleBar.nBotY := dSingleBar.y, dSingleBar.nTopY := dSingleBar.y
                    dSingleBar.nLeftX := dSingleBar.x
                    dSingleBar.nRightX := dSingleBar.x + dSingleBar.nLength
                    aHorizontal.Push( dSingleBar )
                }
            }
            ; --------------------------  vvv  Sorting  vvv  --------------------------------- ;
            For _, aList in [ aHorizontal, aVertical ] {
                shouldStop := 1
                sCoordA := ( A_Index == 1 ) ? "y" : "x" ; Horizontals are sorted by «y» first.
                sCoordB := ( A_Index == 1 ) ? "x" : "y" ; Verticals are sorted by «x» first.

                Loop {
                    shouldStop := 1
                    Loop % aList.Length() - 1
                    {            
                        If ( (aList[A_Index][ sCoordA ] > aList[A_Index+1][ sCoordA ])
                            or ( (aList[A_Index][ sCoordA ] == aList[A_Index+1][ sCoordA ])
                                and (aList[A_Index][ sCoordB ] > aList[A_Index+1][ sCoordB ]))) {
                            rv := aList.RemoveAt( A_Index+1 ), aList.InsertAt( A_Index, rv )
                            shouldStop := 0
                            break
                        }
                    }
                } until shouldStop
            }            
            ; --------------------------  ^^^  Sorting  ^^^  --------------------------------- ;

            If ( isBent ) { ; If bent bars have been found in this mesh.
                dBarsBent.aHorizontal := aHorizontal
                dBarsBent.aVertical := aVertical
            } else {
                fAbort(hasFlat, A_ThisFunc, "Две плоских сетки в """ sPanel """?", { "pFile": pFile })
                hasFlat := true
                dBarsFlat.aHorizontal := aHorizontal
                dBarsFlat.aVertical := aVertical
            }
        } ;================================ ^^^ A mesh node ^^^ ===============================;

    } ; ########  ^^^  For loop: looking for Steel nodes in the PXML document  ^^^  ########## ;

    fAbort(nSteelNodes == 0, A_ThisFunc, "Нет сеток в source-файле «" sPanel "»?", { "pFile": pFile }) 
    fAbort(nSteelNodes > 3, A_ThisFunc, "Три сетки в source-файле «" sPanel "»?", { "pFile": pFile }) 
    ; ##############################  ^^^  GETTING BAR DATA  ^^^  ############################ ;


    ; ##############################  vvv  FINDING DOOR-FRAMING BARS vvv  #################### ;
    aDoors := [] ; Shouldn't be more than two.
    For oOutline in oPanelXml.selectNodes("/" ns("PXML_Document", "Order", "Product", "Slab", "Outline")) {
        If ( oOutline.selectSingleNode( ns("Name")).text == "Углубление" ) {
            nDoorSizeX := oOutline.selectSingleNode( ns("MountPartLength")).text
            nDoorSizeY := oOutline.selectSingleNode( ns("MountPartWidth")).text
            If ( ( nDoorSizeX < 700 ) or ( nDoorSizeY < 1800 ) )
                continue
            nDoorX := oOutline.selectSingleNode( ns("X") ).text
            nDoorX := nDoorX ? nDoorX : 0
            nLeftX := nDoorX, nRightX := nDoorX + nDoorSizeX
            nTopY  := nDoorSizeY

            aDoors.Push( { "nLeftX": nLeftX, "nRightX": nRightX, "nTopY": nTopY } )
        }

    }

    ;===============  vvv  Looking for matching CUTOUTs just to make sure.  vvv  ==============;
    aDoorCutouts := [] 
    For oOutline in oPanelXml.selectNodes("/" ns("PXML_Document", "Order", "Product", "Slab", "Outline")) {
        If (oOutline.getAttribute("Type") == "lot") {
            For oShape in oOutline.selectNodes( ns("Shape") ) {
                If ( oShape.selectNodes( ns("SVertex") ) > 4 )
                    continue  ; If more than 4 geometric points it's not a door.
                nLeftX := 0, nRightX := 0, nTopY := 0
                For oSVertex in oShape.selectNodes( ns("SVertex") ) {
                    x := oSVertex.selectSingleNode( ns("X") ).text
                    y := oSVertex.selectSingleNode( ns("Y") ).text
                    nLeftX  := ( !nLeftX or ( x < nLeftX) ) ? x : nLeftX
                    nRightX := ( x > nRightX ) ? x : nRightX
                    nTopY   := !nTopY ? y : nTopY
                }

                aDoorCutouts.Push( { "nLeftX": nLeftX, "nRightX": nRightX, "nTopY": nTopY } )
            }

            break ; We've found the Outline with Type "Lot" and stop looking.
        }
    }

    For _, dDoor in aDoors {
        isFound := false
        For _, dCutout in aDoorCutouts {
            If ( dDoor.nLeftX == dCutout.nLeftX ) and ( dDoor.nRightX == dCutout.nRightX )
                and ( dDoor.nTopY == dCutout.nTopY )
                isFound := true
        }
        fAbort(!isFound, A_ThisFunc, "Couldn't find matching door mountpart and cutout.", { "pFile": pFile } )
    }
    ;===============  ^^^  Looking for matching CUTOUTs just to make sure.  ^^^  ==============;
    aDoorFrames := []
    For _, dDoor in aDoors {

        dLeftBar := "", dRightBar := ""
        For _, dBar in dBarsFlat.aVertical {
            dNextBar := dBarsFlat.aVertical[A_Index+1]
            ; msgbox % "«" dBar.x "» < «" dDoor.nLeftX "», «" dBar.nLength "» > «" dDoor.nTopY "»`n"
                    ; . "«" dNextBar.x "» > «" dDoor.nLeftX "»"
            If ( ( dBar.x < dDoor.nLeftX ) and ( dBar.nLength > dDoor.nTopY )
             and ( dNextBar.x > dDoor.nLeftX ) ) {
                dLeftBar := dBar.Clone()
            }
            If ( ( dBar.x < dDoor.nRightX )
             and ( dNextBar.x > dDoor.nRightX ) and ( dNextBar.nLength > dDoor.nTopY ) ) {
                dRightBar := dNextBar.Clone()
                break
            }
        }

        dTopBar := ""
        For _, dBar in dBarsFlat.aHorizontal {
            ; msgbox % "«" dBar.y "» < «" dDoor.nTopY "»`n«" dBar.nLength "» > «" dDoor.nRightX - dDoor.nLeftX "»"
            If ( (dBar.y > dDoor.nTopY) and ( dBar.nLength > (dDoor.nRightX - dDoor.nLeftX) ) ) {
                dTopBar := dBar.Clone()
                break
            }
        }

        If ( dLeftBar and dRightBar and dTopBar ) {
            aDoorFrames.Push( { "dLeftBar": dLeftBar, "dRightBar": dRightBar, "dTopBar": dTopBar } )
        }
    }
    ; ##############################  ^^^  FINDING DOOR-FRAMING BARS ^^^  #################### ;

    ; ####  vvv TRIMMING BARS THAT STICK OUT TOO FAR INTO DOORWAYS IN FLAT MESHES  vvv  ###### ;
    For _, dFrame in aDoorFrames {
        
        ; @@@@@@@@@@@@@  Horizontal Bars @@@@@@@@@@@@ ;
        For _, dBar in dBarsFlat.aHorizontal {
            If not ( dBar.y < dFrame.dTopBar.y ) {
                continue ; SKIP if not lower than the bar right above the doorway.
            }            
            nJutNew := 15

            ;======= Left Bar =======;
            nJutLeft := dBar.nRightX - dFrame.dLeftBar.x ; How far it sticks out beyond the Left Bar.
            ; msgbox % fObjToStr(dBar) "`n`n"
            ; . "( «" dBar.nLeftX "» < «" dFrame.dLeftBar.x "» ) and ( «" nJutLeft "» > «" nJutNew "» )"
            If ( ( dBar.nLeftX < dFrame.dLeftBar.x ) and ( nJutLeft > nJutNew )
                and ( dBar.nRightX < dFrame.dRightBar.x ) ) { ; Bar must not go all the way accross the doorway.
                If ( ( dBar.nLength - ( nJutLeft - nJutNew ) ) >= 500 ) {
                    dBar.nLength := dBar.nLength - ( nJutLeft - nJutNew )
                } else {
                    dBar.x := dBar.x - ( nJutLeft - nJutNew )
                }
            }
            ;======= Right Bar =======;
            nJutRight := dFrame.dRightBar.x - dBar.nLeftX ; How far it sticks out beyond the Right Bar.
            If ( ( dBar.nRightX > dFrame.dRightBar.x ) and ( nJutRight > nJutNew )
                and (dBar.nLeftX > dFrame.dLeftBar.x) ) { ; dBar must not go all the way accross the doorway.
                If ( ( dBar.nLength - ( nJutRight - nJutNew ) ) >= 500 ) {
                    dBar.nLength := dBar.nLength - ( nJutRight - nJutNew )
                }
                dBar.x := dBar.x + ( nJutRight - nJutNew )
            }
        }

        ; @@@@@@@@@@@@@  Vertical Bars @@@@@@@@@@@@ ;
        For _, dBar in dBarsFlat.aVertical {
            If not ( ( dBar.x > dFrame.dLeftBar.x ) and (dBar.x < dFrame.dRightBar.x) ){
                continue ; SKIP if not between the Left Bar and the Right Bar of the doorway.
            }
            ;======= Top Bar =======;
            nJutTop := dFrame.dTopBar.y - dBar.nBotY ; How far it sticks out below the Top Bar.
            If ( ( dBar.nTopY > dFrame.dTopBar.y ) and ( nJutTop > nJutNew ) ) {
                If ( ( dBar.nLength - ( nJutTop - nJutNew ) ) >= 500 ) {
                    dBar.nLength := dBar.nLength - ( nJutTop - nJutNew )
                }
                dBar.y := dBar.y + ( nJutTop - nJutNew )
            }
        }
    }

    For _, aList in dBarsFlat {
        For _, dBar in aList {

            isElement := dBar.elRef.selectSingleNode( ns("X") ).text
            nBarX := isElement ? isElement : 0
            If ( nBarX != dBar.x ) {
                ; Longitudinal bars: distance between the first weld point and the right end of
                ; the bar must be at least 300mm. Otherwise MSystem automatically extends them.
                aWeldedBars := fGetWeldedBars(dBar, dBarsFlat)
                If ( ( dBar.x + dBar.nLength - aWeldedBars[1].x ) >= 300 ) {
                    isTrimmed := true

                    If ( isElement ) {
                        dBar.elRef.selectSingleNode( ns("X") ).text := dBar.x
                    } else {
                        el := oPanelXML.createNode( 1, "X", oPanelXML.DocumentElement.NamespaceURI )
                        el.text := dBar.x
                        oBar.appendChild( el )
                        t := oPanelXML.createTextNode( "`r`n" )
                        oBar.appendChild( t )
                    }
                } 
            }

            isElement := dBar.elRef.selectSingleNode( ns("Y") ).text
            nBarY := isElement ? isElement : 0
            If ( nBarY != dBar.y ) {
                    isTrimmed := true

                    If ( isElement ) {
                        dBar.elRef.selectSingleNode( ns("Y") ).text := dBar.y
                    } else {
                        el := oPanelXML.createNode( 1, "Y", oPanelXML.DocumentElement.NamespaceURI )
                        el.text := dBar.y
                        oBar.appendChild( el )
                        t := oPanelXML.createTextNode( "`r`n" )
                        oBar.appendChild( t )
                    }
            }

            If ( dBar.elRef.selectSingleNode( ns("Segment","L") ).text != dBar.nLength ) {
                isTrimmed := true
                dBar.elRef.selectSingleNode( ns("Segment","L") ).text := dBar.nLength
            }
        }
    }
    ; ####  ^^^ TRIMMING BARS THAT STICK OUT TOO FAR INTO DOORWAYS IN FLAT MESHES  ^^^  ###### ;

    sXml := RegExReplace(oPanelXML.xml, "S)\Q<?xml version=""1.0""?><PXML\E"
                        , "<?xml version=""1.0"" encoding=""utf-8""?>`r`n<PXML")

    return { "isTrimmed": isTrimmed, "nDoorCount": aDoors.Length()
    , "sXml": sXml }
}

; dBars.aHorizontal and dBars.aVertical must be sorted.
; Returns a sorted (left to right or bot to top) array of bars that have common weld points with
; the given bar.
fGetWeldedBars(dBar, dBars) {
    Local
    aWeldedBars := []
    sCrossBarsType := ( dBar.RotZ == 0 ) ? "aVertical" : "aHorizontal"
    ; sCrossBarsType is opposite to the type of dBar, i.e. vertical if dBar is horizontal.
    For _, dCrossBar in dBars[sCrossBarsType] {
        ; To check if numerical ranges overlap: (StartA <= EndB) and (EndA >= StartB)
        ; Minimum welding offset from the ends of bars is 10mm. 9mm or lower are not considered
        ; weld points by MSystem.
        If ( ( dBar.nLeftX <= (dCrossBar.nRightX-10) ) and ( dBar.nRightX >= (dCrossBar.nLeftX+10) ) )
        and ( ( dBar.nBotY <= (dCrossBar.nTopY-10) ) and ( dBar.nTopY >= (dCrossBar.nBotY+10) ) ) {
            aWeldedBars.Push( dCrossBar )
        }
    }

    return aWeldedBars
}

ns(aNodeNames*) { ; Some XML namespace bullshit
    Local
    sSelector := ""
    For idx, sNodeName in aNodeNames {
        If (A_Index > 1)
            sSelector .= "/"
        sSelector .= "*[namespace-uri()=""http://progress-m.com/ProgressXML/Version1"" and local-name()=""" sNodeName """]"
    }

    return sSelector
}
