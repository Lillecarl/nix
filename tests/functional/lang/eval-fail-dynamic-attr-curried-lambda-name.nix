# Like eval-fail-dynamic-attr-lambda-name.nix, but with a curried
# lambda. The name has to reach the inner lambda too, since that is the
# one that reports the missing argument.
let
  mk = n: { ${n} = a: { x }: x; };
  alpha = (mk "alpha").alpha;
  beta = (mk "beta").beta;
in
builtins.seq (alpha 1) (builtins.seq (beta 1) (alpha 1 { }))
