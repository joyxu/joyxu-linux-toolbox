#!/usr/bin/env bash

##########
# - list of possibly required packages: curl,gawk,coreutils,util-linux,procps,ioping
##########

source 0_common.sh

function print_head_banner {
	printf '%s\n' '-------------------------------------------------'
	printf 'joyxu cpu micro benchmark  -- https://github.com/joyxu/joyxu-linux-toolbox/benchmark\n'
	date -u '+ benchmark timestamp:    %F %T UTC'
	printf '%s\n' '-------------------------------------------------'
	printf 'system environment infomation calculated from procfs/sysfs\n'
	printf '%s\n' '-------------------------------------------------'

	UPTIME=$(uptime | awk -F'( |,|:)+' '{d=h=m=0; if ($7=="min") m=$6; else {if ($7~/^day/) {d=$6;h=$8;m=$9} else {h=$6;m=$7}}} {print d+0,"days,",h+0,"hours,",m+0,"minutes"}')
	echo -e "Uptime:\t\t\t\t$UPTIME"

	. /etc/os-release
	echo -e "Linux Distribution:\t\t${PRETTY_NAME:-$ID-$VERSION_ID}"

	#KERNEL=$(</proc/sys/kernel/osrelease) # uname -r
	KERNEL=$(uname -srm)
	echo -e "Linux Kernel:\t\t\t$KERNEL"

	file=/sys/class/dmi/id # /sys/devices/virtual/dmi/id
	if [[ -d $file ]]; then
		if [[ -r "$file/sys_vendor" ]]; then
			MODEL=$(<"$file/sys_vendor")
		elif [[ -r "$file/board_vendor" ]]; then
			MODEL=$(<"$file/board_vendor")
		elif [[ -r "$file/chassis_vendor" ]]; then
			MODEL=$(<"$file/chassis_vendor")
		fi
		if [[ -r "$file/product_name" ]]; then
			MODEL+=" $(<"$file/product_name")"
		fi
		if [[ -r "$file/product_version" ]]; then
			MODEL+=" $(<"$file/product_version")"
		fi
	elif [[ -r /sys/firmware/devicetree/base/model ]]; then
		read -r -d '' MODEL </sys/firmware/devicetree/base/model
	fi
	if [[ -n $MODEL ]]; then
		echo -e "Computer Model:\t\t\t$MODEL"
	fi

	CPU_THREADS=$(nproc --all) # getconf _NPROCESSORS_CONF # $(lscpu | grep -i '^cpu(s)' | sed -n 's/^.\+:[[:blank:]]*//p')
	declare -A lists
	for file in /sys/devices/system/cpu/cpu[0-9]*/topology/core_cpus_list; do
		if [[ -r $file ]]; then
			lists[$(<"$file")]=1
		fi
	done
	if ! ((${#lists[*]})); then
		for file in /sys/devices/system/cpu/cpu[0-9]*/topology/thread_siblings_list; do
			if [[ -r $file ]]; then
				lists[$(<"$file")]=1
			fi
		done
	fi
	CPU_CORES=${#lists[*]}
	# CPU_CORES=$(lscpu -ap | grep -v '^#' | cut -d, -f2 | sort -nu | wc -l)
	lists=()
	for file in /sys/devices/system/cpu/cpu[0-9]*/topology/package_cpus_list; do
		if [[ -r $file ]]; then
			lists[$(<"$file")]=1
		fi
	done
	if ! ((${#lists[*]})); then
		for file in /sys/devices/system/cpu/cpu[0-9]*/topology/core_siblings_list; do
			if [[ -r $file ]]; then
				lists[$(<"$file")]=1
			fi
		done
	fi
	CPU_SOCKETS=${#lists[*]}
	# CPU_SOCKETS=$(lscpu -ap | grep -v '^#' | cut -d, -f3 | sort -nu | wc -l) # $(lscpu | grep -i '^\(socket\|cluster\)(s)' | sed -n 's/^.\+:[[:blank:]]*//p' | tail -n 1)

	CPU_FREQ=$(lscpu | grep "CPU max MHz" | sed 's/CPU max MHz: *//g')
	[[ -z "$CPU_FREQ" ]] && CPU_FREQ="???"
	CPU_FREQ="max ${CPU_FREQ} MHz"

	echo -e "CPU Sockets/Cores/Threads:\t$CPU_SOCKETS/$CPU_CORES/$CPU_THREADS@$CPU_FREQ"

	CPU_CACHES=()
	declare -A CPU_NUM_CACHES CPU_CACHE_SIZES CPU_TOTAL_CACHE_SIZES CACHE_LINE_SIZE
	# CPU_L1I_CACHE_SIZE=$(getconf LEVEL1_ICACHE_SIZE)
	# CPU_L1D_CACHE_SIZE=$(getconf LEVEL1_DCACHE_SIZE)
	# CPU_L2_CACHE_SIZE=$(getconf LEVEL2_CACHE_SIZE)
	# CPU_L3_CACHE_SIZE=$(getconf LEVEL3_CACHE_SIZE)
	# CPU_L4_CACHE_SIZE=$(getconf LEVEL4_CACHE_SIZE)
	lists=()
	for dir in /sys/devices/system/cpu/cpu[0-9]*/cache; do
		if [[ -d $dir ]]; then
			for file in "$dir"/index[0-9]*/size; do
				if [[ -r $file ]]; then
					size=$(numfmt --from=iec <"$file")
					file=${file%/*}
					level=$(<"$file/level")
					type=$(<"$file/type")
					if [[ $type == Data ]]; then
						type=d
					elif [[ $type == Instruction ]]; then
						type=i
					else
						type=''
					fi
					name="L$level$type"
					key="$(<"$file/shared_cpu_list") $name"
					if [[ -z ${lists[$key]} ]]; then
						if [[ -z ${CPU_TOTAL_CACHE_SIZES[$name]} ]]; then
							CPU_CACHES+=("$name")
						fi
						((++CPU_NUM_CACHES[$name]))
						CPU_CACHE_SIZES[$name]=$size
						((CPU_TOTAL_CACHE_SIZES[$name] += size))
						lists[$key]=1
					fi
				fi
			done
			for file in "$dir"/index[0-9]*/coherency_line_size; do
				if [[ -r $file ]]; then
					size=$(numfmt --from=iec <"$file")
					file=${file%/*}
					level=$(<"$file/level")
					type=$(<"$file/type")
					if [[ $type == Data ]]; then
						type=d
					elif [[ $type == Instruction ]]; then
						type=i
					else
						type=''
					fi
					name="L$level$type"
					CACHE_LINE_SIZE[$name]=$size
				fi
			done
		fi
	done
	if ((${#CPU_CACHES[*]})); then
		echo -e -n "CPU Caches:\t\t\t"
		for i in "${!CPU_CACHES[@]}"; do
			cache=${CPU_CACHES[i]}
			((i)) && printf '\t\t\t\t'
			echo "$cache: $(printf "%'d" $((CPU_CACHE_SIZES[$cache] >> 10))) KiB × ${CPU_NUM_CACHES[$cache]} pcs,total ($(numfmt --to=iec-i "${CPU_TOTAL_CACHE_SIZES[$cache]}")B)" "?cacheline:" ${CACHE_LINE_SIZE[$cache]}
		done
	fi

	MEMINFO=$(</proc/meminfo)
	TOTAL_PHYSICAL_MEM=$(echo "$MEMINFO" | awk '/^MemTotal:/ { print $2 }') # (( $(getconf PAGE_SIZE) * $(getconf _PHYS_PAGES) ))
	echo -e "Total memory (RAM):\t\t$(toiec "$TOTAL_PHYSICAL_MEM") ($(tosi "$TOTAL_PHYSICAL_MEM"))"

	TOTAL_SWAP=$(echo "$MEMINFO" | awk '/^SwapTotal:/ { print $2 }')
	echo -e "Total swap space:\t\t$(toiec "$TOTAL_SWAP") ($(tosi "$TOTAL_SWAP"))"

	echo -e "clocksource: \t\t\t"$(cat /sys/devices/system/clocksource/clocksource0/current_clocksource)
	echo -e "governor: \t\t\t"$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
}

# Function to get information from IP Address using ip-api.com free API
function get_ip_info() {
	# check for curl vs wget
	[[ ! -z $LOCAL_CURL ]] && DL_CMD="curl -s" || DL_CMD="wget -qO-"

	local ip6me_resp="$($DL_CMD http://ip6.me/api/)"
	local net_type="$(echo $ip6me_resp | cut -d, -f1)"
	local net_ip="$(echo $ip6me_resp | cut -d, -f2)"

	local response=$($DL_CMD http://ip-api.com/json/$net_ip)

	# if no response, skip output
	if [[ -z $response ]]; then
		return
	fi

	local country=$(echo "$response" | sed -e 's/[{}]/''/g' | awk -v RS=',"' -F: '/^country/ {print $2}' | head -1 | sed 's/^"\(.*\)"$/\1/')
	local region=$(echo "$response" | sed -e 's/[{}]/''/g' | awk -v RS=',"' -F: '/^regionName/ {print $2}' | sed 's/^"\(.*\)"$/\1/')
	local region_code=$(echo "$response" | sed -e 's/[{}]/''/g' | awk -v RS=',"' -F: '/^region/ {print $2}' | head -1 | sed 's/^"\(.*\)"$/\1/')
	local city=$(echo "$response" | sed -e 's/[{}]/''/g' | awk -v RS=',"' -F: '/^city/ {print $2}' | sed 's/^"\(.*\)"$/\1/')
	local isp=$(echo "$response" | sed -e 's/[{}]/''/g' | awk -v RS=',"' -F: '/^isp/ {print $2}' | sed 's/^"\(.*\)"$/\1/')
	local org=$(echo "$response" | sed -e 's/[{}]/''/g' | awk -v RS=',"' -F: '/^org/ {print $2}' | sed 's/^"\(.*\)"$/\1/')
	local as=$(echo "$response" | sed -e 's/[{}]/''/g' | awk -v RS=',"' -F: '/^as/ {print $2}' | sed 's/^"\(.*\)"$/\1/')

	echo
	echo "$net_type Network Information:"
	echo "---------------------------------"

	if [[ -n "$isp" ]]; then
		echo -e "ISP:\t\t\t\t$isp"
	else
		echo -e "ISP:\t\t\t\tUnknown"
	fi
	if [[ -n "$as" ]]; then
		echo -e "ASN:\t\t\t\t$as"
	else
		echo -e "ASN:\t\t\t\tUnknown"
	fi
	if [[ -n "$org" ]]; then
		echo -e "Host:\t\t\t\t$org"
	fi
	if [[ -n "$city" && -n "$region" ]]; then
		echo -e "Location:\t\t\t$city, $region ($region_code)"
	fi
	if [[ -n "$country" ]]; then
		echo -e "Country:\t\t\t$country"
	fi

	[[ ! -z $JSON ]] && JSON_RESULT+=',"ip_info":{"protocol":"'$net_type'","isp":"'$isp'","asn":"'$as'","org":"'$org'","city":"'$city'","region":"'$region'","region_code":"'$region_code'","country":"'$country'"}'
}

print_head_banner
get_ip_info

run "system topo" $WAYCA_PATH/tools/wayca-lstopo
