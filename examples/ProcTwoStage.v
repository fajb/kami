Require Import Bool String List.
Require Import Lib.CommonTactics Lib.ilist Lib.Word Lib.Indexer Lib.StringBound.
Require Import Kami.Syntax Kami.Notations Kami.Semantics Kami.Specialize Kami.Duplicate.
Require Import Kami.Wf Kami.ParametricEquiv Kami.Tactics.
Require Import Ex.MemTypes Ex.SC Ex.Fifo Ex.MemAtomic.

Set Implicit Arguments.

(* A fifo containing only one element.
 * Implementation is much simpler than the general fifo, implemented in Fifo.v
 *)
Section OneEltFifo.
  Variable fifoName: string.
  Variable dType: Kind.

  Local Notation "^ s" := (fifoName -- s) (at level 0).

  Definition enq {ty} : forall (d: ty dType), ActionT ty Void := fun d =>
    (Read isFull <- ^"full";
     Assert !#isFull;
     Write ^"elt" <- #d;
     Write ^"full" <- $$true;
     Retv)%kami_action.

  Definition deq {ty} : ActionT ty dType :=
    (Read isFull <- ^"full";
     Assert #isFull;
     Read elt <- ^"elt";
     Write ^"full" <- $$false;
     Ret #elt)%kami_action.

  Definition firstElt {ty} : ActionT ty dType :=
    (Read isFull <- ^"full";
     Assert #isFull;
     Read elt <- ^"elt";
     Ret #elt)%kami_action.

  Definition isFull {ty} : ActionT ty Bool :=
    (Read isFull <- ^"full";
     Ret #isFull)%kami_action.
  
  Definition oneEltFifo := MODULE {
    Register ^"elt" : dType <- Default
    with Register ^"full" : Bool <- Default

    with Method ^"enq"(d : dType) : Void := (enq d)
    with Method ^"deq"() : dType := deq
  }.

  Definition oneEltFifoEx := MODULE {
    Register ^"elt" : dType <- Default
    with Register ^"full" : Bool <- Default

    with Method ^"enq"(d : dType) : Void := (enq d)
    with Method ^"deq"() : dType := deq
    with Method ^"isFull"() : Bool := isFull
  }.

End OneEltFifo.

Hint Unfold oneEltFifo oneEltFifoEx : ModuleDefs.
Hint Unfold enq deq firstElt isFull : MethDefs.

(* A two-staged processor, where two sets, {fetch, decode} and {execute, commit, write-back},
 * are modularly separated to form each stage. "epoch" registers are used to handle incorrect
 * branch prediction. Like a decoupled processor, memory operations are stalled until getting 
 * the response.
 *)
Section ProcTwoStage.
  Variable inName outName: string.
  Variables addrSize lgDataBytes rfIdx: nat.

  (* External abstract ISA: decoding and execution *)
  Variables (getOptype: OptypeT lgDataBytes)
            (getLdDst: LdDstT lgDataBytes rfIdx)
            (getLdAddr: LdAddrT addrSize lgDataBytes)
            (getLdSrc: LdSrcT lgDataBytes rfIdx)
            (calcLdAddr: LdAddrCalcT addrSize lgDataBytes)
            (getStAddr: StAddrT addrSize lgDataBytes)
            (getStSrc: StSrcT lgDataBytes rfIdx)
            (calcStAddr: StAddrCalcT addrSize lgDataBytes)
            (getStVSrc: StVSrcT lgDataBytes rfIdx)
            (getSrc1: Src1T lgDataBytes rfIdx)
            (getSrc2: Src2T lgDataBytes rfIdx)
            (execState: ExecStateT addrSize lgDataBytes rfIdx)
            (execNextPc: ExecNextPcT addrSize lgDataBytes rfIdx).

  Definition RqFromProc := MemTypes.RqFromProc lgDataBytes (Bit addrSize).
  Definition RsToProc := MemTypes.RsToProc lgDataBytes.

  Definition memReq := MethodSig (inName -- "enq")(RqFromProc) : Void.
  Definition memRep := MethodSig (outName -- "deq")() : RsToProc.

  Definition d2eElt :=
    STRUCT { "opType" :: Bit 2;
             "dst" :: Bit rfIdx;
             "addr" :: Bit addrSize;
             "val" :: Data lgDataBytes;
             "rawInst" :: Data lgDataBytes;
             "curPc" :: Bit addrSize;
             "nextPc" :: Bit addrSize;
             "epoch" :: Bool }.

  Definition d2eFifoName := "d2e"%string.
  Definition d2eEnq := MethodSig (d2eFifoName -- "enq")(d2eElt) : Void.
  Definition d2eDeq := MethodSig (d2eFifoName -- "deq")() : d2eElt.

  (* For correct pc redirection *)
  Definition e2dElt := Bit addrSize. 
  Definition e2dFifoName := "e2d"%string.
  Definition e2dEnq := MethodSig (e2dFifoName -- "enq")(e2dElt) : Void.
  Definition e2dDeq := MethodSig (e2dFifoName -- "deq")() : e2dElt.
  Definition e2dFull := MethodSig (e2dFifoName -- "isFull")() : Bool.

  Section RegFile.

    Definition regFile := MODULE {
      Register "rf" : Vector (Data lgDataBytes) rfIdx <- Default

      with Method "getRf" () : Vector (Data lgDataBytes) rfIdx :=
        Read rf <- "rf";
        Ret #rf

      with Method "setRf" (rf: Vector (Data lgDataBytes) rfIdx) : Void :=
        Write "rf" <- #rf;
        Retv
    }.
      
    Definition getRf := MethodSig "getRf"() : Vector (Data lgDataBytes) rfIdx.
    Definition setRf := MethodSig "setRf"(Vector (Data lgDataBytes) rfIdx) : Void.

  End RegFile.

  Section ScoreBoard.

    Definition scoreBoard := MODULE {
      Register "idx" : Bit rfIdx <- Default
      with Register "valid" : Bool <- false
                                   
      with Method "search1" (idx1: Bit rfIdx) : Bool :=
        Read idx <- "idx";
        Read valid <- "valid";
        Ret (#valid && #idx == #idx1)

      with Method "search2" (idx2: Bit rfIdx) : Bool :=
        Read idx <- "idx";
        Read valid <- "valid";
        Ret (#valid && #idx == #idx2)

      with Method "insert" (nidx: Bit rfIdx) : Void :=
        Write "idx" <- #nidx;
        Write "valid" <- $$true;
        Retv
        
      with Method "remove" () : Void :=
        Write "valid" <- $$false;
        Retv
    }.

    Definition sbSearch1 := MethodSig "search1"(Bit rfIdx) : Bool.
    Definition sbSearch2 := MethodSig "search2"(Bit rfIdx) : Bool.
    Definition sbInsert := MethodSig "insert"(Bit rfIdx) : Void.
    Definition sbRemove := MethodSig "remove"() : Void.
    
  End ScoreBoard.
    
  Section BranchPredictor.

    Definition branchPredictor := MODULE {
      Method "predictNextPc" (ppc: Bit addrSize) : Bit addrSize :=
        Ret (#ppc + $1)
    }.

  End BranchPredictor.
    
  Section Decode.
    Definition predictNextPc := MethodSig "predictNextPc"(Bit addrSize) : Bit addrSize.

    Definition decoder := MODULE {
      Register "pc" : Bit addrSize <- Default
      with Register "pgm" : Vector (Data lgDataBytes) addrSize <- Default
      with Register "fEpoch" : Bool <- false
                                    
      with Rule "modifyPc" :=
        Call correctPc <- e2dDeq();
        Write "pc" <- #correctPc;
        Read pEpoch <- "fEpoch";
        Write "fEpoch" <- !#pEpoch;
        Retv
          
      with Rule "instFetchLd" :=
        Call e2dFull <- e2dFull();
        Assert !#e2dFull;
        Read ppc : Bit addrSize <- "pc";
        Read pgm <- "pgm";
        LET rawInst <- #pgm@[#ppc];
        Call rf <- getRf();

        Call npc <- predictNextPc(#ppc);
        Read epoch <- "fEpoch";
        Write "fetchStall" <- $$false;
        Write "pc" <- #npc;

        LET opType <- getOptype _ rawInst;
        Assert (#opType == $$opLd);

        LET srcIdx <- getLdSrc _ rawInst;
        Call stall1 <- sbSearch1(#srcIdx);
        Assert !#stall1;
        Call sbInsert(getLdDst _ rawInst);
        LET addr <- getLdAddr _ rawInst;
        LET srcVal <- #rf@[#srcIdx];
        LET laddr <- calcLdAddr _ addr srcVal;
        Call d2eEnq(STRUCT { "opType" ::= #opType;
                             "dst" ::= getLdDst _ rawInst;
                             "addr" ::= #laddr;
                             "val" ::= $$Default;
                             "rawInst" ::= #rawInst;
                             "curPc" ::= #ppc;
                             "nextPc" ::= #npc;
                             "epoch" ::= #epoch });
        Retv

      with Rule "instFetchSt" :=
        Call e2dFull <- e2dFull();
        Assert !#e2dFull;
        Read ppc : Bit addrSize <- "pc";
        Read pgm <- "pgm";
        LET rawInst <- #pgm@[#ppc];
        Call rf <- getRf();

        Call npc <- predictNextPc(#ppc);
        Read epoch <- "fEpoch";
        Write "fetchStall" <- $$false;
        Write "pc" <- #npc;

        LET opType <- getOptype _ rawInst;
        Assert (#opType == $$opSt);

        LET srcIdx <- getStSrc _ rawInst;
        LET vsrcIdx <- getStVSrc _ rawInst;
        Call stall1 <- sbSearch1(#srcIdx);
        Call stall2 <- sbSearch2(#vsrcIdx);
        Assert !(#stall1 || #stall2);

        LET addr <- getStAddr _ rawInst;
        LET srcVal <- #rf@[#srcIdx];
        LET stVal <- #rf@[#vsrcIdx];
        LET saddr <- calcStAddr _ addr srcVal;
        Call d2eEnq(STRUCT { "opType" ::= #opType;
                             "dst" ::= $$Default;
                             "addr" ::= #saddr;
                             "val" ::= #stVal;
                             "rawInst" ::= #rawInst;
                             "curPc" ::= #ppc;
                             "nextPc" ::= #npc;
                             "epoch" ::= #epoch });
        Retv

      with Rule "instFetchTh" :=
        Call e2dFull <- e2dFull();
        Assert !#e2dFull;
        Read ppc : Bit addrSize <- "pc";
        Read pgm <- "pgm";
        LET rawInst <- #pgm@[#ppc];
        Call rf <- getRf();

        Call npc <- predictNextPc(#ppc);
        Read epoch <- "fEpoch";
        Write "fetchStall" <- $$false;
        Write "pc" <- #npc;

        LET opType <- getOptype _ rawInst;
        Assert (#opType == $$opTh);

        LET srcIdx <- getSrc1 _ rawInst;
        LET srcVal <- #rf@[#srcIdx];
        Call d2eEnq(STRUCT { "opType" ::= #opType;
                             "dst" ::= $$Default;
                             "addr" ::= $$Default;
                             "val" ::= #srcVal;
                             "rawInst" ::= #rawInst;
                             "curPc" ::= #ppc;
                             "nextPc" ::= #npc;
                             "epoch" ::= #epoch });
        Retv

      with Rule "instFetchNm" :=
        Call e2dFull <- e2dFull();
        Assert !#e2dFull;
        Read ppc : Bit addrSize <- "pc";
        Read pgm <- "pgm";
        LET rawInst <- #pgm@[#ppc];
        Call rf <- getRf();

        Call npc <- predictNextPc(#ppc);
        Read epoch <- "fEpoch";
        Write "fetchStall" <- $$false;
        Write "pc" <- #npc;

        LET opType <- getOptype _ rawInst;
        Assert (#opType == $$opNm);
        Call d2eEnq(STRUCT { "opType" ::= #opType;
                             "dst" ::= $$Default;
                             "addr" ::= $$Default;
                             "val" ::= $$Default;
                             "rawInst" ::= #rawInst;
                             "curPc" ::= #ppc;
                             "nextPc" ::= #npc;
                             "epoch" ::= #epoch });
        Retv
    }.

  End Decode.

  Section Execute.
    Definition toHost := MethodSig "toHost"(Data lgDataBytes) : Void.

    Definition checkNextPc {ty} ppc npcp st rawInst :=
      (LET npc <- execNextPc ty st ppc rawInst;
       If (#npc != #npcp)
       then
         Read pEpoch <- "eEpoch";
         Write "eEpoch" <- !#pEpoch;
         Call e2dEnq(#npc);
         Retv
       else
         Retv
       as _;
       Retv)%kami_action.
    
    Definition executer := MODULE {
      Register "stall" : Bool <- false
      with Register "eEpoch" : Bool <- false
      with Register "stalled" : d2eElt <- Default

      with Rule "wrongEpoch" :=
        Read stall <- "stall";
        Assert !#stall;
        Call d2e <- d2eDeq();
        LET fEpoch <- #d2e@."epoch";
        Read eEpoch <- "eEpoch";
        Assert (#fEpoch != #eEpoch);
        Retv

      with Rule "reqLd" :=
        Read stall <- "stall";
        Assert !#stall;
        Call st <- getRf();
        Call d2e <- d2eDeq();
        LET fEpoch <- #d2e@."epoch";
        Read eEpoch <- "eEpoch";
        Assert (#fEpoch == #eEpoch);
        Assert #d2e@."opType" == $$opLd;
        Assert #d2e@."dst" != $0;
        Call memReq(STRUCT { "addr" ::= #d2e@."addr";
                             "op" ::= $$false;
                             "data" ::= $$Default });
        Write "stall" <- $$true;
        Write "stalled" <- #d2e;
        Retv
          
      with Rule "reqLdZ" :=
        Read stall <- "stall";
        Assert !#stall;
        Call rf <- getRf();
        Call d2e <- d2eDeq();
        LET fEpoch <- #d2e@."epoch";
        Read eEpoch <- "eEpoch";
        Assert (#fEpoch == #eEpoch);
        Assert #d2e@."opType" == $$opLd;
        Assert #d2e@."dst" == $0;
        LET ppc <- #d2e@."curPc";
        LET npcp <- #d2e@."nextPc";
        LET rawInst <- #d2e@."rawInst";
        checkNextPc ppc npcp rf rawInst
                        
      with Rule "reqSt" :=
        Read stall <- "stall";
        Assert !#stall;
        Call d2e <- d2eDeq();
        LET fEpoch <- #d2e@."epoch";
        Read eEpoch <- "eEpoch";
        Assert (#fEpoch == #eEpoch);
        Assert #d2e@."opType" == $$opSt;
        Call memReq(STRUCT { "addr" ::= #d2e@."addr";
                             "op" ::= $$true;
                             "data" ::= #d2e@."val" });
        Write "stall" <- $$true;
        Write "stalled" <- #d2e;
        Retv
                                
      with Rule "repLd" :=
        Read stall <- "stall";
        Assert #stall;
        Call val <- memRep();
        Call rf <- getRf();
        Read curInfo : d2eElt <- "stalled";
        LET inst <- #curInfo;
        Assert #inst@."opType" == $$opLd;
        Call setRf (#rf@[#inst@."dst" <- #val@."data"]);
        Call sbRemove ();
        Write "stall" <- $$false;
        LET ppc <- #curInfo@."curPc";
        LET npcp <- #curInfo@."nextPc";
        LET rawInst <- #inst@."rawInst";
        checkNextPc ppc npcp rf rawInst

      with Rule "repSt" :=
        Read stall <- "stall";
        Assert #stall;
        Call val <- memRep();
        Call rf <- getRf();
        Read curInfo : d2eElt <- "stalled";
        LET inst <- #curInfo;
        Assert #inst@."opType" == $$opSt;
        Write "stall" <- $$false;
        LET ppc <- #curInfo@."curPc";
        LET npcp <- #curInfo@."nextPc";
        LET rawInst <- #inst@."rawInst";
        checkNextPc ppc npcp rf rawInst
                                
      with Rule "execToHost" :=
        Read stall <- "stall";
        Assert !#stall;
        Call rf <- getRf();
        Call d2e <- d2eDeq();
        LET fEpoch <- #d2e@."epoch";
        Read eEpoch <- "eEpoch";
        Assert (#fEpoch == #eEpoch);
        Assert #d2e@."opType" == $$opTh;
        Call toHost(#d2e@."val");
        LET ppc <- #d2e@."curPc";
        LET npcp <- #d2e@."nextPc";
        LET rawInst <- #d2e@."rawInst";
        checkNextPc ppc npcp rf rawInst

      with Rule "execNm" :=
        Read stall <- "stall";
        Assert !#stall;
        Call rf <- getRf();
        Call d2e <- d2eDeq();
        LET fEpoch <- #d2e@."epoch";
        Read eEpoch <- "eEpoch";
        Assert (#fEpoch == #eEpoch);
        LET ppc <- #d2e@."curPc";
        Assert #d2e@."opType" == $$opNm;
        LET rawInst <- #d2e@."rawInst";
        Call setRf (execState _ rf ppc rawInst);
        LET ppc <- #d2e@."curPc";
        LET npcp <- #d2e@."nextPc";
        checkNextPc ppc npcp rf rawInst
    }.
    
  End Execute.

  Definition procTwoStage := (decoder
                                ++ regFile
                                ++ scoreBoard
                                ++ branchPredictor
                                ++ oneEltFifo d2eFifoName d2eElt
                                ++ oneEltFifoEx e2dFifoName (Bit addrSize)
                                ++ executer)%kami.

End ProcTwoStage.

Hint Unfold regFile scoreBoard branchPredictor decoder executer procTwoStage : ModuleDefs.
Hint Unfold RqFromProc RsToProc memReq memRep
     d2eElt d2eFifoName d2eEnq d2eDeq
     e2dElt e2dFifoName e2dEnq e2dDeq e2dFull
     getRf setRf
     sbSearch1 sbSearch2 sbInsert sbRemove
     predictNextPc toHost checkNextPc : MethDefs.

Section ProcTwoStageM.
  Variables addrSize lgDataBytes rfIdx: nat.

  (* External abstract ISA: decoding and execution *)
  Variables (getOptype: OptypeT lgDataBytes)
            (getLdDst: LdDstT lgDataBytes rfIdx)
            (getLdAddr: LdAddrT addrSize lgDataBytes)
            (getLdSrc: LdSrcT lgDataBytes rfIdx)
            (calcLdAddr: LdAddrCalcT addrSize lgDataBytes)
            (getStAddr: StAddrT addrSize lgDataBytes)
            (getStSrc: StSrcT lgDataBytes rfIdx)
            (calcStAddr: StAddrCalcT addrSize lgDataBytes)
            (getStVSrc: StVSrcT lgDataBytes rfIdx)
            (getSrc1: Src1T lgDataBytes rfIdx)
            (getSrc2: Src2T lgDataBytes rfIdx)
            (execState: ExecStateT addrSize lgDataBytes rfIdx)
            (execNextPc: ExecNextPcT addrSize lgDataBytes rfIdx).

  Definition p2st := procTwoStage "rqFromProc"%string "rsToProc"%string
                                  getOptype getLdDst getLdAddr getLdSrc calcLdAddr
                                  getStAddr getStSrc calcStAddr getStVSrc
                                  getSrc1 execState execNextPc.

End ProcTwoStageM.

Hint Unfold p2st : ModuleDefs.

Section Facts.
  Variables addrSize lgDataBytes rfIdx: nat.

  (* External abstract ISA: decoding and execution *)
  Variables (getOptype: OptypeT lgDataBytes)
            (getLdDst: LdDstT lgDataBytes rfIdx)
            (getLdAddr: LdAddrT addrSize lgDataBytes)
            (getLdSrc: LdSrcT lgDataBytes rfIdx)
            (calcLdAddr: LdAddrCalcT addrSize lgDataBytes)
            (getStAddr: StAddrT addrSize lgDataBytes)
            (getStSrc: StSrcT lgDataBytes rfIdx)
            (calcStAddr: StAddrCalcT addrSize lgDataBytes)
            (getStVSrc: StVSrcT lgDataBytes rfIdx)
            (getSrc1: Src1T lgDataBytes rfIdx)
            (getSrc2: Src2T lgDataBytes rfIdx)
            (execState: ExecStateT addrSize lgDataBytes rfIdx)
            (execNextPc: ExecNextPcT addrSize lgDataBytes rfIdx).

  Lemma regFile_ModEquiv:
    ModPhoasWf (regFile lgDataBytes rfIdx).
  Proof. kequiv. Qed.
  Hint Resolve regFile_ModEquiv.

  Lemma scoreBoard_ModEquiv:
    ModPhoasWf (scoreBoard rfIdx).
  Proof. kequiv. Qed.
  Hint Resolve scoreBoard_ModEquiv.

  Lemma branchPredictor_ModEquiv:
    ModPhoasWf (branchPredictor addrSize).
  Proof. kequiv. Qed.
  Hint Resolve branchPredictor_ModEquiv.

  Lemma oneEltFifo_ModEquiv:
    forall fifoName dType, ModPhoasWf (oneEltFifo fifoName dType).
  Proof. kequiv. Qed.
  Hint Resolve oneEltFifo_ModEquiv.
  
  Lemma oneEltFifoEx_ModEquiv:
    forall fifoName dType, ModPhoasWf (oneEltFifoEx fifoName dType).
  Proof. kequiv. Qed.
  Hint Resolve oneEltFifoEx_ModEquiv.

  Lemma decoder_ModEquiv:
    ModPhoasWf (decoder getOptype getLdDst getLdAddr getLdSrc calcLdAddr
                        getStAddr getStSrc calcStAddr getStVSrc
                        getSrc1).
  Proof. (* SKIP_PROOF_ON
    kequiv.
    END_SKIP_PROOF_ON *) admit.
  Qed.
  Hint Resolve decoder_ModEquiv.

  Lemma executer_ModEquiv:
    forall inName outName,
      ModPhoasWf (executer inName outName execState execNextPc).
  Proof. (* SKIP_PROOF_ON
    kequiv.
    END_SKIP_PROOF_ON *) admit.
  Qed.
  Hint Resolve executer_ModEquiv.
  
  Lemma procTwoStage_ModEquiv:
    ModPhoasWf (p2st getOptype getLdDst getLdAddr getLdSrc calcLdAddr
                     getStAddr getStSrc calcStAddr getStVSrc
                     getSrc1 execState execNextPc).
  Proof.
    kequiv.
  Qed.

End Facts.

Hint Resolve regFile_ModEquiv
     scoreBoard_ModEquiv
     branchPredictor_ModEquiv
     oneEltFifo_ModEquiv
     oneEltFifoEx_ModEquiv
     decoder_ModEquiv
     executer_ModEquiv
     procTwoStage_ModEquiv.
