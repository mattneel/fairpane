# Downstream integration report: <integration name>

## Use this template

Copy this file for each downstream integration that a release cites.
Replace each placeholder in angle brackets with a recorded value.
Write `none` for an empty field, and never leave a placeholder in a finished report.
Cite an evidence record for every value and every result.
Take every value from a recorded command, a receipt, or a commit, never from memory.

A report describes what one integration exercised at one Fairpane commit.
It is not release qualification, and a local receipt in it stays an unsigned integrity record.

## Integration

| Field | Value | Evidence |
| --- | --- | --- |
| Integration | <name of the downstream application or library> | <record> |
| Integration version | <release version, tag, or full commit ID of the integration> | <record> |
| Fairpane commit | <full 40-hex commit ID that the integration built against> | <record> |
| ABI revision | <value that `fp_abi_revision()` returned to the integration> | <record> |
| Wrapper | <wrapper name, or `none` for direct C ABI calls> | <record> |
| Wrapper version | <wrapper version or full commit ID, or `none`> | <record> |

## Workflow

Describe the downstream workflow that the integration exercises, in the order of its public contract calls.
Name each call or wrapper operation, and name the observable result that the integration checks.

1. <step>

## Failure scenarios

List every scenario of `api/failure-scenarios.json` at the Fairpane commit, in file order.
A scenario that did not run stays in the table, so the denominator stays visible.
Use the result `pass`, `fail`, `crash`, `timeout`, or `not run`, and give the reason for `not run`.

| Scenario | Result | Evidence or reason |
| --- | --- | --- |
| <scenario ID> | <result> | <record or reason> |

## Evidence records

| Record | What it shows |
| --- | --- |
| <repository path or log> | <the command, its exit status, and the commit it ran on> |

## Open limits

List every limit of this report that a reader could otherwise miss.
Include untested platforms, scenarios that did not run, unsigned records, and behavior that the integration does not check.

- <limit>
