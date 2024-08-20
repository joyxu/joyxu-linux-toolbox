#!/bin/bash
#refer to: https://github.com/brendangregg/Misc/blob/master/microbenchmarks/microbench_ubuntu.sh
#refer to: https://francisz.cn/2022/05/12/lmbench/
#refer to: https://github.com/bpowers/HBench-OS/blob/master/scripts/gen-latgraph
#refer to: https://docs.nxp.com/bundle/GUID-487B2E69-BB19-42CB-AC38-7EF18C0FE3AE/page/GUID-A3FD5FAE-BA2E-4C6E-BE9B-5270D6E8DD7A.html
#refer to: https://ouc.ai/zhenghaiyong/courses/tutorials/gnuplot/gnuplot-zh.pdf
#refer to: https://gist.github.com/darencard/ffc850949a53ff578260c8b7d3881f28
#refer to: https://github.com/open-power/op-benchmark-recipes/tree/master/standard-benchmarks/Memory/lat_mem_rd_lmbench
#refer to: https://github.com/LucaCanali/Miscellaneous/blob/master/Spark_Notes/Tools_Linux_Memory_Perf_Measure.md
# cat 2.txt|  gnuplot -p -e "set terminal dumb size 120, 30; set autoscale; plot '-' using 2:3 with lines notitle" 

source 0_common.sh

function calc_cache_size {
	echo "test"
}

echo " "
for i in `seq 1 5`
do
	echo “L1, L2, L3 and DDR read latency”
	$LMBENCH_PATH/lat_mem_rd 100M
done

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

echo "-----------------------------"
echo "par_mem -L 512 -M 64M"
$LMBENCH_PATH/par_mem -L 512 -M 64M
echo "-----------------------------"
echo " "

