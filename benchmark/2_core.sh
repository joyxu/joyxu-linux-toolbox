#!/usr/bin/env bash

source 0_common.sh

function calc_ipc {
	TEST_CMD="sudo perf stat -d $STRESS_NG --nop 1 --timeout 5 --taskset 1"
	show_cmd "instruction per cycle test" $TEST_CMD
	$TEST_CMD 2>&1 | grep instructions | cut -d'#' -f2
	echo ----------------------------------------
}

run "cpu clock speed test" $LMBENCH_PATH/mhz

calc_ipc

run "cpu basic ops latency" $LMBENCH_PATH/lat_ops


# TSC performance:
#run S3 perl -e 'use Time::HiRes; for (;$i++ < 100_000_000;) { Time::HiRes::gettimeofday(); }'



