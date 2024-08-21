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
	echo ----------------------------------------
	echo "core to core latency test"
	echo ----------------------------------------
	compile_name ${NAME} 2
	taskset -c 1,3,7,15,31,32,63,65,94,97,127 ${TARGET}
	rm ${TARGET}:
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



