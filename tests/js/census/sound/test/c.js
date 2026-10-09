/*---
description: Strict code cannot contain a with statement.
flags: [onlyStrict]
negative:
  phase: parse
  type: SyntaxError
---*/
with (a) {}
