* [What is CIRCT?](#what-is-circt)
* [Tutorial Part 1: Basics](#tutorial-part-1-basics)
    * [1.1 Install CIRCT Tools](#11-install-circt-tools)
    * [1.2 Compiling a Design](#12-compiling-a-design)
    * [1.3 Optimizing a Design](#13-optimizing-a-design)
    * [1.4 Verifying a Transformation](#14-verifying-a-transformation)
    * [1.5 EDA Integration Generating Verilog](#15-eda-integration-generating-verilog)
* [Tutorial Part 2: Datapath Synthesis](#tutorial-part-2-datapath-synthesis)
	* [2.1 Datapath Dialect](#21-datapath-dialect)
	* [2.2 Synthesizing a Design](#22-synthesizing-a-design)
	* [2.3 EDA Integration Generating AIGER](#23-eda-integration-generating-aiger)
* [Command Glossary](#command-glossary)
* [Authors](#authors)

---
# What is CIRCT?

[CIRCT (Circuit IR Compilers and Tools)](https://circt.llvm.org/) is an open-source compiler infrastructure project for digital hardware design.
It provides reusable compiler dialects, optimizations, and passes built on MLIR.
CIRCT enables hardware designers and compiler developers to express, transform, and generate circuit representations for FPGAs, ASICs, and other digital systems.

---
### Key Features:
- A hardware-centered IR and dialect ecosystem for digital circuit design.
- Reusable passes for lowering, verification, and code generation.
- Integration with [MLIR](https://mlir.llvm.org/) and LLVM for compiler-based hardware flows.
- Support for multiple input formats and backends, including FIRRTL, HW, and system-level representations.

---
### CIRCT Inspiration
- LLVM and [MLIR](https://mlir.llvm.org/): using compiler infrastructure patterns to make hardware transformation passes composable.
- Hardware description languages like [Chisel](https://www.chisel-lang.org/).
- The desire to unify hardware and software compiler techniques in a shared framework.

CIRCT aims to make hardware compiler development more agile, enabling researchers and engineers to experiment with new optimizations and hardware dialects.

---
# Tutorial Part 1: Basics

1. Install CIRCT tools in a docker image.
2. Compile a hardware design to CIRCT IR.
3. Apply CIRCT optimization passes.
4. Generate an output circuit for verification/implementation.

---
## 1.1 Install CIRCT Tools 
```
git clone https://github.com/cowardsa/CIRCT_TUTORIAL_2026
cd CIRCT_TUTORIAL_2026
```
Then either:
* Docker Option (may need sudo)
```
docker build -t circt .
docker run -it circt
```
* VSCode + Dev Container Option
```
code .
Ctrl+Shift+P
Dev Containers: Reopen in Container
```

---

From within the docker container you should now be able to use CIRCT's pre-built tools.
`circt-opt --version` should produce:
```
LLVM (http://llvm.org/):
  LLVM version 23.0.0git
  Optimized build.
CIRCT firtool-1.147.0
```

---
## 1.2 Compiling a Design

```verilog
// rtl/fma.sv
module fma (
    input  wire [3:0] a,
    input  wire [3:0] b,
    input  wire [3:0] c,
    output wire [8:0] d
);
    assign d = (a * b) + (c * 1'd1);

endmodule
```

System Verilog feature support in `circt-verilog` documented at [sv-tests](https://chipsalliance.github.io/sv-tests-results/). This is an ongoing effort.

---
```
circt-verilog rtl/fma.sv
```

```mlir
module {
  hw.module @fma(in %a: i4, in %b: i4, in %c: i4, out d: i9){
    %c0_i5 = hw.constant 0 : i5
    %0 = comb.concat %c0_i5, %a : i5, i4
    %1 = comb.concat %c0_i5, %b : i5, i4
    %2 = comb.mul %0, %1 : i9
    %3 = comb.concat %c0_i5, %c : i5, i4
    %4 = comb.add %2, %3 : i9
    hw.output %4 : i9
  }
}
```

- **comb dialect**: combinational logic operations e.g., add, xor, mux
- **hw dialect**: structural hardware descriptions e.g., modules, ports, instances
- The mnemonic before the dot names the dialect (`comb.add`, `hw.module`); `i4`, `i5`, etc. are types from MLIR's builtin dialect, which is implicit in the IR.

--- 
To save the output to a file:
```
circt-verilog rtl/fma.sv -o rtl/fma.mlir
```


---

## 1.3 Optimizing a Design
* CIRCT is a compiler stack - it's all **passes**! 
* These incantations look scary but in many cases they are hidden behind nice tools 
* LLMs are good at CIRCT
---
### `circt-opt`

```
circt-opt <in.mlir> --<pass 1> ... -o <out.mlir>
```

* **comb-int-range-narrowing** - operator width reduction based on an interval analysis (e.g., `a[3:0]*b[3:0]`  fits in 8-bits rather than 9)
* **canonicalize** - basic hardware optimizations strictly improving area and delay e.g., zext(res[7:0])[7:0] -> res[7:0]

---
```
circt-opt rtl/fma.mlir --comb-int-range-narrowing \
                       --canonicalize             \
                       -o rtl/fma_opt.mlir
```

```mlir
module {
  hw.module @fma(in %a: i4, in %b: i4, in %c: i4, out d:i9){
    %false = hw.constant false
    %c0_i4 = hw.constant 0 : i4
    %0 = comb.concat %c0_i4, %a : i4, i4
    %1 = comb.concat %c0_i4, %b : i4, i4
    %2 = comb.mul %0, %1 : i8
    %3 = comb.concat %c0_i4, %c : i4, i4
    %4 = comb.add %2, %3 : i8
    %5 = comb.concat %false, %4 : i1, i8
    hw.output %5 : i9
  }
}
```

---
### Exercise 1 (2 mins)
Try swapping the order of the passes in the command? How does the output change?

---
## 1.4 Verifying a Transformation
Of course, you don't trust research tools... 
(And of course, industrial tools are always exact... except when AMD/Xilinx documents [IEEE-754 partial compliance](https://docs.amd.com/r/en-US/ug1399-vitis-hls/Floats-and-Doubles) and [deviations](https://docs.amd.com/api/khub/documents/ym1A7qsltTGP_saZFTrikQ/content).)

Fortunately, we provide a way to mark our own homework using a logical equivalence checker called `circt-lec`

---
### `circt-lec`

General:
 ```
circt-lec --c1 <module_name_1> <design_1.mlir> 
           --c2 <module_name_2> <design_2.mlir>
 ```

Our example: 
```
circt-lec --c1 fma rtl/fma.mlir \
          --c2 fma rtl/fma_opt.mlir
```

Which should return: `c1 == c2`

---
### How does `circt-lec` work? 
1. It constructs a miter circuit (a wrapper comparing both designs) that instantiates each design and asserts identical outputs when supplied with identical inputs.
2. The miter circuit and both modules are lowered to SMT (Satisfiability Modulo Theories).
3. The SMT query is solved by Z3: `unsat` means no counterexample exists, so the circuits are equivalent; `sat` means Z3 found an input where they differ.

---
### Aside Bounded Model Checking
CIRCT has support for [bounded model checking](https://circt.llvm.org/docs/Tools/circt-bmc/) through `circt-bmc`, which we will not cover in this tutorial.

---
### Exercise 2 (5 mins)
Copy `rtl/fma_opt.mlir` to a new file then break it by editing (vim & nano installed)  and check that `circt-lec` returns `c1 != c2`? 

Unfortunately, we can't generate a counter-example easily right now.

---
## 1.5 EDA Integration Generating Verilog
`firtool` is CIRCT's tool for emitting Verilog from CIRCT IR.
A classic CIRCT design flow is:
1. Parse a design and generate CIRCT IR
2. Optimize the CIRCT IR and verify the correctness
3. Generate Verilog to hand-off to downstream tools (e.g., Synopsys/Cadence/Altera/Xilinx)

---
```
firtool rtl/fma_opt.mlir
```

```verilog
// Generated by CIRCT firtool-1.147.0
module fma(     // rtl/fma_opt.mlir:2:3
  input  [3:0] a,       // rtl/fma_opt.mlir:2:21
               b,       // rtl/fma_opt.mlir:2:33
               c,       // rtl/fma_opt.mlir:2:45
  output [8:0] d        // rtl/fma_opt.mlir:2:58
);

  assign d = {1'h0, {4'h0, a} * {4'h0, b} + {4'h0, c}}; // rtl/fma_opt.mlir:3:14, :4:14, :5:10, :6:10, :7:10, :8:10, :9:10, :10:10, :11:5
endmodule
```

---
### Exercise 3 (5 mins)
1. Modify the command above to save the verilog to a file?
2. Use `circt-verilog` to compile the generated verilog back to CIRCT IR?
3. Use `circt-lec` to verify the round-trip preserved equivalence?

---
# Tutorial Part 2: Datapath Synthesis
[Back to the slides](TODO)!
1. Convert to `datapath`
2. Logic synthesis
3. Generate AIGER format

---
## 2.1 Datapath Dialect
```
circt-verilog rtl/dot_product.sv -o rtl/dot_product.mlir
```

```mlir
module {
  hw.module @dot_product(in %a : i8, in %b : i8, in %c : i8, in %d : i8, out out : i16) {
    %c0_i8 = hw.constant 0 : i8
    %0 = comb.concat %c0_i8, %a : i8, i8 // zext(a)
    %1 = comb.concat %c0_i8, %b : i8, i8 // zext(b)
    %2 = comb.mul %0, %1 : i16 // ab = zext(a)*zext(b)
    %3 = comb.concat %c0_i8, %c : i8, i8 // zext(c)
    %4 = comb.concat %c0_i8, %d : i8, i8 // zext(d)
    %5 = comb.mul %3, %4 : i16  // cd = zext(c)*zext(d)
    %6 = comb.add %2, %5 : i16           // ab + cd
    hw.output %6 : i16
  }
}
```

---
* Some passes convert between dialects; this is often called lowering, but dialect conversion is a transformation and can also be a promotion.
* Compilation flows usually lower from higher-level IR to lower-level IR.
* `--convert-<dialect>-to-<dialect>`
* `--convert-comb-to-datapath`
---
```
circt-opt rtl/dot_product.mlir --convert-comb-to-datapath
```

```mlir
hw.module @dot_product(in %a : i8, in %b : i8, in %c : i8, in %d : i8, out out : i16) {
  %c0_i8 = hw.constant 0 : i8
  %0 = comb.concat %c0_i8, %a : i8, i8
  %1 = comb.concat %c0_i8, %b : i8, i8
  // Construct partial products for a*b
  %2:16 = datapath.partial_product %0, %1 : (i16, i16) -> (i16, i16, i16, i16, i16, i16, i16, i16, i16, i16, i16, i16, i16, i16, i16, i16)
  // Reduce partial products for a*b
  %3:2 = datapath.compress %2#0, %2#1, %2#2, %2#3, %2#4, %2#5, %2#6, %2#7, %2#8, %2#9, %2#10, %2#11, %2#12, %2#13, %2#14, %2#15 : i16 [16 -> 2]
  %4 = comb.add bin %3#0, %3#1 : i16 // == a*b
  
  %5 = comb.concat %c0_i8, %c : i8, i8
  %6 = comb.concat %c0_i8, %d : i8, i8
  // Construct partial products for c*d
  %7:16 = datapath.partial_product %5, %6 : (i16, i16) -> (i16, i16, i16, i16, i16, i16, i16, i16, i16, i16, i16, i16, i16, i16, i16, i16)
  // Reduce partial products for c*d
  %8:2 = datapath.compress %7#0, %7#1, %7#2, %7#3, %7#4, %7#5, %7#6, %7#7, %7#8, %7#9, %7#10, %7#11, %7#12, %7#13, %7#14, %7#15 : i16 [16 -> 2]
  %9 = comb.add bin %8#0, %8#1 : i16 // == c*d
  %10 = comb.add %4, %9 : i16 // a*b + c*d
  hw.output %10 : i16
}
```

---
### Optimization Opportunities
1. `datapath.partial_product` produces 16 partial products for an 8-bit multiplication???
2. Do we need two separate `datapath.compress` operations?

These transformations are automated using CIRCT's `--canonicalize` pass. 

---
```
circt-opt rtl/dot_product.mlir --convert-comb-to-datapath \
                                         --canonicalize
```

```mlir
hw.module @dot_product(in %a : i8, in %b : i8, in %c : i8, in %d : i8, out out : i16) {
  %c0_i8 = hw.constant 0 : i8
  %0 = comb.concat %c0_i8, %a : i8, i8
  %1 = comb.concat %c0_i8, %b : i8, i8
  // 8-bit multiplier produces 8 partial products - GOOD!
  %2:8 = datapath.partial_product %0, %1 : (i16, i16) -> (i16, i16, i16, i16, i16, i16, i16, i16)
  %3 = comb.concat %c0_i8, %c : i8, i8
  %4 = comb.concat %c0_i8, %d : i8, i8
  // 8-bit multiplier produces 8 partial products - GOOD!
  %5:8 = datapath.partial_product %3, %4 : (i16, i16) -> (i16, i16, i16, i16, i16, i16, i16, i16)
  // Single compress operation - GOOD!
  %6:2 = datapath.compress %2#0, %2#1, %2#2, %2#3, %2#4, %2#5, %2#6, %2#7, %5#0, %5#1, %5#2, %5#3, %5#4, %5#5, %5#6, %5#7 : i16 [16 -> 2]
  // Single carry-propagate adder - GOOD!
  %7 = comb.add bin %6#0, %6#1 : i16
  hw.output %7 : i16
}
```

---
### Exercise 4 (15 mins): 
1. Determine what computation `rtl/ex4.mlir` implements?
2. Write `rtl/ex4.sv` and use `circt-lec` to verify it is equivalent to `rtl/ex4.mlir`
3. Apply the canonicalization pass to `rtl/ex4.mlir` and then convert back to comb? What has happened to the design?

Hint: extract, replicate, and concatenate implement sign extension, e.g., `wire [8:0] sext_a = {{5{a[3]}}, a};`.

---
## 2.2 Logic Synthesis
* Automatically synthesize a design using `circt-synth` 
* lowers to `synth` dialect == gate-level
* Default is an And-Inverter Graph (AIG)

---
### `circt-synth`

General:
```
circt-synth <in.mlir> --analysis-output=<dir> -o <out.mlir>
```

Our example: 
```
circt-synth rtl/dot_product.mlir --analysis-output=analysis \
         -o rtl/dot_product_aiger.mlir
```


---
### Analysis Output
```
> cat analysis/longest_path.txt
# Longest Path Analysis result for "dot_product"
Found 400 paths
Found 16 unique end points 
Maximum path delay: 33
```

```
> cat analysis/resource_usage.txt
Resource Usage Analysis for module: dot_product
========================================
Total:
  <unknown>:         33
  synth.aig.and_inv: 976
```

---
## 2.3 EDA Integration Generating AIGER
```
circt-translate rtl/dot_product_aiger.mlir --export-aiger \
             -o rtl/dot_product.aiger
```

This format is accepted by [ABC](https://people.eecs.berkeley.edu/~alanmi/abc/) and [Yosys](https://github.com/yosyshq/yosys), which support technology mapping to various FPGAs and ASIC libraries. Technology mapping in `circt-synth` is WIP.

---
### Exercise 5 (15 mins)
1. Chain commands we've learnt together to parse `rtl/ex5.sv` and synthesize an AIG-level representation? How many And-Inverter gates does it take?
2. Copy `rtl/ex5.sv` and optimize the copy **by-hand** to see if you can reduce the And-Inverter count? Can you beat my best attempt 54 And Inverters?
3. Use `circt-lec` to verify the hand-optimized design against the original `rtl/ex5.sv`?

Hint: export AIGER from the `circt-synth` output, not directly from the MLIR generated by `circt-verilog`.

---
# Command Glossary
- `circt-verilog`: parses SystemVerilog and emits CIRCT MLIR.
- `circt-opt`: runs CIRCT/MLIR transformation and optimization passes.
- `circt-lec`: checks logical equivalence between two CIRCT modules.
- `firtool`: emits Verilog from CIRCT IR.
- `circt-synth`: synthesizes CIRCT IR to lower-level logic, such as AIG.
- `circt-translate`: converts CIRCT MLIR to external formats, such as AIGER.
- `z3`: SMT solver used by `circt-lec` to prove equivalence or find a counterexample.

---
# Authors
- Sam Coward ([@cowardsa](https://github.com/cowardsa))
- Louis Ledoux ([@Bynaryman](https://github.com/Bynaryman))
