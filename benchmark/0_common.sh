#!/usr/bin/env bash

##########
# - list of possibly required packages: curl,gawk,coreutils,util-linux,procps,ioping
##########

#DATADIR=/mnt/microbench
LMBENCH_PATH=$PWD/lmbench/bin
WAYCA_PATH=$PWD/wayca-scheduler/build
STRESS_NG=$PWD/stress-ng/stress-ng

#LOGFILE=$PWD/out.microbench.$$

COLOR_NONE='\033[0m'
COLOR_INFO='\033[0;36m'
COLOR_ERROR='\033[1;31m'

SCRIPT_PATH=`pwd -P`

function compile() {
    CC=g++
    OPT="-std=c++11"
    case $3 in
        1) OPT="${OPT} -g";; 
        2) OPT="${OPT} -fpermissive -O2 -pthread";;
        3) OPT="${OPT} -march=native";;
        *) ;;
    esac
    echo "compile program with \"${OPT}\""
    ${CC} ${OPT} -o $2 $1
}

function compile_name() {
    NAME=${1}
    SOURCE=${SCRIPT_PATH}/${NAME}.cpp
    TARGET=${SCRIPT_PATH}/${NAME}
    compile ${SOURCE} ${TARGET} $2 
}

### run: name command [arguments ...]
function run {
	( echo ----------------------------------------
	echo BENCHMARK: $1
	echo ---------------------------------------- ) | tee -a $LOGFILE
	shift
	( echo RUN: "$@"
	echo
	sudo $@ ) > >(tee -a $LOGFILE)
}

function run_with_time {
	( echo ----------------------------------------
	echo BENCHMARK: $1
	echo ---------------------------------------- ) | tee -a $LOGFILE
	shift
	( echo RUN: "$@"
	echo
	sudo time $@
	echo
	echo EXIT STATUS: $? ) > >(tee -a $LOGFILE)
}

### show_cmd: name command [arguments ...]
function show_cmd {
	echo ----------------------------------------
	echo BENCHMARK: $1
	echo ----------------------------------------
	shift
	echo RUN: "$@"
}

function die {
	echo >&2 "$@"
	exit 1
}

function addpkgs {
	all=1
	for pkg in "$@"; do
		if ! dpkg -s $pkg > /dev/null; then all=0; fi
	done
	if (( all )); then
		echo "All packages already installed."
	else
		sudo apt-get update
		for pkg in "$@"; do
			sudo apt-get install -y $pkg
		done
	fi
}

# toiec <KiB>
function toiec() {
	echo "$(printf "%'d" $(($1 >> 10))) MiB$([[ $1 -ge 1048576 ]] && echo " ($(numfmt --from=iec --to=iec-i "${1}K")B)")"
}

# tosi <KiB>
function tosi() {
	echo "$(printf "%'d" $(((($1 << 10) / 1000) / 1000))) MB$([[ $1 -ge 1000000 ]] && echo " ($(numfmt --from=iec --to=si "${1}K")B)")"
}

function command_exists() {
	command -v "$@" > /dev/null 2>&1
}

source spinner.sh
