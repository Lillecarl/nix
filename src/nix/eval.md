R""(

# Examples

* Evaluate a Nix expression given on the command line:

  ```console
  # nix eval --expr '1 + 2'
  ```

* Evaluate a Nix expression to JSON:

  ```console
  # nix eval --json --expr '{ x = 1; }'
  {"x":1}
  ```

* Evaluate a Nix expression from a file:

  ```console
  # nix eval --file ./my-nixpkgs hello.name
  ```

* Get the current version of the `nixpkgs` flake:

  ```console
  # nix eval --raw nixpkgs#lib.version
  ```

* Print the store path of the Hello package:

  ```console
  # nix eval --raw nixpkgs#hello
  ```

* Get a list of checks in the `nix` flake:

  ```console
  # nix eval nix#checks.x86_64-linux --apply builtins.attrNames
  ```

* Generate a directory with the specified contents:

  ```console
  # nix eval --write-to ./out --expr '{ foo = "bar"; subdir.bla = "123"; }'
  # cat ./out/foo
  bar
  # cat ./out/subdir/bla
  123

# Description

This command evaluates the given Nix expression, and prints the result on standard output.

It also evaluates any nested attribute values and list items.

# Output format

`nix eval` can produce output in several formats:

* By default, the evaluation result is printed as a Nix expression.

* With `--json`, the evaluation result is printed in JSON format. Note
  that this fails if the result contains values that are not
  representable as JSON, such as functions.

* With `--raw`, the evaluation result must be a string, which is
  printed verbatim, without any quoting.

* With `--write-to` *path*, the evaluation result must be a string or
  a nested attribute set whose leaf values are strings. These strings
  are written to files named *path*/*attrpath*. *path* must not
  already exist.

# Submitting an output

`--submit` *output-name* gives no output on standard output. It registers
the derivation that the expression gives as the output *output-name* of the
derivation that runs now.

It works only inside a build that asks for the `builder-rpc-v0` system
feature. That feature gives the builder a restricted daemon socket, and
`nix store submit-output` uses the same socket.

The evaluator writes each derivation of the graph through that socket, so
one command registers the whole graph and names the root:

```console
# nix eval --submit out --file ./graph.nix root
```

The expression gives a derivation, and `--submit` takes the derivation
itself and not the output of it. The build that runs now makes the
derivation, and no build made the output of that derivation yet. A plain
store path goes through as it is, which is what `nix store submit-output`
takes.

The derivation that runs must be content-addressing, and `outputHashMode`
must be `text` when the expression gives a derivation. Every derivation
ingests as `text`, and Nix compares the method that the running derivation
declares with the method of the submitted store object.

)""
