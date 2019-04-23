Require Import Bool String List ZArith.BinInt.
Require Import Lib.CommonTactics Lib.Word Lib.Struct.
Require Import Kami.Syntax Kami.Semantics Kami.Notations.
Require Import Ex.MemTypes Ex.SC.

Require Import riscv.Spec.Decode.

Definition rv32InstBytes := 4.
Definition rv32DataBytes := 4.
(* 2^5 = 32 general purpose registers, x0 is hardcoded though *)
Definition rv32RfIdx := 5. 

Section Common.

  Definition getOpcodeE {ty}
             (inst : Expr ty (SyntaxKind (Data rv32DataBytes))) :=
    (UniBit (Trunc 7 _) inst)%kami_expr.

  Definition getRs1E {ty}
             (inst : Expr ty (SyntaxKind (Data rv32DataBytes))) :=
    (UniBit (ConstExtract 15 5 _) inst)%kami_expr.
  
  Definition getRs1ValueE {ty}
             (s : StateT rv32DataBytes rv32RfIdx ty)
             (inst : Expr ty (SyntaxKind (Data rv32DataBytes))) :=
    (#s @[getRs1E inst])%kami_expr.

  Definition getRs2E {ty}
             (inst : Expr ty (SyntaxKind (Data rv32DataBytes))) :=
    (UniBit (ConstExtract 20 5 _) inst)%kami_expr.

  Definition getRs2ValueE {ty}
             (s : StateT rv32DataBytes rv32RfIdx ty)
             (inst : Expr ty (SyntaxKind (Data rv32DataBytes))) :=
    (#s @[getRs2E inst])%kami_expr.

  Definition getRdE {ty}
             (inst: Expr ty (SyntaxKind (Data rv32DataBytes))) :=
    UniBit (ConstExtract 7 5 _) inst.

  Definition getFunct7E {ty}
             (inst : Expr ty (SyntaxKind (Data rv32DataBytes))) :=
    (UniBit (TruncLsb 25 7) inst)%kami_expr.

  Definition getFunct3E {ty}
             (inst : Expr ty (SyntaxKind (Data rv32DataBytes))) :=
    (UniBit (ConstExtract 12 3 _) inst)%kami_expr.

  Definition getOffsetIE {ty}
             (inst : Expr ty (SyntaxKind (Data rv32DataBytes))) :=
    (UniBit (TruncLsb 20 12) inst)%kami_expr.

  Definition getOffsetShamtE {ty}
             (inst : Expr ty (SyntaxKind (Data rv32DataBytes))) :=
    (UniBit (ConstExtract 20 5 _) inst)%kami_expr.

  Definition getOffsetSE {ty}
             (inst : Expr ty (SyntaxKind (Data rv32DataBytes))) :=
    (BinBit (Concat _ _)
            (UniBit (TruncLsb 25 7) inst)
            (UniBit (ConstExtract 7 5 _) inst))%kami_expr.

  Definition getOffsetSBE {ty}
             (inst: Expr ty (SyntaxKind (Data rv32DataBytes))) :=
    (BinBit (Concat _ _)
            (BinBit (Concat _ _)
                    (UniBit (TruncLsb 31 1) inst)
                    (UniBit (ConstExtract 7 1 _) inst))
            (BinBit (Concat _ _)
                    (UniBit (ConstExtract 25 6 _) inst)
                    (UniBit (ConstExtract 8 4 _) inst)))%kami_expr.

  Definition getOffsetUE {ty}
             (inst: Expr ty (SyntaxKind (Data rv32DataBytes))) :=
    (UniBit (TruncLsb 12 20) inst)%kami_expr.

  Definition getOffsetUJE {ty}
             (inst: Expr ty (SyntaxKind (Data rv32DataBytes))) :=
    (BinBit (Concat _ _)
            (BinBit (Concat _ _)
                    (UniBit (TruncLsb 31 1) inst)
                    (UniBit (ConstExtract 12 8 _) inst))
            (BinBit (Concat _ _)
                    (UniBit (ConstExtract 20 1 _) inst)
                    (UniBit (ConstExtract 21 10 _) inst))).
End Common.

Local Notation "$ z" := (Const _ (ZToWord _ z)) (at level 0) : kami_expr_scope.

(** RV32I instructions (#instructions=47, categorized by opcode_)):
 * - Supported(31)
 *   + opcode_LUI(1): lui
 *   + opcode_AUIPC(1): auipc
 *   + opcode_JAL(1): jal
 *   + opcode_JALR(1): jalr
 *   + opcode_BRANCH(6): beq, bne, blt, bge, bltu, bgeu
 *   + opcode_LOAD(1): lw
 *   + opcode_STORE(1): sw
 *   + opcode_OP_IMM_32(9): addi, slti, sltiu, xori, ori, andi, slli, srli, srai
 *   + opcode_OP(10): add, sub, sll, slt, sltu, xor, srl, sra, or, and
 * - Not supported yet(6)
 *   + opcode_LOAD(4): lb, lh, lbu, lhu
 *   + opcode_STORE(2): sb, sh
 * - No plan to support(10)
 *   + opcode_MISC_MEM(2): fence, fence.i
 *   + opcode_SYSTEM(8): ecall, ebreak, csrrw, csrrs, csrrc, csrrwi, csrrsi, csrrci
 *
 ** RV32M instructions
 * - Supported(1)
 *   + opcode_OP(1): mul
 * - Not supported yet(7)
 *   + opcode_OP(7): mulh, mulhsu, mulhu, div, divu, rem, remu
 *)

Section RV32IM.
  Variables rv32AddrSize (* 2^(rv32AddrSize) memory cells *)
            rv32IAddrSize: nat. (* 2^(rv32IAddrSize) instructions *)

  Section Decode.

    Definition rv32GetOptype: OptypeT rv32InstBytes.
      unfold OptypeT; intros ty inst.
      refine (IF (getOpcodeE #inst == $opcode_LOAD) then $$opLd else _)%kami_expr.
      refine (IF (getOpcodeE #inst == $opcode_STORE) then $$opSt else $$opNm)%kami_expr.
    Defined.

    Definition rv32GetLdDst: LdDstT rv32InstBytes rv32RfIdx.
      unfold LdDstT; intros ty inst.
      exact (getRdE #inst)%kami_expr.
    Defined.

    Definition rv32GetLdAddr: LdAddrT rv32AddrSize rv32InstBytes.
      unfold LdAddrT; intros ty inst.
      exact (_signExtend_ (getOffsetIE #inst))%kami_expr.
    Defined.

    Definition rv32GetLdSrc: LdSrcT rv32InstBytes rv32RfIdx.
      unfold LdSrcT; intros ty inst.
      exact (getRs1E #inst)%kami_expr.
    Defined.

    Definition rv32CalcLdAddr: LdAddrCalcT rv32AddrSize rv32DataBytes.
      unfold LdAddrCalcT; intros ty ofs base.
      exact ((_zeroExtend_ #base) + (_signExtend_ #ofs))%kami_expr.
    Defined.

    Definition rv32GetStAddr: StAddrT rv32AddrSize rv32InstBytes.
      unfold StAddrT; intros ty inst.
      exact (_signExtend_ (getOffsetSE #inst))%kami_expr.
    Defined.
      
    Definition rv32GetStSrc: StSrcT rv32InstBytes rv32RfIdx.
      unfold StSrcT; intros ty inst.
      exact (getRs1E #inst)%kami_expr.
    Defined.
    
    Definition rv32CalcStAddr: StAddrCalcT rv32AddrSize rv32DataBytes.
      unfold StAddrCalcT; intros ty ofs base.
      exact ((_zeroExtend_ #base) + (_signExtend_ #ofs))%kami_expr.
    Defined.

    Definition rv32GetStVSrc: StVSrcT rv32InstBytes rv32RfIdx.
      unfold StVSrcT; intros ty inst.
      exact (getRs2E #inst)%kami_expr.
    Defined.

    Definition rv32GetSrc1: Src1T rv32InstBytes rv32RfIdx.
      unfold Src1T; intros ty inst.
      exact (getRs1E #inst)%kami_expr.
    Defined.
    
    Definition rv32GetSrc2: Src2T rv32InstBytes rv32RfIdx.
      unfold Src2T; intros ty inst.
      exact (getRs2E #inst)%kami_expr.
    Defined.

    Definition rv32GetDst: DstT rv32InstBytes rv32RfIdx.
      unfold DstT; intros ty inst.
      refine (IF (getOpcodeE #inst == $opcode_BRANCH) then _ else _)%kami_expr.
      - exact ($0)%kami_expr. (* Branch instructions should not write registers *)
      - exact (getRdE #inst)%kami_expr.
    Defined.

  End Decode.
    
  Ltac register_op_funct7 inst op expr :=
    refine (IF (getFunct7E #inst == $op) then expr else _)%kami_expr.
  Ltac register_op_funct3 inst op expr :=
    refine (IF (getFunct3E #inst == $op) then expr else _)%kami_expr.

  Definition rv32Exec: ExecT rv32AddrSize rv32InstBytes rv32DataBytes.
    unfold ExecT; intros ty val1 val2 pc inst.

    refine (IF (getOpcodeE #inst == $opcode_LUI)
            then {getOffsetUE #inst, $0::(12)}
            else _)%kami_expr.
    refine (IF (getOpcodeE #inst == $opcode_AUIPC)
            then ((_zeroExtend_ #pc) + {getOffsetUE #inst, $0::(12)})
            else _)%kami_expr.
    refine (IF (getOpcodeE #inst == $opcode_JAL)
            then (_zeroExtend_ (#pc + $4))
            else _)%kami_expr.
    refine (IF (getOpcodeE #inst == $opcode_JALR)
            then (_zeroExtend_ (#pc + $4))
            else _)%kami_expr.

    refine (IF (getOpcodeE #inst == $opcode_OP_IMM_32) then _ else _)%kami_expr.
    1: {
      register_op_funct3 inst funct3_ADDI
                         (#val1 + (_signExtend_ (getOffsetIE #inst)))%kami_expr.
      register_op_funct3 inst funct3_SLTI
                         (IF (#val1 < (_signExtend_ (getOffsetIE #inst)))
                          then $1 else $$(natToWord (rv32DataBytes * 8) 0))%kami_expr.
      register_op_funct3 inst funct3_SLTIU
                         (IF (#val1 < (_zeroExtend_ (getOffsetIE #inst)))
                          then $1 else $$(natToWord (rv32DataBytes * 8) 0))%kami_expr.
      register_op_funct3 inst funct3_XORI
                         (#val1 ~+ (_signExtend_ (getOffsetIE #inst)))%kami_expr.
      register_op_funct3 inst funct3_ORI
                         (#val1 ~| (_signExtend_ (getOffsetIE #inst)))%kami_expr.
      register_op_funct3 inst funct3_ANDI
                         (#val1 ~& (_signExtend_ (getOffsetIE #inst)))%kami_expr.
      register_op_funct3 inst funct3_SLLI
                         (#val1 << (getOffsetShamtE #inst))%kami_expr.
      register_op_funct3 inst funct3_SRLI
                         (#val1 >> (getOffsetShamtE #inst))%kami_expr.
      register_op_funct3 inst funct3_SRAI
                         (#val1 ~>> (getOffsetShamtE #inst))%kami_expr.
      exact ($$Default)%kami_expr. (* This should never happen. *)
    }

    refine (IF (getOpcodeE #inst == $opcode_OP) then _ else $$Default)%kami_expr.
    refine (IF (getFunct7E #inst == $funct7_ADD) then _ else _)%kami_expr.
    1: {
      register_op_funct3 inst funct3_ADD (#val1 + #val2)%kami_expr.
      register_op_funct3 inst funct3_SLL (#val1 << (UniBit (Trunc 5 _) #val2))%kami_expr.
      register_op_funct3 inst funct3_SLT
                         (IF ((UniBit (TruncLsb 31 1) (#val1 - #val2)) == $1)
                          then $1 else $$(natToWord (rv32DataBytes * 8) 0))%kami_expr.
      register_op_funct3 inst funct3_SLTU
                         (IF (#val1 < #val2)
                          then $1 else $$(natToWord (rv32DataBytes * 8) 0))%kami_expr.
      register_op_funct3 inst funct3_XOR (#val1 ~+ #val2)%kami_expr.
      register_op_funct3 inst funct3_SRL (#val1 >> (UniBit (Trunc 5 _) #val2))%kami_expr.
      register_op_funct3 inst funct3_OR (#val1 ~| #val2)%kami_expr.
      register_op_funct3 inst funct3_AND (#val1 ~& #val2)%kami_expr.
      exact ($$Default)%kami_expr. (* This should never happen. *)
    }

    refine (IF (getFunct7E #inst == $funct7_SUB) then _ else _)%kami_expr.
    1: {
      register_op_funct3 inst funct3_SUB (#val1 - #val2)%kami_expr.
      register_op_funct3 inst funct3_SRA (#val1 ~>> (UniBit (Trunc 5 _) #val2))%kami_expr.
      exact ($$Default)%kami_expr. (* This should never happen. *)
    }
    
    refine (IF (getFunct7E #inst == $funct7_MUL) then _ else _)%kami_expr.
    1: {
      register_op_funct3 inst funct3_MUL (#val1 * #val2)%kami_expr.
      exact ($$Default)%kami_expr. (* undefined semantics so far *)
    }

    exact ($$Default)%kami_expr. (* undefined semantics so far *)

  Defined.

  Definition rv32AlignAddr: AlignAddrT rv32AddrSize.
    unfold AlignAddrT; intros ty addr.
    exact (#addr)%kami_expr.
  Defined.

  Definition rv32NextPc: NextPcT rv32AddrSize rv32InstBytes rv32DataBytes rv32RfIdx.
    unfold NextPcT; intros ty st pc inst.

    refine (IF (getOpcodeE #inst == $opcode_JAL)
            then #pc + (_signExtend_ ((getOffsetUJE #inst) << $$(natToWord 1 1)))
            else _)%kami_expr.
    refine (IF (getOpcodeE #inst == $opcode_JALR)
            then (_signExtend_ (getRs1ValueE st #inst))
                 + (_signExtend_ (getOffsetIE #inst))
            else _)%kami_expr.

    refine (IF (getOpcodeE #inst == $opcode_BRANCH) then _ else #pc + $4)%kami_expr.
    register_op_funct3 inst funct3_BEQ
                       (IF (getRs1ValueE st #inst == getRs2ValueE st #inst)
                        then #pc + (_signExtend_ ((getOffsetSBE #inst) << $$(natToWord 1 1)))
                        else #pc + $4)%kami_expr.
    register_op_funct3 inst funct3_BNE
                       (IF (getRs1ValueE st #inst != getRs2ValueE st #inst)
                        then #pc + (_signExtend_ ((getOffsetSBE #inst) << $$(natToWord 1 1)))
                        else #pc + $4)%kami_expr.
    register_op_funct3 inst funct3_BLT
                       (IF ((UniBit (TruncLsb 31 1)
                                    (getRs1ValueE st #inst - getRs2ValueE st #inst)) == $1)
                        then #pc + (_signExtend_ ((getOffsetSBE #inst) << $$(natToWord 1 1)))
                        else #pc + $4)%kami_expr.
    register_op_funct3 inst funct3_BGE
                       (IF ((UniBit (TruncLsb 31 1)
                                    (getRs1ValueE st #inst - getRs2ValueE st #inst)) == $0)
                        then #pc + (_signExtend_ ((getOffsetSBE #inst) << $$(natToWord 1 1)))
                        else #pc + $4)%kami_expr.
    register_op_funct3 inst funct3_BLTU
                       (IF (getRs1ValueE st #inst < getRs2ValueE st #inst)
                        then #pc + (_signExtend_ ((getOffsetSBE #inst) << $$(natToWord 1 1)))
                        else #pc + $4)%kami_expr.
    register_op_funct3 inst funct3_BGEU
                       (IF (getRs1ValueE st #inst >= getRs2ValueE st #inst)
                        then #pc + (_signExtend_ ((getOffsetSBE #inst) << $$(natToWord 1 1)))
                        else #pc + $4)%kami_expr.
    exact (#pc + $4)%kami_expr.
  Defined.

End RV32IM.

