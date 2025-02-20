# Initialize variables
DEBUG_MODE=0
DEBUG_SUFFIX=""
VECTORIZE=0
SCALAR_SUFFIX="scalar"
KERNEL_TYPE=""
kernel_ir=""
kernel_launcher=""
c_kernel=""
blk_values=""


# Build directories
BUILD_DIR="../benchmark/build"
KERNEL_LAUNCHER_INCLUDE_DIR=${BUILD_DIR}/launcher/include
LLVM_BUILD_DIR="/llvm-project/build"
RISCV_GNU_TOOLCHAIN_DIR="/opt/riscv"

# Function to print usage
usage() {
    echo "Usage:"
    echo "  ./build.sh -t <python.py> [--blk num1 num2 num3] [-g] [-v]    Build triton kernel"
    echo "  ./build.sh -c <xxx.cpp> [--blk num1 num2 num3] [-g] [-v]      Build C kernel"
    echo "Options:"
    echo "  --blk    Specify three block size numbers (required)"
    echo "  -g      Enable debug mode"
    echo "  -v      Enable vectorization"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t)
            if [[ $# -lt 2 ]]; then
                echo "Error: -t requires a Python file"
                usage
            fi
            KERNEL_TYPE="triton"
            triton_kernel="$2"
            shift 2
            ;;
        -c)
            if [[ $# -lt 2 ]]; then
                echo "Error: -c requires a C++ file"
                usage
            fi
            KERNEL_TYPE="c"
            c_kernel="$2"
            shift 2
            ;;
        --blk)
            if [[ $# -lt 4 ]]; then
                echo "Error: --blk requires three numbers"
                usage
            fi
            # Validate numbers
            if ! [[ $2 =~ ^[0-9]+$ ]] || ! [[ $3 =~ ^[0-9]+$ ]] || ! [[ $4 =~ ^[0-9]+$ ]]; then
                echo "Error: --blk arguments must be numbers"
                usage
            fi
            blk_values="_${2}_${3}_${4}"
            shift 4
            ;;
        -g)
            DEBUG_MODE=1
            DEBUG_SUFFIX="_g"
            shift
            ;;
        -v)
            VECTORIZE=1
            SCALAR_SUFFIX=""
            shift
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate input
if [ -z "$KERNEL_TYPE" ]; then
    echo "Error: Must specify either -t or -c option"
    usage
fi

if [ -z "$blk_values" ]; then
    echo "Error: Must specify --blk option with three numbers"
    usage
fi


# Setup compiler flags
DEBUG_FLAG=""
[ $DEBUG_MODE -eq 1 ] && DEBUG_FLAG="-g"

# # VECTORIZE_FLAGS looks like no effects for riscv
# VECTORIZE_FLAGS="-fno-vectorize -fno-slp-vectorize"
# [ $VECTORIZE -eq 1 ] && VECTORIZE_FLAGS="-fvectorize -fslp-vectorize"

VECTORIZE_FLAGS=""
[ $VECTORIZE -eq 1 ] && VECTORIZE_FLAGS="-mllvm --riscv-v-vector-bits-min=256" 
# --riscv-v-vector-bits-min=128 by default, 
# if it's longer than what it should be, there may be mistakes in application results.


MARCH="rv64gc"
[ $VECTORIZE -eq 1 ] && MARCH="${MARCH}v"


CLANGPP="clang++ --target=riscv64-unknown-linux-gnu \
        --sysroot=${RISCV_GNU_TOOLCHAIN_DIR}/sysroot \
        --gcc-toolchain=${RISCV_GNU_TOOLCHAIN_DIR} \
        -march=${MARCH} -mabi=lp64d \
        ${VECTORIZE_FLAGS} \
        -O2 ${DEBUG_FLAG}"

OBJDUMP="${RISCV_GNU_TOOLCHAIN_DIR}/bin/riscv64-unknown-linux-gnu-objdump" #<<<<<<M


AR="${LLVM_BUILD_DIR}/bin/llvm-ar"
AS="${LLVM_BUILD_DIR}/bin/llvm-as"
PYC="python3"


# Read input from files to test correctness. 
# You can feel free to comment them when necessary.
MODE="Accuracy"
if [ "${MODE}" == "Accuracy" ]; then
     CLANGPP+=" -DCHECK_ACCURACY "
     # export DB_FILE="matrix"
fi

build_c_kernel() {
    KERNEL_ENABLE="C_KERNEL_ENABLE"
    LIB_DIR="${BUILD_DIR}/lib/gcc"
    BIN_DIR="${BUILD_DIR}/bin/gcc"
    OBJ_DIR="${BUILD_DIR}/obj/gcc"

    ${CLANGPP} -fPIC \
        -I ${BUILD_DIR}/../../env_build/include \
        -c ${BUILD_DIR}/../src/support/*.cpp \
        -o ${OBJ_DIR}/support.o

    ${AR} rcs ${LIB_DIR}/libsupport.a ${OBJ_DIR}/support.o

    kernel_name="$(basename "${c_kernel}" .cpp)"

    OUT_OBJ_DIR="${OBJ_DIR}/${kernel_name}"
    [ ! -d "${OUT_OBJ_DIR}" ] && mkdir -p "${OUT_OBJ_DIR}"

    $CLANGPP \
        -I "${BUILD_DIR}/../../env_build/include" \
        -S "${c_kernel}" \
        -fPIC -o "${OUT_OBJ_DIR}/${SCALAR_SUFFIX}_c_${kernel_name}${blk_values}_kernel_src.s"

    $CLANGPP \
        -I "${BUILD_DIR}/../../env_build/include" \
        -c "${c_kernel}" \
        -fPIC \
        -o "${OUT_OBJ_DIR}/c_${kernel_name}.o"

    $AR rcs "${LIB_DIR}/libc${kernel_name}.a" "c_${kernel_name}.o"
    lib_name="c${kernel_name}"
}

build_triton_kernel() {
    KERNEL_ENABLE="TRITON_KERNEL_ENABLE"
    LIB_DIR="${BUILD_DIR}/lib/triton"
    OBJ_DIR="${BUILD_DIR}/obj/triton"
    BIN_DIR="${BUILD_DIR}/bin/triton"


    ${CLANGPP} -fPIC -I ${BUILD_DIR}/../../env_build/include -c ${BUILD_DIR}/../src/support/*.cpp -o ${OBJ_DIR}/support.o
    ${AR} rcs ${LIB_DIR}/libsupport.a ${OBJ_DIR}/support.o

    kernel_name="$(basename "${triton_kernel}" .py)"
    KERNEL_AUX_FILE_DIR=${BUILD_DIR}/launcher/src/${kernel_name}
    [ ! -d "${KERNEL_AUX_FILE_DIR}" ] && mkdir -p ${KERNEL_AUX_FILE_DIR}

    OUT_OBJ_DIR="${OBJ_DIR}/${kernel_name}"
    [ ! -d "${OUT_OBJ_DIR}" ] && mkdir -p "${OUT_OBJ_DIR}"

    KERNEL_LAUNCHER_INCLUDE_DIR=${KERNEL_LAUNCHER_INCLUDE_DIR} KERNEL_AUX_FILE_DIR=${KERNEL_AUX_FILE_DIR} TRITON_CPU_BACKEND=1 ${PYC} ${triton_kernel}

    kernel_ir=${KERNEL_AUX_FILE_DIR}/"${kernel_name}_kernel.llir" # each llvm IR file name ends up with _kernel
    $AS -o "${OUT_OBJ_DIR}/${kernel_name}_kernel.bc" "${kernel_ir}"

    $CLANGPP -fPIC \
             -S "${OUT_OBJ_DIR}/${kernel_name}_kernel.bc" \
             -o "${OUT_OBJ_DIR}/${SCALAR_SUFFIX}_${kernel_name}${blk_values}_kernel_src.s"

    $CLANGPP -fPIC \
             -c "${OUT_OBJ_DIR}/${kernel_name}_kernel.bc" \
             -o "${OUT_OBJ_DIR}/${kernel_name}.o"

    kernel_launcher=${KERNEL_AUX_FILE_DIR}/"${kernel_name}_kernel_launcher.cpp" #notice _cpu
    launcher_name=$(basename "${kernel_launcher}" .cpp)

    $CLANGPP \
    -I "${BUILD_DIR}/../../env_build/include" \
    -I "${KERNEL_LAUNCHER_INCLUDE_DIR}" \
    -c "${kernel_launcher}" \
    -fPIC \
    -o "${OUT_OBJ_DIR}/${launcher_name}.o"

    $AR rcs "${LIB_DIR}/libtriton${kernel_name}.a" "${OUT_OBJ_DIR}/${launcher_name}.o" "${OUT_OBJ_DIR}/${kernel_name}.o"
    lib_name="triton${kernel_name}"
}

# Build kernel based on type
if [ "$KERNEL_TYPE" = "triton" ]; then
    build_triton_kernel
elif [ "$KERNEL_TYPE" = "c" ]; then
    build_c_kernel
else
    echo "Error: Invalid kernel type"
    exit 1
fi

main="${BUILD_DIR}/../src/main/${kernel_name}_kernel.cpp"
[ ! -f "$main" ] && echo "Error: main file not found: $main" && exit 1

OUT_ELF_DIR="${BIN_DIR}/${kernel_name}"
[ ! -d "${OUT_ELF_DIR}" ] && mkdir -p "${OUT_ELF_DIR}"

# Build final executable
$CLANGPP ${main} \
    -I "${BUILD_DIR}/../../env_build/include" \
    -I "${KERNEL_LAUNCHER_INCLUDE_DIR}" \
    -L "${LIB_DIR}" \
    -l"${lib_name}" \
    -lsupport \
    -latomic \
    -std=c++17 \
    -D"${KERNEL_ENABLE}" \
    -fPIC \
    -o "${OUT_ELF_DIR}/${SCALAR_SUFFIX}_${kernel_name}${blk_values}${DEBUG_SUFFIX}.elf"

${OBJDUMP} -d -S --source-comment="@src " \
           "${OUT_ELF_DIR}/${SCALAR_SUFFIX}_${kernel_name}${blk_values}${DEBUG_SUFFIX}.elf" \
           &> "${OUT_OBJ_DIR}/${SCALAR_SUFFIX}_${kernel_name}${blk_values}.elf.s"
