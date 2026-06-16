module {
  hw.module @ex3(in %a : i4, in %b : i4, in %c : i4, out d : i9) {
    %0 = comb.extract %a from 3 : (i4) -> i1
    %1 = comb.replicate %0 : (i1) -> i5
    %2 = comb.concat %1, %a : i5, i4
    %3 = comb.extract %b from 3 : (i4) -> i1
    %4 = comb.replicate %3 : (i1) -> i5
    %5 = comb.concat %4, %b : i5, i4
    %6:9 = datapath.partial_product %2, %5 : (i9, i9) -> (i9, i9, i9, i9, i9, i9, i9, i9, i9)
    %7:2 = datapath.compress %6#0, %6#1, %6#2, %6#3, %6#4, %6#5, %6#6, %6#7, %6#8 : i9 [9 -> 2]
    %8 = comb.add %7#0, %7#1 : i9
    %9 = comb.extract %c from 3 : (i4) -> i1
    %10 = comb.replicate %9 : (i1) -> i5
    %11 = comb.concat %10, %c : i5, i4
    %12 = comb.add %8, %11 : i9
    hw.output %12 : i9
  }
}

