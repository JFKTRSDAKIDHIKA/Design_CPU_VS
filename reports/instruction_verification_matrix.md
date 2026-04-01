# Instruction Verification Matrix

| Instruction | RTL | Reference | Directed tests | Corner cases | Randomized scenarios | Coverage bins hit | Assertions | Bugs | Final status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ADD | yes | yes | arith_logic, arith_signoff, branch_control, branch_flag_signoff | flag_edges | rand_101 | 4/4 | reset/data-bus safety assertions | - | PASS |
| SUB | yes | yes | arith_logic, arith_signoff, branch_control, branch_flag_signoff, memory_access, memory_signoff | - | - | 4/4 | reset/data-bus safety assertions | - | PASS |
| AND | yes | yes | arith_logic, logic_move_shift_signoff | - | rand_100 | 2/2 | reset/data-bus safety assertions | - | PASS |
| CMP | yes | yes | arith_logic, logic_move_shift_signoff, branch_flag_signoff | - | rand_100, rand_101, rand_102, rand_103, rand_cov_500, rand_cov_501, rand_cov_502, rand_cov_503 | 3/3 | branch/PC legality assertions | - | PASS |
| XOR | yes | yes | arith_logic, logic_move_shift_signoff | - | - | 2/2 | reset/data-bus safety assertions | - | PASS |
| TEST | yes | yes | arith_logic, logic_move_shift_signoff | - | rand_cov_502 | 3/3 | branch/PC legality assertions | - | PASS |
| OR | yes | yes | arith_logic, logic_move_shift_signoff | - | rand_100 | 2/2 | reset/data-bus safety assertions | BUG-001 Assembler mis-sized `LDRR/STRR` | PASS |
| MVRR | yes | yes | arith_logic, logic_move_shift_signoff | - | rand_100, rand_103, rand_cov_503 | 3/3 | reset/data-bus safety assertions | - | PASS |
| DEC | yes | yes | arith_logic, arith_signoff, branch_control, branch_flag_signoff | flag_edges | rand_100, rand_101, rand_102, rand_103, rand_cov_500, rand_cov_501, rand_cov_502, rand_cov_503 | 2/2 | branch/PC legality assertions | - | PASS |
| INC | yes | yes | arith_logic, arith_signoff | flag_edges | rand_102 | 2/2 | branch/PC legality assertions | - | PASS |
| SHL | yes | yes | arith_logic, logic_move_shift_signoff | - | rand_102, rand_cov_500, rand_cov_502 | 2/2 | branch/PC legality assertions | - | PASS |
| SHR | yes | yes | arith_logic, logic_move_shift_signoff | - | rand_102, rand_103, rand_cov_500, rand_cov_501, rand_cov_502, rand_cov_503 | 2/2 | branch/PC legality assertions | - | PASS |
| ADC | yes | yes | arith_logic, arith_signoff | flag_edges | rand_103, rand_cov_503 | 3/3 | carry-chain protocol assertions | - | PASS |
| SBB | yes | yes | arith_logic, arith_signoff | flag_edges | rand_103, rand_cov_503 | 3/3 | carry-chain protocol assertions | - | PASS |
| JR | yes | yes | arith_logic, arith_signoff, logic_move_shift_signoff, branch_control, branch_flag_signoff, memory_access, memory_signoff | flag_edges | rand_100, rand_101, rand_102, rand_103, rand_cov_500, rand_cov_501, rand_cov_502, rand_cov_503 | 3/3 | branch/PC legality assertions | - | PASS |
| JRC | yes | yes | branch_control, branch_flag_signoff | - | rand_102, rand_cov_500, rand_cov_501 | 3/3 | branch/PC legality assertions | - | PASS |
| JRNC | yes | yes | branch_control, branch_flag_signoff | - | rand_cov_500, rand_cov_501 | 3/3 | branch/PC legality assertions | - | PASS |
| JRZ | yes | yes | branch_control, branch_flag_signoff | - | rand_100, rand_101, rand_103, rand_cov_500, rand_cov_501 | 3/3 | branch/PC legality assertions | - | PASS |
| JRNZ | yes | yes | branch_control, branch_flag_signoff | - | rand_100, rand_101, rand_102, rand_103, rand_cov_500, rand_cov_501, rand_cov_502, rand_cov_503 | 3/3 | branch/PC legality assertions | - | PASS |
| JRS | yes | yes | branch_control, branch_flag_signoff | - | rand_cov_503 | 3/3 | branch/PC legality assertions | - | PASS |
| JRNS | yes | yes | branch_control, branch_flag_signoff | - | rand_100, rand_101, rand_cov_500, rand_cov_501 | 3/3 | branch/PC legality assertions | - | PASS |
| CLC | yes | yes | arith_logic, arith_signoff, branch_control, branch_flag_signoff | flag_edges | rand_100, rand_102, rand_cov_500, rand_cov_501, rand_cov_502, rand_cov_503 | 3/3 | carry-chain protocol assertions | - | PASS |
| STC | yes | yes | arith_logic, arith_signoff, branch_control, branch_flag_signoff | flag_edges | rand_101, rand_103, rand_cov_500, rand_cov_501 | 3/3 | carry-chain protocol assertions | - | PASS |
| JMPA | yes | yes | branch_control, branch_flag_signoff | - | rand_100, rand_101, rand_102, rand_103, rand_cov_500, rand_cov_501, rand_cov_502, rand_cov_503 | 2/2 | branch/PC legality assertions | - | PASS |
| LDRR | yes | yes | memory_access, memory_signoff | - | rand_100, rand_101, rand_102, rand_103, rand_cov_500, rand_cov_501 | 3/3 | data_bus read/write and memory timing assertions | BUG-001 Assembler mis-sized `LDRR/STRR`, BUG-003 UVM memory responder drive-release timing | PASS |
| STRR | yes | yes | memory_access, memory_signoff | - | rand_100, rand_101, rand_102, rand_103, rand_cov_500, rand_cov_501, rand_cov_502, rand_cov_503 | 3/3 | data_bus read/write and memory timing assertions | BUG-001 Assembler mis-sized `LDRR/STRR`, BUG-003 UVM memory responder drive-release timing | PASS |
| MVRD | yes | yes | arith_logic, arith_signoff, logic_move_shift_signoff, branch_control, branch_flag_signoff, memory_access, memory_signoff | flag_edges | rand_100, rand_101, rand_102, rand_103, rand_cov_500, rand_cov_501, rand_cov_502, rand_cov_503 | 4/4 | double-word PC step assertions | - | PASS |
