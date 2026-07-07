# All parametric container types live in the DataStructures FOLDER module so no
# parametrics sit at the content root (a module hosting parametric defs gets
# member resolution poisoned for its other members, 3502/3506, discussion #27
# in verselang/book). Explicit nested modules keep layering deterministic:
#   DataStructures            parametric interfaces + type aliases (this scope)
#   DataStructures.Containers implementation classes
#   DataStructures.Containers.Ops  extensions
# Worked-around bugs: 3502 (ordering, failable set RHS), 3503, 3509, 3510,
# 3532, 3552. Details in the claudeverse skill gotchas.

# ---------------------------------------------------------------------------
# Root: interfaces
# ---------------------------------------------------------------------------

graph_node<public>(t:type) := interface:
    GetValue<public>()<transacts>:t
    # Outgoing edges. For trees these are the children.
    Successors<public>()<transacts>:[]graph_node(t)


graph<public>(t:type) := interface:
    Nodes<public>()<transacts>:[]graph_node(t)
    NodeCount<public>()<transacts>:int


# Contract: acyclic, connected from the root, one parent per non-root node.
tree<public>(t:type) := interface(graph(t)):
    # Fails on an empty tree.
    GetRoot<public>()<transacts><decides>:graph_node(t)


binary_node<public>(t:type) := interface(graph_node(t)):
    GetLeft<public>()<transacts><decides>:binary_node(t)
    GetRight<public>()<transacts><decides>:binary_node(t)


binary_tree<public>(t:type) := interface(tree(t)):
    # Same node as GetRoot, typed as binary_node.
    GetBinaryRoot<public>()<transacts><decides>:binary_node(t)


sized<public> := interface:
    Count<public>()<transacts>:int


stack<public>(t:type) := interface(sized):
    Push<public>(V:t)<transacts>:void
    Pop<public>()<transacts><decides>:t
    Peek<public>()<transacts><decides>:t


queue<public>(t:type) := interface(sized):
    Enqueue<public>(V:t)<transacts>:void
    Dequeue<public>()<transacts><decides>:t
    Front<public>()<transacts><decides>:t


# A deque really is both: stack ops work the front, queue enqueues at the
# back. Diamond-inherits sized; implementors provide Count once.
deque<public>(t:type) := interface(stack(t), queue(t)):
    PopBack<public>()<transacts><decides>:t
    PeekBack<public>()<transacts><decides>:t


# Combined view for linked_list: path graph + LIFO + FIFO. A parametric
# class takes one parametric parent safely, so the combining happens here.
list_view<public>(t:type) := interface(graph(t), stack(t), queue(t)):


priority_queue<public>(t:type) := interface(sized):
    Insert<public>(V:t)<transacts>:void
    PopMin<public>()<transacts><decides>:t
    PeekMin<public>()<transacts><decides>:t


# Estimated remaining cost between two node values. Must be admissible
# (never overestimate) or A* may return a non-optimal path.
path_heuristic<public>(t:type) := interface:
    EstimateFor<public>(FromValue:t, GoalValue:t)<transacts>:float


# Strict failable less-than, the comparator shape used by avl_tree,
# binary_heap and the sorting extensions in Containers.Ops.
comparator<public>(t:type) := type{_(:t, :t)<transacts><decides>:void}

# Failable equality, injected where a member can't constrain the class's t
# to comparable (linked_list.IndexOf) and closures can't capture V.
equality<public>(t:type) := type{_(:t, :t)<transacts><decides>:void}


# ---------------------------------------------------------------------------
# Containers: implementations
# ---------------------------------------------------------------------------

