* [What is CIRCT?](#what-is-circt)
* [CIRCT Tutorial](#circt-tutorial)
    * [Getting Started](#getting-started)
    * [Loading a Design](#loading-a-design)
    * [Optimizing a Design](#optimizing-a-design)
    * [Verifying a Transformation](#verifying-a-transformation)

# What is CIRCT?

CIRCT (Circuit IR Compilers and Tools) is an open-source compiler infrastructure project for digital hardware design.
It provides a set of reusable compiler dialects, optimizations, and transformation passes built on LLVM/MLIR.
CIRCT enables hardware designers and compiler developers to express, transform, and generate circuit representations for FPGAs, ASICs, and other digital systems.

Key aspects:

- A hardware-centered IR and dialect ecosystem for digital circuit design.
- Reusable passes for lowering, verification, and code generation.
- Integration with MLIR and LLVM for compiler-based hardware flows.
- Support for multiple input formats and backends, including FIRRTL, HW, and system-level representations.

CIRCT was inspired by the need for a more modular and reusable hardware compiler infrastructure.
Traditional hardware design flows were often monolithic and hard to extend.
The CIRCT project draws inspiration from:

- LLVM and MLIR: using compiler infrastructure patterns to make hardware transformation passes composable.
- Hardware description languages like Verilog, FIRRTL, and Chisel.
- Prior work in high-level synthesis and domain-specific IRs for hardware.
- The desire to unify hardware and software compiler techniques in a shared framework.

CIRCT aims to make hardware compiler development more agile, enabling researchers and engineers to experiment with new optimizations and hardware dialects.

# CIRCT Tutorial

In this tutorial we will cover the following:
1. Install CIRCT tools in a docker image.
2. Load a hardware design representation.
3. Apply CIRCT transformations and analysis passes.
4. Generate a target output for verification or implementation.

## Getting Started
Build and run the docker container:
```
docker build -t circt .
docker run -it circt
```

From within the docker container you should now be able to use CIRCT's pre-built tools.
`circt-opt --version` should produce:
```
LLVM (http://llvm.org/):
  LLVM version 23.0.0git
  Optimized build.
CIRCT firtool-1.147.0
```

## Loading a Design
Now lets look at how to get an existing design into CIRCT:
```sv
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

If we run: `circt-verilog rtl/fma.sv -o rtl/fma.mlir` we get CIRCT IR out:
```mlir
// rtl/fma.mlir
module {
  hw.module @fma(in %a : i4, in %b : i4, in %c : i4, out d : i9) {
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

We can see two dialects in action here:
- **comb**: combinatorial logic constructs e.g., add, or
- **hw**: structural hardware constructs e.g., modules, ports

The System Verilog features supported by `circt-verilog` are best documented in the [sv-tests suite](https://chipsalliance.github.io/sv-tests-results/), but this is an ongoing effort to add support.

## Optimizing a Design
CIRCT is a compiler stack - it's all about **passes**! 
These incantations look scary but in many cases they are hidden behind nice tools that make life much easier (otherwise LLMs are pretty good at CIRCT). 

Let's try out a couple of passes using the godfather tool `circt-opt`:

`circt-opt rtl/fma.mlir --comb-int-range-narrowing  --canonicalize -o rtl/fma_opt.mlir`

```mlir
// rtl/fma_opt.mlir
module {
  hw.module @fma(in %a : i4, in %b : i4, in %c : i4, out d : i9) {
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

What are these passes doing?
* *comb-int-range-narrowing* - performs operator width reduction based on an interval analysis (e.g., the multiplication result fits within 8-bits rather than 9)
* *canonicalize* - classic hardware optimizations that strictly improve area and delay e.g., zext(res[7:0])[7:0] -> res[7:0]

### Exercise
Try swapping the order of the passes in the command? How does the output change?

## Verifying a Transformation
Of course, you're a circuit designer so you don't trust research tools... Fortunately, we provide a way to mark our own homework using a logical equivalence checker called `circt-lec`:

General Usage: `circt-lec --c1 <module_name_1> <design_1.mlir> --c2 <module_name_2> <design_2.mlir>`

Our specific example: 
`circt-lec --c1 fma rtl/fma.mlir --c2 fma rtl/fma_opt.mlir`

Which should return: `c1 == c2`

How does `circt-lec` work? 
1. It constructs a miter circuit that instantiates each design and asserts identical outputs when supplied with identical inputs 
2. The miter circuit and both modules are lowered to SMT
3. The SMT query is discharged to Z3 which returns `unsat` if the two modules are logically equivalent

CIRCT has support for [bounded model checking](https://circt.llvm.org/docs/Tools/circt-bmc/) through `circt-bmc`, which we will not cover in this tutorial.

### Exercise (5 mins)
Have a go at breaking one of the designs by editing `rtl/fma_opt.mlir` and check that `circt-lec` returns `c1 != c2`? (unfortunately we can't generate a counter-example easily right now).

## Generating Verilog
A classic CIRCT design flow is:
1. Parse a design and generate CIRCT IR
2. Optimize the CIRCT IR and verify the correctness
3. Generate Verilog to hand-off to downstream tools (e.g., Synopsys/Cadence/Altera/Xilinx)

Given that we've now got some optimized and correct mlir (`rtl/fma_opt.mlir`), we can generate Verilog out:

`circt-opt --export-verilog -o rtl/fma_opt.mlir`

```
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

### Exercise (5 mins)
1. Modify the command above to save the verilog to a file?
2. Use `circt-verilog` to compile the generated verilog back to CIRCT IR?
3. Use `circt-lec` to verify that the generated verilog and original CIRCT IR are equivalent?

## Synthesizing a Design
Instead of generating Verilog, we can also synthesize a design using `circt-synth`, that lowers a design to an And-Inverter Graph (AIG).

`circt-synth rtl/fma_opt.mlir --analysis-output=results -o rtl/fma_opt_aiger.mlir`

If we look at the analysis-output we get a summary of the number of AIG gates used along with the critical path

