using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }


# Drop on any entity; runs the demo scripts once at simulation start.
# Each script prints an "expect: ..." line first, so the log is
# self-checking: every minilang> line should match the expectation above it.
minilang_demo_component<public> := class<final_super>(component):

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()

        Print("--- minilang 1: hello, arithmetic, precedence. expect: hi then 7 then 9")
        R1 := RunMinilang("print(\"hi\"); print(1 + 2 * 3); print((1 + 2) * 3);")

        Print("--- minilang 2: while + assignment. expect: 0 1 2 3 4 then done")
        R2 := RunMinilang("let i = 0; while i < 5 do print(i); i = i + 1; end print(\"done\");")

        Print("--- minilang 3: fizzbuzz 1..15, strings via +")
        R3 := RunMinilang(FizzBuzz())

        Print("--- minilang 4: recursion. expect: 144")
        R4 := RunMinilang("let fib = fn(n) do if n < 2 do return n; end return fib(n - 1) + fib(n - 2); end; print(fib(12));")

        Print("--- minilang 5: closures. expect: 1 2 3 then 1")
        R5 := RunMinilang(Counters())

        Print("--- minilang 6: higher-order fn. expect: 12")
        R6 := RunMinilang("let twice = fn(f, x) do return f(f(x)); end; let add3 = fn(x) do return x + 3; end; print(twice(add3, 6));")

        Print("--- minilang 7: lex error. expect one lex error line, no crash")
        R7 := RunMinilang("let x = 1 ? 2;")

        Print("--- minilang 8: parse error. expect one parse error line")
        R8 := RunMinilang("let = 5;")

        Print("--- minilang 9: runtime error, unknown name. expect one runtime error line")
        R9 := RunMinilang("print(nope);")

        Print("--- minilang 10: div by zero. expect one runtime error line")
        R10 := RunMinilang("print(1 / 0);")

        Print("--- minilang 11: infinite loop. expect one runtime error line (fuel), not a hang")
        R11 := RunMinilang("while true do end")

        Print("--- minilang 12: deep recursion. expect one runtime error line (depth cap), not a VM kill")
        R12 := RunMinilang("let f = fn(n) do return f(n + 1); end; print(f(0));")

        Print("--- minilang demo finished")

    FizzBuzz<internal>()<transacts>:string =
        "let i = 1; while i <= 15 do if i / 15 * 15 == i do print(\"fizzbuzz\"); else if i / 3 * 3 == i do print(\"fizz\"); else if i / 5 * 5 == i do print(\"buzz\"); else print(i); end end end i = i + 1; end"

    Counters<internal>()<transacts>:string =
        "let make_counter = fn() do let count = 0; return fn() do count = count + 1; return count; end; end; let c = make_counter(); print(c()); print(c()); print(c()); let d = make_counter(); print(d());"
