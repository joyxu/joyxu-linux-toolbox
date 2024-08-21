#!/usr/bin/env bash

source 0_common.sh

function calc_ipc {
	TEST_CMD="sudo perf stat -d $STRESS_NG --nop 1 --timeout 5 --taskset 1"
	show_cmd "instruction per cycle test" $TEST_CMD
	$TEST_CMD 2>&1 | grep instructions | cut -d'#' -f2
	echo ----------------------------------------
}

function test_core2core_latency {
	NAME="c2clat"
	SCRIPT_PATH=$(pwd -P)/c2clat
	show_cmd "core to core latency test" $SCRIPT_PATH
	compile_name ${NAME} 2

	CPU_CORES=$(lscpu -ap | grep -v '^#' | cut -d, -f2 | sort -nu | wc -l)
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

run "cpu clock speed test" $LMBENCH_PATH/mhz

# cpu instruction per cycle test:
calc_ipc

run "cpu basic ops latency" $LMBENCH_PATH/lat_ops

# cpu core to core latency test
test_core2core_latency

# cpu single core performance:
#run C2 sysbench --max-requests=10000000 --max-time=10 --num-threads=1 --test=cpu --cpu-max-prime=10000 run

# TSC performance:
#run S3 perl -e 'use Time::HiRes; for (;$i++ < 100_000_000;) { Time::HiRes::gettimeofday(); }'



