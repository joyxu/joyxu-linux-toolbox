#!/usr/bin/env bash

source 0_common.sh

function calc_ipc() {
	local TEST_CMD="sudo perf stat -d $STRESS_NG --nop 1 --timeout 5 --taskset 1"
	show_cmd "instruction per cycle test" $TEST_CMD
	$TEST_CMD 2>&1 | grep instructions | cut -d'#' -f2
	echo ----------------------------------------
}

function test_core2core_latency() {
	local NAME="c2clat"
	local SCRIPT_PATH=$(pwd -P)/c2clat
	show_cmd "core to core latency test @nanosecond" $SCRIPT_PATH
	compile_name ${NAME} 2

	local CPU_CORES=$(lscpu -ap | grep -v '^#' | cut -d, -f2 | sort -nu | wc -l)
	declare -a C2C_CORE_ARR=()
	i=1
	j=1

	while [ $i -lt $CPU_CORES ]; do
		C2C_CORE_ARR+=("$i")
		j=$((j * 2))
		if [ $j -gt 32 ]; then
			j=32
		fi
		i=$((i + j))
	done
	taskset -c $(echo ${C2C_CORE_ARR[*]}|tr ' ' ',') ${TARGET}
	rm ${TARGET}
}

function test_cache_association() {
	show_cmd "cache association test" "sudo dmidecode -t cache"
	sudo dmidecode -t cache |awk '/Designation/ { print; getline;getline;getline;getline;;getline;getline;getline;getline;getline;getline;getline;getline;print }'
}

function test_uarch_exec_units() {
	local TEST_CMD="$SCRIPT_PATH/insn_bench_aarch64/src/insn_bench_aarch64 -m | tee -a $SCRIPT_PATH/insn_bench_aarch64/results/uarch_$(date '+%Y-%m-%d_%H:%M:%S').md"
	show_cmd "SoC uarch exec units test" $TEST_CMD
	$TEST_CMD
}

run "cpu clock speed test" $LMBENCH_PATH/mhz

run "cpu tlb size test" $LMBENCH_PATH/tlb

run "cpu cacheline size test" $LMBENCH_PATH/line

test_cache_association

# cpu instruction per cycle test:
calc_ipc

# cpu core to core latency test
test_core2core_latency

# test micro architecture exe unit
test_uarch_exec_units

#run "cpu basic ops latency" $LMBENCH_PATH/lat_ops

# cpu single core performance:
#run C2 sysbench --max-requests=10000000 --max-time=10 --num-threads=1 --test=cpu --cpu-max-prime=10000 run

# TSC performance:
#run S3 perl -e 'use Time::HiRes; for (;$i++ < 100_000_000;) { Time::HiRes::gettimeofday(); }'
