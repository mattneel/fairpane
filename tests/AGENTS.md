# Test rules

Exercise actual behavior rather than constants that describe intended behavior.
Keep malformed input and allocation failure visible.
Preserve every crash, timeout, and unsupported case in results.

Keep upstream corpora separate from local expectations.
Do not edit upstream tests to match the implementation.
Do not change acceptance thresholds inside a feature patch.
Use only redistributable, provenance-recorded fixtures.
