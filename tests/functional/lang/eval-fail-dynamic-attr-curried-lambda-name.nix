# A curried lambda passes the name of its dynamic attribute on to the
# lambda in its body. The error must name `alpha`, even after `beta` was
# evaluated.
let
  mk = n: { ${n} = a: { x }: x; };
  alpha = (mk "alpha").alpha;
  beta = (mk "beta").beta;
in
builtins.seq (alpha 1) (builtins.seq (beta 1) (alpha 1 { }))
