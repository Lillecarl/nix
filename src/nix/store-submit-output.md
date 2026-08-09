R""(

# Examples

* To submit a given [store object] as the output named `out`:

  ```console
  # nix store submit-output /nix/store/h6zs50y2662apmnbcnhnbxll76lv02yy-hello-2.12.3 out
  ```

# Description

`nix store submit-output` registers a [store object] as an output of the currently-running derivation.

It only functions when running inside a content-addressing derivation with the `builder-rpc-v0`
system feature, which provides a limited daemon socket to the builder.
Execution in any other environment will fail.

The name of the store object must be the name that the derivation gives that output.
That name is the name of the derivation for the output `out`,
and it is that name with `-<output>` after it for each other output.

A store object that is a derivation is the exception, and it keeps the name of that derivation.
A planner registers a graph of derivations and then submits the root of that graph,
and the name of that root is a result of the plan.
Nix reads such a store object as a derivation, and it computes the store path of that derivation again.
The submission fails when the result is not the store path where the derivation is.

This exception needs a floating content-addressed output.
The name of the derivation and the declared hash together give a fixed output its store path,
so a fixed output keeps the rule above.

[store object]: @docroot@/store/store-object.md
)""
