# Generic array helpers that `for` doesn't cover (for already gives
# map/filter/flat-map). Predicates are failable functions, so these compose
# with any <decides> check.

# Failable predicate and binary fold step.
predicate<public>(t:type) := type{_(:t)<transacts><decides>:void}
fold_step<public>(t:type, u:type) := type{_(:u, :t)<transacts>:u}


(Arr:[]t where t:type, u:type).Fold<public>(Init:u, F:fold_step(t, u))<transacts>:u =
    var Acc:u = Init
    for (X : Arr):
        set Acc = F(Acc, X)
    Acc

# Fold with the first element as seed. Fails on empty.
(Arr:[]t where t:type).Reduce<public>(F:type{_(:t, :t)<transacts>:t})<transacts><decides>:t =
    var Acc:t = Arr[0]
    for (I -> X : Arr, I > 0):
        set Acc = F(Acc, X)
    Acc

# Pairs up to the shorter length.
(A:[]t where t:type, u:type).Zip<public>(B:[]u)<transacts>:[]tuple(t, u) =
    for (I -> X : A, Y := B[I]):
        (X, Y)

(Arr:[]t where t:type).Reversed<public>()<transacts>:[]t =
    for (I -> X : Arr, Y := Arr[Arr.Length - 1 - I]):
        Y

# Fails unless every element satisfies P. Counts because a failing for
# body skips, it doesn't fail the function.
(Arr:[]t where t:type).All<public>(P:predicate(t))<transacts><decides>:void =
    Passing := for (X : Arr, P[X]) { X }
    Passing.Length = Arr.Length

# First element satisfying P. Doubles as Any.
(Arr:[]t where t:type).FirstWhere<public>(P:predicate(t))<transacts><decides>:t =
    first (X : Arr, P[X]) { X }

(Arr:[]t where t:type).CountIf<public>(P:predicate(t))<transacts>:int =
    for (X : Arr, P[X]) { X }.Length

# (passing, failing)
(Arr:[]t where t:type).Partition<public>(P:predicate(t))<transacts>:tuple([]t, []t) =
    Pass := for (X : Arr, P[X]) { X }
    Fail := for (X : Arr, not P[X]) { X }
    (Pass, Fail)
