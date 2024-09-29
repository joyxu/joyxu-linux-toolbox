#!/bin/bash
#refer to: https://github.com/brendangregg/Misc/blob/master/microbenchmarks/microbench_ubuntu.sh
#refer to: https://francisz.cn/2022/05/12/lmbench/
#refer to: https://github.com/bpowers/HBench-OS/blob/master/scripts/gen-latgraph
#refer to: https://docs.nxp.com/bundle/GUID-487B2E69-BB19-42CB-AC38-7EF18C0FE3AE/page/GUID-A3FD5FAE-BA2E-4C6E-BE9B-5270D6E8DD7A.html
#refer to: https://ouc.ai/zhenghaiyong/courses/tutorials/gnuplot/gnuplot-zh.pdf
#refer to: https://gist.github.com/darencard/ffc850949a53ff578260c8b7d3881f28
#refer to: https://github.com/open-power/op-benchmark-recipes/tree/master/standard-benchmarks/Memory/lat_mem_rd_lmbench
#refer to: https://github.com/LucaCanali/Miscellaneous/blob/master/Spark_Notes/Tools_Linux_Memory_Perf_Measure.md
#refer to: https://www.alibabacloud.com/blog/the-mechanism-behind-measuring-cache-access-latency_599384
# cat 2.txt|  gnuplot -p -e "set terminal dumb size 120, 30; set autoscale; plot '-' using 2:3 with lines notitle"
# gnuplot -p -e "set terminal dumb ansirgb; set autoscale;set key top left; plot '<cat mem.nop.txt' u 1:2 w lp ls 1 t 'real', '<cat mem.nop.txt' u 1:3 w lp ls 2 t 'base' "

source 0_common.sh

function test_cache_latency {
	#refer to: https://nexthink.com/blog/smarter-cpu-testing-kaby-lake-haswell-memory
	#refer to: https://www.alibabacloud.com/blog/the-mechanism-behind-measuring-cache-access-latency_599384
	local NAME="mem-lat"
	local SCRIPT_PATH=$(pwd -P)
	show_cmd "cache and memory latency test" $SCRIPT_PATH/$NAME
	gcc -o $SCRIPT_PATH/$NAME $SCRIPT_PATH/${NAME}.c -lpthread 2>/dev/null

	local CPU_CORE=$(lscpu -ap | grep -v '^#' | cut -d, -f2 | sort -nu | wc -l)
	CPU_CORE=$(($CPU_CORE-1))
	local buffer_size=1
	local stride=64
	for i in `seq 1 18`; do
	    numactl -C $CPU_CORE -l $SCRIPT_PATH/$NAME -b $buffer_size -s $stride
	    buffer_size=$(($buffer_size*2))
	done
	rm ${SCRIPT_PATH}/$NAME
}

function test_memory_theory_bandwidth {
	show_cmd "memory theory bandwidth test" "dmidecode -t memory"
	local CMD_OUTPUT=$(sudo dmidecode -t memory | awk '{printf "%s\\n", $0}')  #store the output with \n
	local DDR_CHANNEL=$(echo -e $CMD_OUTPUT | grep -i channel | sort | tail -n 1 | sed -n 's/.*CHANNEL \([^ ]*\).*/\1/Ip')
	DDR_CHANNEL=$(($DDR_CHANNEL+1))
	local DDR_SPD=$(echo -e $CMD_OUTPUT | grep -i speed | sort | uniq | grep MT | tail -n 1 | sed -n 's/.*speed: \([^ ]*\).*/\1/Ip')
	local DDR_DATA_WIDTH=$(echo -e $CMD_OUTPUT | grep -i "data width" | sort | uniq | grep bits | tail -n 1 | sed -n 's/.*width: \([^ ]*\).*/\1/Ip')
	local DDR_THEORY_BW=$(($DDR_SPD*$DDR_DATA_WIDTH/8*$DDR_CHANNEL/1024))
	local DDR_CHANNEL_USED=$(echo -e $CMD_OUTPUT | awk '/GB/ { print; getline;getline;getline;getline;print }' | grep -i channel | uniq | wc -l)
	local USED_DDR_THEORY_BW=$(($DDR_SPD*$DDR_DATA_WIDTH/8*$DDR_CHANNEL_USED/1024))
	echo "Total bank theory DDR BW:" $DDR_THEORY_BW "GB/s"
	echo "Current plugined DDR theory DDR BW:" $USED_DDR_THEORY_BW "GB/s"
}

