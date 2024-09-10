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
	local TEST_CMD="$SCRIPT_PATH/insn_bench_aarch64/src/insn_bench_aarch64 -m"
	local LOG_FILE="$SCRIPT_PATH/insn_bench_aarch64/results/uarch_$(date '+%Y_%m_%d_%H_%M_%S').md"
	show_cmd "SoC uarch exec units test " $LOG_FILE
	start_spinner $TEST_CMD
	numactl -C 2 -l $TEST_CMD > $LOG_FILE
	stop_spinner $?

	local START_LINE=$(cat $LOG_FILE | grep -ni 'scalar load' | cut -d ':' -f1)
	START_LINE=$((START_LINE + 4))
	local END_LINE=$(cat $LOG_FILE | grep -ni 'scalar store (' | cut -d ':' -f1)
	END_LINE=$((END_LINE - 2))
	local UNIT_COUNTS=$(cat $LOG_FILE | sed -n "$START_LINE,$END_LINE p" | cut -d '|' -f4 | sort | uniq | tail -n 1)
	echo "Load Excution Units Counts: " $UNIT_COUNTS

	START_LINE=$((END_LINE + 6))
	END_LINE=$(cat $LOG_FILE | grep -ni 'scalar store-to-load' | cut -d ':' -f1)
	END_LINE=$((END_LINE - 2))
	UNIT_COUNTS=$(cat $LOG_FILE | sed -n "$START_LINE,$END_LINE p" | cut -d '|' -f4 | sort | uniq | tail -n 1)
	echo "Store Excution Units Counts: " $UNIT_COUNTS

	START_LINE=$(cat $LOG_FILE | grep -ni 'scalar integer add' | cut -d ':' -f1)
	START_LINE=$((START_LINE + 4))
	END_LINE=$(cat $LOG_FILE | grep -ni 'scalar integer mul' | cut -d ':' -f1)
	END_LINE=$((END_LINE - 2))
	UNIT_COUNTS=$(cat $LOG_FILE | sed -n "$START_LINE,$END_LINE p" | cut -d '|' -f4 | sort | uniq | tail -n 1)
	echo "ALU Excution Units Counts: " $UNIT_COUNTS

	START_LINE=$((END_LINE + 6))
	END_LINE=$(cat $LOG_FILE | grep -ni 'scalar integer divide' | cut -d ':' -f1)
	END_LINE=$((END_LINE - 2))
	UNIT_COUNTS=$(cat $LOG_FILE | sed -n "$START_LINE,$END_LINE p" | cut -d '|' -f4 | sort | uniq | tail -n 1)
	echo "MUL/DIV Excution Units Counts: " $UNIT_COUNTS

	START_LINE=$(cat $LOG_FILE | grep -ni 'vector integer add, sub' | cut -d ':' -f1)
	START_LINE=$((START_LINE + 4))
	END_LINE=$(cat $LOG_FILE | grep -ni 'vector integer add and sub' | cut -d ':' -f1)
	END_LINE=$((END_LINE - 2))
	UNIT_COUNTS=$(cat $LOG_FILE | sed -n "$START_LINE,$END_LINE p" | cut -d '|' -f4 | sort | uniq | tail -n 1)
	echo "Vector/SIMD Excution Units Counts: " $UNIT_COUNTS

	START_LINE=$(cat $LOG_FILE | grep -ni 'vector integer multiply-acc' | cut -d ':' -f1)
	START_LINE=$((START_LINE + 4))
	END_LINE=$(cat $LOG_FILE | grep -ni 'Vector integer absolute difference accumulate' | cut -d ':' -f1)
	END_LINE=$((END_LINE - 2))
	UNIT_COUNTS=$(cat $LOG_FILE | sed -n "$START_LINE,$END_LINE p" | cut -d '|' -f4 | sort | uniq | tail -n 1)
	echo "Vector MUL/DIV Excution Units Counts: " $UNIT_COUNTS
}

function test_uarch_buf_units() {
	local TEST_PATH=$SCRIPT_PATH/microarchitecturometer
	local TMP_ARCH=$(uname -m)
	show_cmd "SoC uarch buf test " $TEST_PATH

	export WORK_LIST=mem
	export PADDING_LIST="nop mov cmp $(python $TEST_PATH/microarchitecturometer_generator.py --list padding | grep $TMP_ARCH)"
	cd $TEST_PATH
	numactl -C 2 -l ./collect-results.sh
	cd -

 	local R_BUF_DATA=$TEST_PATH/results/mem.nop.txt
	if [[ -e $R_BUF_DATA ]]; then
		echo ----------------------------------------
		echo "ROB size"
		echo ----------------------------------------
		gnuplot -p -e "set terminal dumb ansirgb; set autoscale;set key top left; plot '<cat $R_BUF_DATA' u 1:2 w lp ls 1 t 'real', '<cat $R_BUF_DATA' u 1:3 w lp ls 2 t 'base' "
	fi

 	R_BUF_DATA=$TEST_PATH/results/mem.branch-$TMP_ARCH.txt
	if [[ -e $R_BUF_DATA ]]; then
		echo ----------------------------------------
		echo "Outstanding size"
		echo ----------------------------------------
		gnuplot -p -e "set terminal dumb ansirgb; set autoscale;set key top left; plot '<cat $R_BUF_DATA' u 1:2 w lp ls 1 t 'real', '<cat $R_BUF_DATA' u 1:3 w lp ls 2 t 'base' "
	fi

 	R_BUF_DATA=$TEST_PATH/results/mem.load-$TMP_ARCH.txt
	if [[ -e $R_BUF_DATA ]]; then
		echo ----------------------------------------
		echo "Load buf size"
		echo ----------------------------------------
		gnuplot -p -e "set terminal dumb ansirgb; set autoscale;set key top left; plot '<cat $R_BUF_DATA' u 1:2 w lp ls 1 t 'real', '<cat $R_BUF_DATA' u 1:3 w lp ls 2 t 'base' "
	fi

 	R_BUF_DATA=$TEST_PATH/results/mem.store-$TMP_ARCH.txt
	if [[ -e $R_BUF_DATA ]]; then
		echo ----------------------------------------
		echo "Store buf size"
		echo ----------------------------------------
		gnuplot -p -e "set terminal dumb ansirgb; set autoscale;set key top left; plot '<cat $R_BUF_DATA' u 1:2 w lp ls 1 t 'real', '<cat $R_BUF_DATA' u 1:3 w lp ls 2 t 'base' "
	fi
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

# test micro architecture rob, load buf and store buf
test_uarch_buf_units

#run "cpu basic ops latency" $LMBENCH_PATH/lat_ops

# cpu single core performance:
#run C2 sysbench --max-requests=10000000 --max-time=10 --num-threads=1 --test=cpu --cpu-max-prime=10000 run

# TSC performance:
#run S3 perl -e 'use Time::HiRes; for (;$i++ < 100_000_000;) { Time::HiRes::gettimeofday(); }'