Containers<public> := module:

    # --- Linked list ---------------------------------------------------------
    # Cycles prevented by encapsulation: Next is internal-write and no list
    # op links to an existing node. ToArray is total; a chain/Size mismatch
    # is a broken invariant (Err tier), not a data fact. list_node is
    # <unique> so nodes compare by identity.

    list_node<public>(t:type) := class<unique>(graph_node(t)):
        Value<public>:t
        var<internal> Next<public>:?list_node(t) = false

        GetValue<override>()<transacts>:t = Value

        Successors<override>()<transacts>:[]graph_node(t) =
            if (N := Next?):
                GN:graph_node(t) = N
                array{GN}
            else:
                array{}


    linked_list<public>(t:type) := class(list_view(t)):

        var<internal> Head<public>:?list_node(t) = false
        var<internal> Tail<public>:?list_node(t) = false
        var<internal> Size<public>:int = 0

        IsEmpty<public>()<reads><decides>:void =
            not Head?

        First<public>()<reads><decides>:t =
            Head?.Value

        Last<public>()<reads><decides>:t =
            Tail?.Value

        Get<public>(Index:int)<transacts><decides>:t =
            NodeAt[Index].Value

        PushFront<public>(V:t)<transacts>:void =
            New := list_node(t){Value := V, Next := Head}
            set Head = option{New}
            if (not Tail?):
                set Tail = option{New}
            set Size += 1

        PushBack<public>(V:t)<transacts>:void =
            New := list_node(t){Value := V}
            if (T := Tail?):
                set T.Next = option{New}
            else:
                set Head = option{New}
            set Tail = option{New}
            set Size += 1

        # Fails on empty. Mutations roll back on failure.
        PopFront<public>()<transacts><decides>:t =
            N := Head?
            set Head = N.Next
            if (not Head?):
                set Tail = false
            set Size -= 1
            N.Value

        # Valid range 0..Size. 0 prepends, Size appends.
        InsertAt<public>(Index:int, V:t)<transacts><decides>:void =
            if (Index = 0):
                PushFront(V)
            else if (Index = Size):
                PushBack(V)
            else:
                Prev := NodeAt[Index - 1]
                New := list_node(t){Value := V, Next := Prev.Next}
                set Prev.Next = option{New}
                set Size += 1

        RemoveAt<public>(Index:int)<transacts><decides>:t =
            if (Index = 0):
                PopFront[]
            else:
                Prev := NodeAt[Index - 1]
                Target := Prev.Next?
                set Prev.Next = Target.Next
                if (not Target.Next?):
                    set Tail = option{Prev}
                set Size -= 1
                Target.Value

        Clear<public>()<transacts>:void =
            set Head = false
            set Tail = false
            set Size = 0

        # stack(t), the front is the top
        Push<override>(V:t)<transacts>:void = PushFront(V)
        Pop<override>()<transacts><decides>:t = PopFront[]
        Peek<override>()<transacts><decides>:t = Head?.Value

        # queue(t), in at the back and out at the front
        Enqueue<override>(V:t)<transacts>:void = PushBack(V)
        Dequeue<override>()<transacts><decides>:t = PopFront[]
        Front<override>()<transacts><decides>:t = Head?.Value

        # sized (via stack and queue)
        Count<override>()<transacts>:int = Size

        # graph(t)
        NodeCount<override>()<transacts>:int = Size

        Nodes<override>()<transacts>:[]graph_node(t) =
            var Result:[]graph_node(t) = array{}
            var Cursor:?list_node(t) = Head
            var Steps:int = 0
            loop:
                if:
                    N := Cursor?
                    Steps < Size
                then:
                    GN:graph_node(t) = N   # explicit upcast, 3510
                    set Result += array{GN}
                    set Cursor = N.Next
                    set Steps += 1
                else:
                    break
            Result

        # Total. Bounded by Size so a corrupted chain can't hang; on a
        # chain/Size mismatch the invariant broke, fail fast.
        ToArray<public>()<transacts>:[]t =
            var Result:[]t = array{}
            var Cursor:?list_node(t) = Head
            var Steps:int = 0
            loop:
                if:
                    N := Cursor?
                    Steps < Size
                then:
                    set Result += array{N.Value}
                    set Cursor = N.Next
                    set Steps += 1
                else:
                    break
            if (Cursor? or Result.Length <> Size):
                Err("linked_list: chain does not match Size, invariant broken (cycle?)")
            Result

        # Value ops take an equality function: a member can't constrain the
        # class's t to comparable, and closures can't capture V (use IntEq/
        # FloatEq/StringEq below, or your own).

        # Index of the first value where Equal[Value, V]. Fails if absent.
        IndexOf<public>(V:t, Equal:equality(t))<transacts><decides>:int =
            var Cursor:?list_node(t) = Head
            var I:int = 0
            var Result:?int = false
            loop:
                if:
                    N := Cursor?
                    I < Size
                then:
                    if (Equal[N.Value, V]):
                        set Result = option{I}
                        break
                    set I += 1
                    set Cursor = N.Next
                else:
                    break
            Result?

        Contains<public>(V:t, Equal:equality(t))<transacts><decides>:void =
            IndexOf[V, Equal]

        RemoveFirst<public>(V:t, Equal:equality(t))<transacts><decides>:t =
            RemoveAt[IndexOf[V, Equal]]

        AppendAll<public>(Arr:[]t)<transacts>:void =
            for (V : Arr):
                PushBack(V)

        # Floyd tortoise/hare, diagnostic. Member: zero-arg extensions
        # leave t unused in an argument position (3503).
        IsCyclic<public>()<transacts><decides>:void =
            var Cyclic:logic = false
            if (H := Head?):
                var Slow:list_node(t) = H
                var Fast:list_node(t) = H
                loop:
                    if:
                        S := Slow.Next?
                        F := Fast.Next?.Next?
                    then:
                        set Slow = S
                        set Fast = F
                        if (S = F):
                            set Cyclic = true
                            break
                    else:
                        break
            Cyclic?

        # Walks at most Index steps, terminates regardless of structure.
        NodeAt<internal>(Index:int)<transacts><decides>:list_node(t) =
            Index >= 0
            var Cursor:?list_node(t) = Head
            var I:int = 0
            var Result:?list_node(t) = false
            loop:
                if (N := Cursor?):
                    if (I = Index):
                        set Result = option{N}
                        break
                    set I += 1
                    set Cursor = N.Next
                else:
                    break
            Result?

    # --- N-ary tree ------------------------------------------------------------
    # Children are internal-write and AddChild attaches fresh nodes only, so
    # no cycles and no diamonds.

    n_tree_node<public>(t:type) := class<unique>(graph_node(t)):
        Value<public>:t
        var<internal> Children<public>:[]n_tree_node(t) = array{}

        GetValue<override>()<transacts>:t = Value

        Successors<override>()<transacts>:[]graph_node(t) =
            var R:[]graph_node(t) = array{}
            for (C : Children):
                GN:graph_node(t) = C
                set R += array{GN}
            R

        # Creates, attaches and returns a fresh child.
        AddChild<public>(V:t)<transacts>:n_tree_node(t) =
            New := n_tree_node(t){Value := V}
            set Children += array{New}
            New

        # Detach by identity. Fails if C isn't a child of this node.
        RemoveChild<public>(C:n_tree_node(t))<transacts><decides>:void =
            Before := Children.Length
            set Children = for (Existing : Children, not (Existing = C)) { Existing }
            Children.Length = Before - 1

        # Self + descendants, preorder. Member (3502/3552 workarounds).
        CollectSubtree<public>()<transacts>:[]graph_node(t) =
            Self0:graph_node(t) = Self
            var Result:[]graph_node(t) = array{Self0}
            for (C : Children):
                set Result += C.CollectSubtree()
            Result


    n_tree<public>(t:type) := class(tree(t)):

        var<internal> Root<public>:?n_tree_node(t) = false

        # Fails if a root already exists.
        SetRoot<public>(V:t)<transacts><decides>:n_tree_node(t) =
            not Root?
            New := n_tree_node(t){Value := V}
            set Root = option{New}
            New

        Clear<public>()<transacts>:void =
            set Root = false

        # tree(t)
        GetRoot<override>()<transacts><decides>:graph_node(t) =
            Root?

        Nodes<override>()<transacts>:[]graph_node(t) =
            if (R := Root?):
                R.CollectSubtree()
            else:
                array{}

        NodeCount<override>()<transacts>:int =
            Nodes().Length

    # --- Plain binary tree ------------------------------------------------------
    # Shape built manually, no ordering, no balancing. For a self-balancing
    # search tree use avl_tree.

    simple_binary_node<public>(t:type) := class<unique>(binary_node(t)):
        var Value<public>:t
        var<internal> Left<public>:?simple_binary_node(t) = false
        var<internal> Right<public>:?simple_binary_node(t) = false

        GetValue<override>()<transacts>:t = Value

        GetLeft<override>()<transacts><decides>:binary_node(t) = Left?

        GetRight<override>()<transacts><decides>:binary_node(t) = Right?

        Successors<override>()<transacts>:[]graph_node(t) =
            var R2:[]graph_node(t) = array{}
            if (L := Left?):
                GL:graph_node(t) = L
                set R2 += array{GL}
            if (R := Right?):
                GR:graph_node(t) = R
                set R2 += array{GR}
            R2

        # Self + descendants, preorder. Member (3502/3552 workarounds).
        CollectSubtree<public>()<transacts>:[]graph_node(t) =
            Self0:graph_node(t) = Self
            var Result:[]graph_node(t) = array{Self0}
            if (L := Left?):
                set Result += L.CollectSubtree()
            if (R := Right?):
                set Result += R.CollectSubtree()
            Result

        # Create, attach and return a fresh child. Fails if the slot is taken.
        AddLeft<public>(V:t)<transacts><decides>:simple_binary_node(t) =
            not Left?
            New := simple_binary_node(t){Value := V}
            set Left = option{New}
            New

        AddRight<public>(V:t)<transacts><decides>:simple_binary_node(t) =
            not Right?
            New := simple_binary_node(t){Value := V}
            set Right = option{New}
            New

        # Detach and return the subtree. Fails if the slot is empty.
        RemoveLeft<public>()<transacts><decides>:simple_binary_node(t) =
            Removed := Left?
            set Left = false
            Removed

        RemoveRight<public>()<transacts><decides>:simple_binary_node(t) =
            Removed := Right?
            set Right = false
            Removed


    simple_binary_tree<public>(t:type) := class(binary_tree(t)):

        var<internal> Root<public>:?simple_binary_node(t) = false

        # Fails if a root already exists.
        SetRoot<public>(V:t)<transacts><decides>:simple_binary_node(t) =
            not Root?
            New := simple_binary_node(t){Value := V}
            set Root = option{New}
            New

        Clear<public>()<transacts>:void =
            set Root = false

        # binary_tree(t)
        GetRoot<override>()<transacts><decides>:graph_node(t) = Root?

        GetBinaryRoot<override>()<transacts><decides>:binary_node(t) = Root?

        Nodes<override>()<transacts>:[]graph_node(t) =
            if (R := Root?):
                R.CollectSubtree()
            else:
                array{}

        NodeCount<override>()<transacts>:int =
            Nodes().Length

    # --- AVL tree ----------------------------------------------------------------
    # Self-balancing BST. No ordering constraint exists in Verse, so the
    # order is injected: Less is a failable strict less-than field.
    #     T := avl_tree(int){Less := IntLess}

    avl_node<public>(t:type) := class<unique>(binary_node(t)):
        var Value<public>:t
        var<internal> Left<public>:?avl_node(t) = false
        var<internal> Right<public>:?avl_node(t) = false
        # Height of the subtree rooted here. Cached; maintained by the tree.
        var<internal> Height<public>:int = 1

        GetValue<override>()<transacts>:t = Value

        GetLeft<override>()<transacts><decides>:binary_node(t) = Left?

        GetRight<override>()<transacts><decides>:binary_node(t) = Right?

        Successors<override>()<transacts>:[]graph_node(t) =
            var R2:[]graph_node(t) = array{}
            if (L := Left?):
                GL:graph_node(t) = L
                set R2 += array{GL}
            if (R := Right?):
                GR:graph_node(t) = R
                set R2 += array{GR}
            R2

        # Self + descendants, preorder. Member (3502/3552 workarounds).
        CollectSubtree<public>()<transacts>:[]graph_node(t) =
            Self0:graph_node(t) = Self
            var Result:[]graph_node(t) = array{Self0}
            if (L := Left?):
                set Result += L.CollectSubtree()
            if (R := Right?):
                set Result += R.CollectSubtree()
            Result


    avl_tree<public>(t:type) := class(binary_tree(t)):

        # Strict less-than. Equal means neither direction succeeds; the
        # tree stores no duplicates.
        Less<public>:type{_(:t, :t)<transacts><decides>:void}

        var<internal> Root<public>:?avl_node(t) = false
        var<internal> Size<public>:int = 0

        # Fails on duplicates. All mutations roll back on failure.
        Insert<public>(V:t)<transacts><decides>:void =
            not Contains[V]
            if (R := Root?):
                set Root = option{InsertNode(R, V)}
            else:
                set Root = option{avl_node(t){Value := V}}
            set Size += 1

        # Fails if V is absent.
        Remove<public>(V:t)<transacts><decides>:void =
            NewRoot := RemoveNode[Root, V]
            set Root = NewRoot
            set Size -= 1

        Contains<public>(V:t)<transacts><decides>:void =
            var Cursor:?avl_node(t) = Root
            var Found:logic = false
            loop:
                if (C := Cursor?):
                    if (Less[V, C.Value]):
                        set Cursor = C.Left
                    else if (Less[C.Value, V]):
                        set Cursor = C.Right
                    else:
                        set Found = true
                        break
                else:
                    break
            Found?

        Min<public>()<transacts><decides>:t =
            FindMin(Root?).Value

        Clear<public>()<transacts>:void =
            set Root = false
            set Size = 0

        # binary_tree(t)
        GetRoot<override>()<transacts><decides>:graph_node(t) = Root?

        GetBinaryRoot<override>()<transacts><decides>:binary_node(t) = Root?

        NodeCount<override>()<transacts>:int = Size

        Nodes<override>()<transacts>:[]graph_node(t) =
            if (R := Root?):
                R.CollectSubtree()
            else:
                array{}

        # --- Internals. Recursive style: each returns the new subtree root. ---

        # V is guaranteed absent (Insert checks first), so this is total.
        InsertNode<internal>(N:avl_node(t), V:t)<transacts>:avl_node(t) =
            if (Less[V, N.Value]):
                if (L := N.Left?):
                    set N.Left = option{InsertNode(L, V)}
                else:
                    set N.Left = option{avl_node(t){Value := V}}
            else:
                if (R := N.Right?):
                    set N.Right = option{InsertNode(R, V)}
                else:
                    set N.Right = option{avl_node(t){Value := V}}
            Rebalance(N)

        # Fails if V isn't in the subtree.
        RemoveNode<internal>(N:?avl_node(t), V:t)<transacts><decides>:?avl_node(t) =
            Node := N?
            if (Less[V, Node.Value]):
                NewL := RemoveNode[Node.Left, V]
                set Node.Left = NewL
                option{Rebalance(Node)}
            else if (Less[Node.Value, V]):
                NewR := RemoveNode[Node.Right, V]
                set Node.Right = NewR
                option{Rebalance(Node)}
            else if (Node.Left?, R := Node.Right?):
                # Two children: adopt the in-order successor's value, then
                # delete it from the right subtree (it exists there).
                Succ := FindMin(R)
                set Node.Value = Succ.Value
                NewR := RemoveNode[Node.Right, Succ.Value]
                set Node.Right = NewR
                option{Rebalance(Node)}
            else if (L := Node.Left?):
                option{L}
            else if (R := Node.Right?):
                option{R}
            else:
                false

        FindMin<internal>(N:avl_node(t))<transacts>:avl_node(t) =
            var Cur:avl_node(t) = N
            loop:
                if (L := Cur.Left?):
                    set Cur = L
                else:
                    break
            Cur

        HeightOf<internal>(N:?avl_node(t))<transacts>:int =
            if (X := N?) then X.Height else 0

        BalanceOf<internal>(N:avl_node(t))<transacts>:int =
            HeightOf(N.Left) - HeightOf(N.Right)

        UpdateHeight<internal>(N:avl_node(t))<transacts>:void =
            set N.Height = 1 + Max(HeightOf(N.Left), HeightOf(N.Right))

        # Restores the AVL invariant at N after a child changed. The
        # unreachable else arms return N unchanged.
        Rebalance<internal>(N:avl_node(t))<transacts>:avl_node(t) =
            UpdateHeight(N)
            B := BalanceOf(N)
            if (B > 1):
                if (L := N.Left?):
                    if (BalanceOf(L) < 0, LR := L.Right?):    # left-right case
                        set N.Left = option{RotateLeft(L, LR)}
                    if (L2 := N.Left?):
                        RotateRight(N, L2)
                    else:
                        N
                else:
                    N
            else if (B < -1):
                if (R := N.Right?):
                    if (BalanceOf(R) > 0, RL := R.Left?):     # right-left case
                        set N.Right = option{RotateRight(R, RL)}
                    if (R2 := N.Right?):
                        RotateLeft(N, R2)
                    else:
                        N
                else:
                    N
            else:
                N

        # X is Y.Left. Returns X as the new subtree root.
        RotateRight<internal>(Y:avl_node(t), X:avl_node(t))<transacts>:avl_node(t) =
            set Y.Left = X.Right
            set X.Right = option{Y}
            UpdateHeight(Y)
            UpdateHeight(X)
            X

        # X is Y.Right.
        RotateLeft<internal>(Y:avl_node(t), X:avl_node(t))<transacts>:avl_node(t) =
            set Y.Right = X.Left
            set X.Left = option{Y}
            UpdateHeight(Y)
            UpdateHeight(X)
            X


    # Ready-made comparators and equalities. Effects match the field types.
    IntLess<public>(A:int, B:int)<transacts><decides>:void = A < B
    FloatLess<public>(A:float, B:float)<transacts><decides>:void = A < B
    IntEq<public>(A:int, B:int)<transacts><decides>:void = A = B
    FloatEq<public>(A:float, B:float)<transacts><decides>:void = A = B
    StringEq<public>(A:string, B:string)<transacts><decides>:void = A = B

    # No string `<` exists on the toolchain: lexicographic, char by char,
    # ranking chars against a reference alphabet (char has no order either).
    # Unlisted chars rank after listed ones.
    StringLess<public>(A:string, B:string)<transacts><decides>:void =
        var Verdict:?logic = false   # unset=undecided
        var I:int = 0
        loop:
            if (CA := A[I], CB := B[I]):
                RA := CharRank(CA)
                RB := CharRank(CB)
                if (RA < RB):
                    set Verdict = option{true}
                    break
                else if (RB < RA):
                    set Verdict = option{false}
                    break
                set I += 1
            else:
                break
        if (V := Verdict?):
            V?
        else:
            A.Length < B.Length   # shared prefix: shorter sorts first

    CharOrder<internal>:string = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz"

    CharRank<internal>(C:char)<transacts>:int =
        first (I -> X : CharOrder, X = C) { I } or CharOrder.Length

    # --- Directed graph -----------------------------------------------------------
    # The unrestricted graph(t): cycles and diamonds are legitimate states,
    # so cycle-sensitive ops are <decides> (contrast linked_list, where a
    # cycle is a broken invariant and Err tier).

    digraph_node<public>(t:type) := class<unique>(graph_node(t)):
        Value<public>:t
        var<internal> Out<public>:[]digraph_node(t) = array{}

        GetValue<override>()<transacts>:t = Value

        Successors<override>()<transacts>:[]graph_node(t) =
            var R:[]graph_node(t) = array{}
            for (S : Out):
                GN:graph_node(t) = S
                set R += array{GN}
            R

        # Breadth-first order of everything reachable from here, self
        # included. Cycles handled via the visited map.
        ReachableNodes<public>()<transacts>:[]digraph_node(t) =
            var Visited:[digraph_node(t)]logic = map{}
            var Order:[]digraph_node(t) = array{Self}
            var I:int = 0
            if (set Visited[Self] = true) {}
            loop:
                if (N := Order[I]):
                    set I += 1
                    for (S : N.Out, not Visited[S]):
                        if (set Visited[S] = true) {}
                        set Order += array{S}
                else:
                    break
            Order


    digraph<public>(t:type) := class(graph(t)):

        var<internal> Members<public>:[]digraph_node(t) = array{}

        AddNode<public>(V:t)<transacts>:digraph_node(t) =
            New := digraph_node(t){Value := V}
            set Members += array{New}
            New

        # Fails if either node isn't a member or the edge already exists.
        AddEdge<public>(From:digraph_node(t), To:digraph_node(t))<transacts><decides>:void =
            IsMember[From]
            IsMember[To]
            not first (E : From.Out, E = To) { E }
            set From.Out += array{To}

        RemoveEdge<public>(From:digraph_node(t), To:digraph_node(t))<transacts><decides>:void =
            first (E : From.Out, E = To) { E }
            set From.Out = for (E : From.Out, not (E = To)) { E }

        IsMember<public>(N:digraph_node(t))<transacts><decides>:void =
            first (M : Members, M = N) { M }

        # graph(t)
        Nodes<override>()<transacts>:[]graph_node(t) =
            var R:[]graph_node(t) = array{}
            for (M : Members):
                GN:graph_node(t) = M
                set R += array{GN}
            R

        NodeCount<override>()<transacts>:int = Members.Length

        # Kahn's algorithm. Fails exactly when the graph is cyclic: a cycle
        # never reaches in-degree 0, so the order comes up short.
        TopologicalSort<public>()<transacts><decides>:[]digraph_node(t) =
            var InDeg:[digraph_node(t)]int = map{}
            for (N : Members):
                if (set InDeg[N] = 0) {}
            for (N : Members):
                for (S : N.Out):
                    if (set InDeg[S] += 1) {}
            # Order doubles as the worklist, I is the read cursor.
            var Order:[]digraph_node(t) = for (N : Members, D := InDeg[N], D = 0) { N }
            var I:int = 0
            loop:
                if (N := Order[I]):
                    set I += 1
                    for (S : N.Out):
                        if (set InDeg[S] -= 1) {}
                        if (D := InDeg[S], D = 0):
                            set Order += array{S}
                else:
                    break
            Order.Length = Members.Length
            Order

        HasCycle<public>()<transacts><decides>:void =
            not TopologicalSort[]

    # --- Weighted directed graph + pathfinding -----------------------------------
    # Non-negative edge costs; the AddEdge invariant licenses Dijkstra/A*.
    # Edges are parallel arrays: a parametric class as a field type of
    # another parametric trips 3509 on construction. Support types are
    # defined BEFORE their users; in-file order matters to the parametric
    # ordering bug even inside one module.

    weighted_node<public>(t:type) := class<unique>(graph_node(t)):
        Value<public>:t
        var<internal> OutTargets<public>:[]weighted_node(t) = array{}
        var<internal> OutCosts<public>:[]float = array{}

        GetValue<override>()<transacts>:t = Value

        Successors<override>()<transacts>:[]graph_node(t) =
            var R:[]graph_node(t) = array{}
            for (S : OutTargets):
                GN:graph_node(t) = S
                set R += array{GN}
            R


    # A* with no guidance; always admissible. Makes FindShortestPath = Dijkstra.
    zero_heuristic<public>(t:type) := class(path_heuristic(t)):
        EstimateFor<override>(FromValue:t, GoalValue:t)<transacts>:float = 0.0

    path_result<public>(t:type) := class:
        # Start..Goal inclusive.
        PathNodes<public>:[]weighted_node(t)
        TotalCost<public>:float

    # Frontier entry: G = cost from start, F = G + heuristic (the priority).
    path_entry<public>(t:type) := class:
        Node<public>:weighted_node(t)
        G<public>:float
        F<public>:float

    # Min-heap on F. Self-contained rather than binary_heap(path_entry(t)):
    # a parametric function value for Less is the BPVM danger zone, and the
    # priority is always float here.
    path_frontier<public>(t:type) := class:

        var<internal> Items<public>:[]path_entry(t) = array{}

        Push<public>(E:path_entry(t))<transacts>:void =
            set Items += array{E}
            var I:int = Items.Length - 1
            loop:
                if:
                    I > 0
                    P := Floor((I - 1) / 2)
                    Child := Items[I]
                    Par := Items[P]
                    Child.F < Par.F
                then:
                    if (set Items[P] = Child) {}
                    if (set Items[I] = Par) {}
                    set I = P
                else:
                    break

        # Fails when empty.
        Pop<public>()<transacts><decides>:path_entry(t) =
            Top := Items[0]
            Last := Items[Items.Length - 1]
            Shrunk := Items.Slice[0, Items.Length - 1]   # hoisted, 3502
            set Items = Shrunk
            if (Items.Length > 0):
                if (set Items[0] = Last) {}
                SiftDown()
            Top

        SiftDown<internal>()<transacts>:void =
            var I:int = 0
            loop:
                var Smallest:int = I
                if (L := Items[2*I + 1], S := Items[Smallest], L.F < S.F):
                    set Smallest = 2*I + 1
                if (R := Items[2*I + 2], S := Items[Smallest], R.F < S.F):
                    set Smallest = 2*I + 2
                if (Smallest = I):
                    break
                if (A := Items[I], B := Items[Smallest]):
                    if (set Items[I] = B) {}
                    if (set Items[Smallest] = A) {}
                set I = Smallest


    weighted_digraph<public>(t:type) := class(graph(t)):

        var<internal> Members<public>:[]weighted_node(t) = array{}

        AddNode<public>(V:t)<transacts>:weighted_node(t) =
            New := weighted_node(t){Value := V}
            set Members += array{New}
            New

        # Fails on negative cost, non-members, or duplicate edge.
        AddEdge<public>(From:weighted_node(t), To:weighted_node(t), Cost:float)<transacts><decides>:void =
            Cost >= 0.0
            IsMember[From]
            IsMember[To]
            not first (E : From.OutTargets, E = To) { E }
            set From.OutTargets += array{To}
            set From.OutCosts += array{Cost}

        # Both directions, same cost.
        AddBidirectional<public>(A:weighted_node(t), B:weighted_node(t), Cost:float)<transacts><decides>:void =
            AddEdge[A, B, Cost]
            AddEdge[B, A, Cost]

        RemoveEdge<public>(From:weighted_node(t), To:weighted_node(t))<transacts><decides>:void =
            Index := first (I -> E : From.OutTargets, E = To) { I }
            NewTargets := From.OutTargets.RemoveElement[Index]
            NewCosts := From.OutCosts.RemoveElement[Index]
            set From.OutTargets = NewTargets
            set From.OutCosts = NewCosts

        GetCost<public>(From:weighted_node(t), To:weighted_node(t))<transacts><decides>:float =
            Index := first (I -> E : From.OutTargets, E = To) { I }
            From.OutCosts[Index]

        IsMember<public>(N:weighted_node(t))<transacts><decides>:void =
            first (M : Members, M = N) { M }

        # graph(t)
        Nodes<override>()<transacts>:[]graph_node(t) =
            var R:[]graph_node(t) = array{}
            for (M : Members):
                GN:graph_node(t) = M
                set R += array{GN}
            R

        NodeCount<override>()<transacts>:int = Members.Length

        # --- Pathfinding. Members, not extensions: t-generic extensions
        # over a class with t-typed var fields trip 3552. Dijkstra is A*
        # with the zero heuristic.

        # Cheapest path by edge costs alone.
        FindShortestPath<public>(Start:weighted_node(t), Goal:weighted_node(t))<transacts><decides>:path_result(t) =
            FindPathWith[Start, Goal, zero_heuristic(t){}]

        # A*. Fails if Goal is unreachable from Start or either isn't a
        # member. Lazy deletion: nodes may be pushed several times, stale
        # entries are skipped on pop instead of decrease-key. H must be
        # admissible or the path may be non-optimal.
        FindPathWith<public>(Start:weighted_node(t), Goal:weighted_node(t), H:path_heuristic(t))<transacts><decides>:path_result(t) =
            IsMember[Start]
            IsMember[Goal]

            var Best:[weighted_node(t)]float = map{}
            var CameFrom:[weighted_node(t)]weighted_node(t) = map{}
            Frontier := path_frontier(t){}

            if (set Best[Start] = 0.0) {}
            Frontier.Push(path_entry(t){Node := Start, G := 0.0, F := H.EstimateFor(Start.Value, Goal.Value)})

            var Found:logic = false
            loop:
                if (E := Frontier.Pop[]):
                    if (BestG := Best[E.Node], E.G > BestG):
                        block {} # stale entry, already expanded cheaper
                    else if (E.Node = Goal):
                        set Found = true
                        break
                    else:
                        for (I -> Target : E.Node.OutTargets, Cost := E.Node.OutCosts[I]):
                            NewG := E.G + Cost
                            if (Old := Best[Target], NewG >= Old):
                                block {} # not an improvement
                            else:
                                if (set Best[Target] = NewG) {}
                                if (set CameFrom[Target] = E.Node) {}
                                Frontier.Push(path_entry(t){
                                    Node := Target,
                                    G := NewG,
                                    F := NewG + H.EstimateFor(Target.Value, Goal.Value)})
                else:
                    break # frontier exhausted, Goal unreachable

            Found?
            ReconstructPath[CameFrom, Start, Goal]

        # Walk CameFrom back from Goal. Bounded by NodeCount; the chain is
        # built by the search, so outrunning it is an algorithm bug (Err).
        ReconstructPath<internal>(CameFrom:[weighted_node(t)]weighted_node(t), Start:weighted_node(t), Goal:weighted_node(t))<transacts><decides>:path_result(t) =
            var PathNodes:[]weighted_node(t) = array{Goal}
            var Cur:weighted_node(t) = Goal
            var Steps:int = 0
            loop:
                if (Cur = Start):
                    break
                if (P := CameFrom[Cur], Steps < NodeCount()):
                    set PathNodes = array{P} + PathNodes
                    set Cur = P
                    set Steps += 1
                else:
                    Err("pathfinding: came-from chain broke, algorithm bug")
            Total := TotalCostOf[PathNodes]
            path_result(t){PathNodes := PathNodes, TotalCost := Total}

        TotalCostOf<internal>(PathNodes:[]weighted_node(t))<transacts><decides>:float =
            var Total:float = 0.0
            for:
                I -> N : PathNodes
                Next := PathNodes[I + 1]
                Cost := GetCost[N, Next]
            do:
                set Total += Cost
            Total

    # --- Binary min-heap ---------------------------------------------------------
    # Array-backed, so deliberately NOT a binary_tree(t): no node objects,
    # no identity. Comparator injection like avl_tree; duplicates allowed.

    binary_heap<public>(t:type) := class(priority_queue(t)):

        # Strict less-than. IntLess/FloatLess/StringLess work here.
        Less<public>:type{_(:t, :t)<transacts><decides>:void}

        var<internal> Items<public>:[]t = array{}

        Count<override>()<transacts>:int = Items.Length

        Insert<override>(V:t)<transacts>:void =
            set Items += array{V}
            SiftUp(Items.Length - 1)

        PeekMin<override>()<transacts><decides>:t = Items[0]

        PopMin<override>()<transacts><decides>:t =
            Top := Items[0]
            Last := Items[Items.Length - 1]
            Shrunk := Items.Slice[0, Items.Length - 1]   # hoisted, 3502
            set Items = Shrunk
            if (Items.Length > 0):
                if (set Items[0] = Last) {}
                SiftDown()
            Top

        SiftUp<internal>(StartIndex:int)<transacts>:void =
            var I:int = StartIndex
            loop:
                if:
                    I > 0
                    P := Floor((I - 1) / 2)
                    Child := Items[I]
                    Par := Items[P]
                    Less[Child, Par]
                then:
                    if (set Items[P] = Child) {}
                    if (set Items[I] = Par) {}
                    set I = P
                else:
                    break

        SiftDown<internal>()<transacts>:void =
            var I:int = 0
            loop:
                var Smallest:int = I
                if (LV := Items[2*I + 1], SV := Items[Smallest], Less[LV, SV]):
                    set Smallest = 2*I + 1
                if (RV := Items[2*I + 2], SV := Items[Smallest], Less[RV, SV]):
                    set Smallest = 2*I + 2
                if (Smallest = I):
                    break
                if (A := Items[I], B := Items[Smallest]):
                    if (set Items[I] = B) {}
                    if (set Items[Smallest] = A) {}
                set I = Smallest

    # --- Array-backed deque --------------------------------------------------------
    # Arrays are values, writes copy; fine at gameplay sizes, use
    # linked_list when fronts must be cheap.

    array_deque<public>(t:type) := class(deque(t)):

        var<internal> Items<public>:[]t = array{}

        Count<override>()<transacts>:int = Items.Length

        # stack(t), front is the top
        Push<override>(V:t)<transacts>:void =
            set Items = array{V} + Items

        Pop<override>()<transacts><decides>:t =
            First := Items[0]
            Shrunk := Items.Slice[1]   # hoisted, 3502
            set Items = Shrunk
            First

        Peek<override>()<transacts><decides>:t = Items[0]

        # queue(t), in at the back and out at the front
        Enqueue<override>(V:t)<transacts>:void =
            set Items += array{V}

        Dequeue<override>()<transacts><decides>:t = Pop[]

        Front<override>()<transacts><decides>:t = Items[0]

        # deque(t)
        PopBack<override>()<transacts><decides>:t =
            Last := Items[Items.Length - 1]
            Shrunk := Items.Slice[0, Items.Length - 1]
            set Items = Shrunk
            Last

        PeekBack<override>()<transacts><decides>:t = Items[Items.Length - 1]

        ToArray<public>()<reads>:[]t = Items

    # --- Union-find ------------------------------------------------------------------
    # Union by rank + path compression. Class-level constraint: the parent
    # map needs t as a map key.

    disjoint_set<public>(t:subtype(comparable)) := class:

        var<internal> Parent<public>:[t]t = map{}
        var<internal> Rank<public>:[t]int = map{}

        # Idempotent. New elements start as their own set.
        Add<public>(V:t)<transacts>:void =
            if (not Parent[V]):
                if (set Parent[V] = V) {}
                if (set Rank[V] = 0) {}

        IsTracked<public>(V:t)<reads><decides>:void =
            Parent[V]

        # Representative of V's set. Fails if V was never added.
        # Compresses the walked path afterwards.
        Find<public>(V:t)<transacts><decides>:t =
            Root := FindRoot[V]
            var Cur:t = V
            loop:
                if (P := Parent[Cur], not (P = Cur)):
                    if (set Parent[Cur] = Root) {}
                    set Cur = P
                else:
                    break
            Root

        # Merge the sets containing A and B. No-op success if already
        # merged. Fails if either was never added.
        Union<public>(A:t, B:t)<transacts><decides>:void =
            RootA := Find[A]
            RootB := Find[B]
            if (not (RootA = RootB)):
                RankA := Rank[RootA] or 0
                RankB := Rank[RootB] or 0
                if (RankA < RankB):
                    if (set Parent[RootA] = RootB) {}
                else if (RankB < RankA):
                    if (set Parent[RootB] = RootA) {}
                else:
                    if (set Parent[RootB] = RootA) {}
                    if (set Rank[RootA] += 1) {}

        SameSet<public>(A:t, B:t)<transacts><decides>:void =
            Find[A] = Find[B]

        FindRoot<internal>(V:t)<transacts><decides>:t =
            Parent[V]   # membership gate
            var Cur:t = V
            var Result:?t = false
            loop:
                if (P := Parent[Cur]):
                    if (P = Cur):
                        set Result = option{Cur}
                        break
                    set Cur = P
                else:
                    break
            Result? or Err("disjoint_set: parent chain broke, invariant violated")

    # =========================================================================
    # Ops: extensions over the containers (a module BELOW their definitions)
    # =========================================================================

    Ops<public> := module:

        # --- Interface-generic algorithms -------------------------------------
        # Work on every implementor. Names unique across receiver types
        # (NodeDepth vs TreeDepth): extension overloading by receiver collides.

        (G:graph(t) where t:type).Values<public>()<transacts>:[]t =
            for (N : G.Nodes()):
                N.GetValue()

        # Height of the subtree below N, counting N. Assumes acyclic.
        (N:graph_node(t) where t:type).NodeDepth<public>()<transacts>:int =
            var Best:int = 0
            for (C : N.Successors()):
                D := C.NodeDepth()
                if (D > Best):
                    set Best = D
            1 + Best

        (T:tree(t) where t:type).TreeDepth<public>()<transacts>:int =
            if (R := T.GetRoot[]):
                R.NodeDepth()
            else:
                0

        # Left, self, right. On a binary search tree this is sorted order.
        (N:binary_node(t) where t:type).InOrderValues<public>()<transacts>:[]t =
            LeftVals := if (L := N.GetLeft[]) then L.InOrderValues() else array{}
            RightVals := if (R := N.GetRight[]) then R.InOrderValues() else array{}
            LeftVals + array{N.GetValue()} + RightVals

        (T:binary_tree(t) where t:type).InOrder<public>()<transacts>:[]t =
            if (R := T.GetBinaryRoot[]):
                R.InOrderValues()
            else:
                array{}

        # --- Sorting and searching over []t -----------------------------------
        # Merge sort: stable, O(n log n), fits value arrays (slice/rebuild
        # beats in-place swaps). Comparators are the root-module
        # comparator(t) shape; IntLess/FloatLess/StringLess from the parent
        # module work directly.

        (Arr:[]t where t:type).SortedBy<public>(Less:comparator(t))<transacts>:[]t =
            if:
                Arr.Length > 1
                Mid := Floor(Arr.Length / 2)
                L := Arr.Slice[0, Mid]
                R := Arr.Slice[Mid]
            then:
                MergeBy(L.SortedBy(Less), R.SortedBy(Less), Less)
            else:
                Arr

        # Stable: ties take from the left run.
        MergeBy<internal>(A:[]t, B:[]t, Less:comparator(t) where t:type)<transacts>:[]t =
            var Result:[]t = array{}
            var I:int = 0
            var J:int = 0
            loop:
                if (X := A[I], Y := B[J]):
                    if (Less[Y, X]):
                        set Result += array{Y}
                        set J += 1
                    else:
                        set Result += array{X}
                        set I += 1
                else if (X := A[I]):
                    set Result += array{X}
                    set I += 1
                else if (Y := B[J]):
                    set Result += array{Y}
                    set J += 1
                else:
                    break
            Result

        # Index of V in a SORTED array. Fails if absent. Equality is derived
        # from the comparator: neither Less direction succeeds.
        (Arr:[]t where t:type).BinarySearchBy<public>(V:t, Less:comparator(t))<transacts><decides>:int =
            var Lo:int = 0
            var Hi:int = Arr.Length - 1
            var Found:?int = false
            loop:
                if (Lo > Hi):
                    break
                if:
                    Mid := Floor((Lo + Hi) / 2)
                    X := Arr[Mid]
                then:
                    if (Less[X, V]):
                        set Lo = Mid + 1
                    else if (Less[V, X]):
                        set Hi = Mid - 1
                    else:
                        set Found = option{Mid}
                        break
                else:
                    break # unreachable, Lo..Hi stays in bounds
            Found?

        (Arr:[]t where t:type).IsSortedBy<public>(Less:comparator(t))<transacts><decides>:void =
            Violations := for (I -> X : Arr, Y := Arr[I + 1], Less[Y, X]) { I }
            Violations.Length = 0

        # Monomorphic sugar. Distinct names: same-named extensions on
        # []int/[]float/[]string are ambiguous at an empty-array call site
        # (3532).
        (Arr:[]int).SortedInts<public>()<transacts>:[]int = Arr.SortedBy(IntLess)
        (Arr:[]float).SortedFloats<public>()<transacts>:[]float = Arr.SortedBy(FloatLess)
        (Arr:[]string).SortedStrings<public>()<transacts>:[]string = Arr.SortedBy(StringLess)

        # linked_list value ops (IndexOf/Contains/RemoveFirst/AppendAll) are
        # MEMBERS taking an equality(t) argument: t-generic extensions over
        # a class with t-typed var fields (Head/Tail/Next) trip 3552. Array
        # to list: linked_list(int){}.AppendAll(Arr).

        # Dijkstra / A* live as MEMBERS on weighted_digraph (see above):
        # t-generic extensions over classes with t-typed var fields trip
        # 3552. Custom heuristics implement path_heuristic(t):
        #     manhattan := class(path_heuristic(grid_pos)):
        #         EstimateFor<override>(A:grid_pos, B:grid_pos)<transacts>:float = ...