function test_memory_bandwidth {
	local CMD_OUTPUT=$(sudo numactl -H | awk '{printf "%s\\n", $0}')  #store the output with \n
	local NODES_WITH_DDR=$(echo -e $CMD_OUTPUT | grep -i size | grep -vE '\.*size: 0 MB$' | cut -d' ' -f2)
	local P_CPUS=0
	local CMD_PARAMS="-C "
	for node_id in $NODES_WITH_DDR; do
		local cpus_in_node=$(echo -e $CMD_OUTPUT | grep -i cpus | sed -n "$((${node_id}+1))p" | sed -n 's/.*cpus: //p')
		local first_cpu=$(echo $cpus_in_node | awk '{printf $1}')
		local last_cpu=$(echo $cpus_in_node | awk '{printf $NF}')
		P_CPUS=$(($P_CPUS+$last_cpu-$first_cpu+1))
		if [[ "$CMD_PARAMS" != "-C " ]]; then
			CMD_PARAMS+=","$first_cpu"-"$last_cpu
		else
			CMD_PARAMS+=" "$first_cpu"-"$last_cpu
		fi
	done
	local CMD="numactl $CMD_PARAMS ./lmbench/bin/bw_mem -P $P_CPUS 128m rd"
	show_cmd "memory bandwidth test @xxxMB xxxMB/s " $CMD
	$($CMD)
}

function test_L1_cache_bandwidth {
# L1 Cache size = 64KB
# Instrunction per cyle = 4
	local IPC=4
	local L1_CACHE_SIZE="64k"
	local CMD="sudo perf stat -d numactl -C 2 -l lmbench/bin/bw_mem $L1_CACHE_SIZE rd"
	show_cmd "L1 Cache bandwidth test" $CMD
	local CMD_OUPUT=$($CMD 2>&1 | awk '{printf "%s\\n", $0}')  #store the output with \n
	local L1_LOAD_CNT=$(echo -e $CMD_OUPUT | grep -i L1-dcache-loads | cut -d' ' -f2 | tr -d ',')
	local TMP_BW=$(echo -e $CMD_OUPUT | head -n 1 | cut -d' ' -f2)
	echo "Byte per Load: " $(echo "scale=6; $TMP_BW*1024*1024/$L1_LOAD_CNT" | bc)
}

test_memory_theory_bandwidth

test_memory_bandwidth

# test cache and memory latency
test_cache_latency

test_L1_cache_bandwidth

exit

SIZE="32k 64k 128k 256k 512k 1m 2m 4m 8m 16m 32m 64m 128m"
BW_MEM_TYPE="rd wr rdwr cp frd fwr fcp bzero bcopy"
for t in $BW_MEM_TYPE;
do
	echo "-----------------------------"
	echo "bw_mem < $t >: size(megabytes) bandwidth(megabytes per second)"
	for s in $SIZE;
	do
		$LMBENCH_PATH/bw_mem $s $t
	done
	echo "-----------------------------"
	echo " "
done

echo "-----------------------------"
echo "lat_mem_rd 128m stride=128"
$LMBENCH_PATH/lat_mem_rd 128 128
echo "-----------------------------"
echo " "

echo "-----------------------------"
echo "lat_mem_rd 128m stride=16"
$LMBENCH_PATH/lat_mem_rd -t 128 16
echo "-----------------------------"
echo " "

echo " "
for i in `seq 1 5`
do
	echo “L1, L2, L3 and DDR read latency”
	$LMBENCH_PATH/lat_mem_rd 100M
done

echo "-----------------------------"
echo "par_mem -L 512 -M 64M"
$LMBENCH_PATH/par_mem -L 512 -M 64M
echo "-----------------------------"
echo " "
