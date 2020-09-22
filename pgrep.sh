#pattern=$1
#parallel=8
#blocks=$(stat -c '%b' access_log_sample)
#block_size=$(stat -c '%B' access_log_sample)
#offset=$(($blocks/$parallel))
#tmp_files=""
command_args=""
grep_parser(){

	while [[ -n "$1" ]]
	do

		case "${1}" in
			--help)  printf "help"
				exit
				;;

			-V)
				printf "version"
				exit
				;;

			--version)
				printf "version long"
				exit
				;;
			-F)
				command_args=`printf "${command_args} --fixed-stirngs"`
				;;

			-G)
				command_args=`printf "${command_args} --basic-regexp"`
				;;

			-P)
				command_args=`printf "${command_args} --perl-regexp"`
				;;
			-e) 
				shift
				patterns="$1"
				command_args="${command_args} --regexp=${patterns}"
				;;

			-f)
				shift
				file="$1"
				command_args="${command_args} --FILE=${file}"
				;;
			-i|-y)
				command_args="${command_args} --ignore-case"
				;;
			-v)
				command_args="${command_args} --invert-match"
				;;

			-w)
				command_args="${command_args} --word-regexp"
				;;
			-x)
				command_args="${command_args} --line-regexp"
				;;
			-c|--count)
				countresults="TRUE"
				;;
			##UNSUPORTED OPTIONS
			--color)
				unsupported_option "$1"
				exit 1
				;;
			-L|-l|-m|-r|-b|-H|-T|--initial-tab|-u|--unix-byte-offset|-A|-B|-C)
			      	unsupported_option "$1"
				exit 1
				;;
			--after-context=*|--before-contex=*|--group-seperator|--no-group-seperator)
				unsupported_option "$1"
				exit 1
				;;
			--binary-files=*|-D|--exclude=*)
				unsupported_option "$1"
				exit 1
				;;
			*)
				if [[ $first_run != "true" ]]; then
					pattern=$1
					first_run="true"
				else
					filenames="${filenames} $1"
				fi
				;;

		esac
	shift
	done
}

unsupported_option(){
	printf "%s option is currently unsupported" "$1"
	exit 1
}

grep_parser "$@"
filenames=$(echo $filenames|sed 's/^[[:space:]]*//')
#echo grep $command_args -e $pattern -f $filenames


	#ensure command accepts grep syntax and understands what to do
	#-a --text procress file as text

	#check length of arguments

	#check for unsupported options
	#--color would be a reduce operation
	#-L -l initially skipped
	#-m requires better job control syntax
	#-r
	#-b --byte-offset
	#-H --with-filename
	#-n --line-number requires fixup
	#-T --initial-tab : wont work with split logic
	#-u --unix-byte-offset only for does text
	#-A num --after-context=NUM split doesn't guarentee file is available
	#-B NUM --before-context ^^
	#-C NUM ^^
	#--group-separator=SEP for above
	#--no-group-seperator
	#--binary-files=TYPE
	#-D ACTION --devices don't want to mess with devices
	#--exclude=GLOB
	



parallel_cores(){
	core_count=`ls /sys/bus/cpu/devices|wc -l`
	echo "$core_count"
}

do_parallel_grep(){
	core_count=4
	parallel=4
	# multiple files
	if [[ $(echo $filenames | wc -w) > 1 ]]; then
		for file in ${filenames}; do
			if [[ $(jobs -l |grep grep | wc -l) > ${core_count} ]]; then
				wait < <(jobs -p)
			fi
			tmp_file=$(mktemp)
			tmp_files="$tmp_files $tmp_file"

			if [[ $count == "true" ]]; then
				command_args="$command_args --count --with-filename"
			fi

			(grep $command_args $pattern $file > $tmp_file) &
		done
	else
		blocks=$(stat -c '%b' $filenames)
		block_size=$(stat -c '%B' $filenames)
		offset=$(($blocks/$core_count))
	
		for (( c=0; c<$core_count; c++ )); do
			tmp_file=`mktemp tmp.${parallel}.XXXXXX`
			tmp_files=`echo $tmp_files $tmp_file`
			(dd bs=$block_size skip=$(($offset*$c)) count=$(($offset)) if=$filenames status=none|grep $command_args $pattern > $tmp_file)  &
		done
	fi

	wait < <(jobs -p)
	if [[ $(printf "%s" $filenames | wc -w) > 1 ]]; then
		for ((c=1; c<=$parallel; c++)); do
		        last=`dd bs=$block_size skip=$(($offset*$c-1)) count=1 if=$filenames status=none|tail -1`
			first=`dd bs=$block_size skip=$(($offset*$c)) count=1 if=$filenames status=none|head -1`
			if match=`echo "${last}" | grep $pattern` ; then
				for file in $tmp_files; do
					match="tmp.$(($c-1))."
					if [[ ${file} =~ $match ]]; then
					sed -i '$d' ${file}
					fi
				done
			fi

			if match=`echo "${first}" | grep $command_args $pattern` ; then
				for file in $tmp_files; do
					match="tmp.$(($c))."
					if [[ ${file} =~ $match ]]; then
						sed -i '1d' ${file}
					fi
				done
			fi
			if match=`echo "${last}${first}" | grep $command_args $pattern` ; then
				for file in $tmp_files; do
					match="tmp.$(($c-1))."
						if [[ ${file} =~ $match ]]; then
							echo "${last}${first}" > ${file}
						fi
				done
			fi
		done
	fi

wait < <(jobs -p)

for file in $tmp_files; do
	cat $file
	rm $file
done

}


do_parallel_grep
