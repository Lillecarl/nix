# One lambda, defined as a dynamic attribute and evaluated under two
# names. The error must name `alpha`, even after `beta` was evaluated.
let
  mk = n: { ${n} = { x }: x; };
  alpha = (mk "alpha").alpha;
  beta = (mk "beta").beta;
in
builtins.seq alpha (builtins.seq beta (alpha { }))
