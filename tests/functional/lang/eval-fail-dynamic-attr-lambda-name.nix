# The same lambda is bound to two dynamic attributes. Calling it as
# `alpha` must report `alpha`, even though `beta` was evaluated last.
let
  mk = n: { ${n} = { x }: x; };
  alpha = (mk "alpha").alpha;
  beta = (mk "beta").beta;
in
builtins.seq alpha (builtins.seq beta (alpha { }))
