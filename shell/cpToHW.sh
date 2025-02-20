BUILD_DIR="../../benchmark/build"
C_BIN_DIR="${BUILD_DIR}/bin/gcc"
TRITON_BIN_DIR="${BUILD_DIR}/bin/triton"
TEST_DATA="${BUILD_DIR}/../test"

REMOTE="aicompiler@10.32.44.164"
REMOTE_DIR="/home/aicompiler/work/triton_riscv_test"


ssh -M -S /tmp/ssh_ctrl_socket -fnN ${REMOTE}


# scp -o ControlPath=/tmp/ssh_ctrl_socket ${C_BIN_DIR}/*/*.elf ${REMOTE}:${REMOTE_DIR}/c/
scp -o ControlPath=/tmp/ssh_ctrl_socket ${TRITON_BIN_DIR}/*/*matmul_8_4_4*.elf ${REMOTE}:${REMOTE_DIR}/triton/
# scp -o ControlPath=/tmp/ssh_ctrl_socket ${TEST_DATA}/*.txt ${REMOTE}:${REMOTE_DIR}/test/

ssh -S /tmp/ssh_ctrl_socket -O exit ${REMOTE}
