# Final Verification Summary

## Regression Result

- 回归入口：[`scripts/run_regression.sh`](/home/3dic/Design_CPU_VS/scripts/run_regression.sh)
- 回归结果条目数：`13`
- 通过情况：`13 / 13 PASS`

## Signoff Status

- Functional coverage: `100.00%`
- Instruction matrix: see [`reports/instruction_verification_matrix.md`](/home/3dic/Design_CPU_VS/reports/instruction_verification_matrix.md)
- Coverage closure: see [`reports/coverage_closure.md`](/home/3dic/Design_CPU_VS/reports/coverage_closure.md)
- Code coverage status: `not_run`

## ISA In Scope

- `ADD SUB AND CMP XOR TEST OR MVRR`
- `DEC INC SHL SHR ADC SBB`
- `JR JRC JRNC JRZ JRNZ JRS JRNS`
- `CLC STC JMPA LDRR STRR MVRD`
