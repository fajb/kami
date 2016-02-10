Require Import Lib.FMap Lib.Struct Semantics Syntax String List.
Require Import Program.Equality.

Set Implicit Arguments.
Section FnInv.
  Variable A B: Type.
  Variable f: A -> B.
  Variable f1To1: forall a1 a2, f a1 = f a2 -> a1 = a2.
  Variable fOnto: forall b, exists a, f a = b.
  
  Variable fInv: B -> A.
  Variable fInvFInverse: forall a, fInv (f a) = a.

  Lemma inv1To1: forall b1 b2, fInv b1 = fInv b2 -> b1 = b2.
  Proof.
    intros.
    destruct (fOnto b1) as [a1 fa1].
    destruct (fOnto b2) as [a2 fa2].
    subst.
    pose proof (fInvFInverse a1) as fa1.
    pose proof (fInvFInverse a2) as fa2.
    rewrite fa1, fa2 in H.
    f_equal; intuition.
  Qed.

  Lemma invOnto: forall a, exists b, fInv b = a.
  Proof.
    intros.
    exists (f a).
    intuition.
  Qed.

  Lemma fFInvInverse: forall b, f (fInv b) = b.
  Proof.
    intros.
    destruct (fOnto b) as [a fa].
    subst.
    f_equal.
    intuition.
  Qed.
End FnInv.

Section Rename.
  Variable p: string -> string.
  Variable p1To1: forall x y, p x = p y -> x = y.
  Variable pOnto: forall x, exists y, p y = x.

  Definition mapNameAttr A a := {| attrName := p (@attrName A a); attrType := attrType a |}.
  
  Fixpoint mapNamesList A (ls: list (Attribute A)) :=
    map (@mapNameAttr _) ls.

  Definition mapNamesMap A (m: M.t A) :=
    M.fold (fun k v old => M.add (p k) v old) m (M.empty _).

  Lemma mapNamesMapEmpty A: mapNamesMap (M.empty A) = M.empty A.
  Proof.
    apply (M.F.P.fold_Empty); intuition.
  Qed.

  Lemma mapNamesMapAdd A m: forall k (v: A),
      ~ M.In k m ->
      mapNamesMap (M.add k v m) = M.add (p k) v (mapNamesMap m).
  Proof.
    intros; unfold mapNamesMap; rewrite M.F.P.fold_add; simpl in *; intuition.
    unfold M.F.P.transpose_neqkey; intros.
    assert (pneq: p k0 <> p k') by (unfold not; intros; apply H0; apply p1To1; intuition).
    apply M.transpose_neqkey_eq_add; intuition.
  Qed.
  
  Lemma mapNamesMapsTo1 A m: forall k (v: A),
      M.MapsTo k v m ->
      M.MapsTo (p k) v (mapNamesMap m).
  Proof.
    M.mind m.
    - apply M.F.P.F.empty_mapsto_iff in H; intuition.
    - apply M.F.P.F.add_mapsto_iff in H1.
      destruct H1 as [[keq veq] | [kneq kin]].
      + subst.
        rewrite mapNamesMapAdd; intuition.
        apply M.F.P.F.add_mapsto_iff; intuition.
      + specialize (H _ _ kin).
        rewrite mapNamesMapAdd; intuition.
        apply M.F.P.F.add_mapsto_iff; intuition.
  Qed.

  Lemma mapNamesMapsTo2 A m: forall k (v: A),
      M.MapsTo (p k) v (mapNamesMap m) ->
      M.MapsTo k v m.
  Proof.
    M.mind m.
    - apply M.F.P.F.empty_mapsto_iff in H; intuition.
    - rewrite mapNamesMapAdd in H1; intuition; apply M.F.P.F.add_mapsto_iff in H1.
      destruct H1 as [[keq veq] | [kneq kin]].
      + specialize (p1To1 keq).
        subst.
        apply M.F.P.F.add_mapsto_iff; intuition.
      + specialize (H _ _ kin).
        assert (kneq': k <> k0) by (unfold not; intros; subst; intuition).
        apply M.F.P.F.add_mapsto_iff; intuition.
  Qed.

  Definition mapNameUnitLabel l :=
    match l with
      | Rle None => Rle None
      | Meth None => Meth None
      | Rle (Some r) => Rle (Some (p r))
      | Meth (Some {| attrName := f; attrType := v |}) => Meth (Some {| attrName := p f; attrType := v |})
    end.

  Section SomeType.
    
    Fixpoint mapNamesAction t k (a: ActionT t k) :=
      match a with
      | MCall meth s e cont => MCall (p meth) s e (fun v => mapNamesAction (cont v))
      | Let_ lret' e cont => Let_ e (fun v => mapNamesAction (cont v))
      | ReadReg r k cont => ReadReg r k (fun v => mapNamesAction (cont v))
      | WriteReg r k e cont => WriteReg r e (mapNamesAction cont)
      | IfElse e k t f cont => IfElse e (mapNamesAction t) (mapNamesAction f)
                                      (fun v => mapNamesAction (cont v))
      | Assert_ e cont => Assert_ e (mapNamesAction cont)
      | Return e => Return e
      end.

    Lemma actionMapName o k a u cs r (sa: @SemAction o k a u cs r):
      SemAction (mapNamesMap o) (mapNamesAction a) (mapNamesMap u) (mapNamesMap cs) r.
    Proof.
      dependent induction sa; simpl in *.
      - 
  Lemma mapNamesKeysEq A (m: M.t A) l:
    M.KeysEq m l ->
    M.KeysEq (mapNamesMap m) (map p l).
  Proof.
    admit.
  Qed.

End Rename.