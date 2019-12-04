#! /bin/bash

# 全局初始化部分
init()
{
	# get param
	period=read_command 	# 命令阶段，在读取指令时区分当前参数对应的命令词
	delay=2000	# 统计间隔，每隔多少时间统计一次，单位ms
	interval="\t"	# 统计数据之间的间隔，默认\t，如果是csv格式的话，则是逗号
	suffix=".txt"	# 统计结果的后缀名，如果指定csv格式，则是.csv，否则默认.txt
	is_net_stat=false	# 是否要统计发送接收字节数，0表示否，1表示是
	is_core_stat=false	# 是否要统计每个核的信息，	
	has_gpu=false	# 是否有gpu核，主要看nvidia-smi命令是否有效
	is_continue=false # 默认检查到无相关进程就结束，设定为true时一直持续检查直至手动kill
	for i in $@; do
		if [ $period = read_command ]; then
			if [ $i = -n ]; then
				# 进程名
				period=get_app_name
			elif [ $i = -i ];then
				# 进程id，一旦定义此项，进程名将被忽略
				period=get_app_id
			elif [ $i = -d ];then
				# 统计间隔，单位ms
				period=get_delay
			elif [ $i = -o ];then
				# 输出目录
				period=get_output_dir
			elif [ $i = -csv ];then
				# 输出格式，如选择csv则是.csv格式，在输出时以逗号间隔，其他格式
				interval=,
				suffix=.csv
			elif [ $i = -net ];then
				# 输出发送接收字节数，仅root权限可以查看特定端口的网络吞吐量
				if [ "root" != `whoami` ];then
					echo "Error: only root user can use param '-net' "
					exit
				fi
				#if [[ `iftop -h 2>&1` =~ "usage" || `iftop -h 2>&1` =~ "用法" ]];then
				if [[ `iftop -h 2>&1` =~ "iftop, version 1.0pre4" ]];then
				#if true;then
					is_net_stat=true
				else
					echo "Error: cannot find command iftop(version 1.0pre4)"
					echo "Info: you can use 'sudo apt-get install' to install iftop"
					echo "Info: or you may need root account to get permission"
					# 注意，iftop命令从1.0pre3版本开始才支持文本输出
					echo "Info: or you should update your iftop command to version 1.0pre4"
					exit
				fi
			elif [ $i = -core ];then
				# 附带统计每个核的使用情况，包括gpu核
				if [ `command -v mpstat` ];then
					is_core_stat=true
				else
					echo "Error: please install sysstat to monitor every cpu"
					exit
				fi		
				if [ `command -v nvidia-smi` ];then
					has_gpu=true
				else
					echo "Info: no gpu found. command \"nvidia-smi\" has no result"
				fi
			elif [ $i = -continue ];then
				is_continue=true
			elif [ $i = -stop ];then
				period=stop_self
			elif [ $i = -stopall ];then 
				script_name=`echo $0 | sed 's/.*\///g'`
				for i in `ps aux | grep $script_name | grep -v grep | grep -v gedit | grep -v stop | awk '{print $2}'`; do
					kill $i
				done
				exit
			elif [ $i = -help -o $i = -h -o $i = --help -o $i = --h ];then
				helpInfo
				exit
			fi
		elif [ $period = get_app_name ]; then
			appname=$i
			period=read_command
		elif [ $period = get_app_id ];then
			appid=$i
			period=read_command
		elif [ $period = get_delay ];then
			delay=`echo $i | bc`
			if [ ! $delay ];then
				delay=2000
			fi
			period=read_command
		elif [ $period = get_output_dir ];then
			output_dir=$i
			period=read_command
		elif [ $period = stop_self ];then
			script_name=`echo $0 | sed 's/.*\///g'`
			for j in `ps aux | grep $script_name | grep $i | grep -v grep | grep -v gedit | grep -v stop | awk '{print $2}'`; do
				kill $j
			done
			exit
		fi
	done

	# 0-no app defined; 1-appname defined; 2-appid defined
	keyword=
	# check param validation
	if [ "$appname" ];then
		echo "Info: set appname as $appname"
		keyword=$appname
	fi
	if [ "$appid" ];then
		echo "Info: set appid as $appid! appname ignored"
		keyword=$appid
	fi
	
	if [ `expr $delay \> 0` -eq 0 ];then
		delay=2000
		echo "Info: no valid time interval defined! Set default as $delay seconds!"
	fi
	
	if [ ! "$output_dir" ];then
		timestamp=`date +%Y-%m-%d_%H-%M-%S`
		output_dir=./$keyword\_$timestamp
		echo "Info: no valid output path defined! Set default as $output_dir"
	fi

	if [ ! "${appname}${appid}" ];then
		echo "Error: Invalid Command. Should define process name or id"
		helpInfo
		exit
	fi

	if [ -d $output_dir ];then
		echo "Warning: $output_dir already exists!"
	elif [ -f $output_dir ];then
		echo "Error: A file named $output_dir already exists!"
	else
		mkdir -p $output_dir
	fi
	
	# 根据$is_continue参数判断在当前不存在某进程的情况下，是否需要结束监测
	if ! $is_continue;then
		pids=`ps -A | grep "\b$appid\b" | grep "\b$appname\b" | awk '{print $1}'`
		if [ ! "$pids" ];then
			echo "Error: No Such Process: $keyword"
			exit 0
		fi
	fi

	if [ "root" != `whoami` ];then
		echo "Warning: You are not root. You cannot get the number of file handlers of others' processes! "
	fi
}

helpInfo(){
	echo "Standard Format As Below:"
	echo "/bin/bash $0 [-n appname(进程名)][-i appid(进程号)][-d time_interval(监控时间间隔,ms)][-o output_dir(输出目录)][-csv(输出格式，csv格式，以逗号间隔)][-net显示发送接收字节数，需要root权限，并且安装iftop version 1.0pre4][-core统计每个cpu/gpu核的用户利用率，需要安装sysstat][-continue 一直持续检查][-stop <keyword>根据关键词结束正在运行的本脚本][-stopall 结束所有正在运行的本脚本][-help 显示帮助信息]"
}

getNet(){	#send_flow receive_flow, 单位kb
	temp_iftop_result="$output_dir/_temp_iftop.`date +%s%N`"	# 临时文件，用以存储一些临时的信息，最后会删除
	iftop -Pp -Nn -t -L 100 -s 1 >$temp_iftop_result 2>&1
	port_list=`netstat -plnt|grep $pid|awk '{print $4}'|awk -F: '{print $2}'|sed 's/\\s/\|/g'`
	if [ ! "$port_list" ];then
		result="0${interval}0"
	else
		temp_stat_result="$output_dir/_temp_stat.`date +%s%N`"	# 临时文件，用以存储一些临时的信息，最后会删除
		send_flow=`cat $temp_iftop_result |grep -E "${port_list}"|grep -E 'Mb|Kb'|grep '=>'|awk '{print $4}'|tr '\n' '+' |sed -e s/Mb/*1000/g |sed s/Kb//g |sed 's/\(.*\)+$/\1\n/g'|bc`
		if [ ! "$send_flow" ];then
			send_flow=0
		fi
		send_num=`cat $temp_iftop_result |grep -E "${port_list}"|grep "=>"|awk '{print $1}'`
		echo "" > $temp_stat_result
		for num in $send_num
		do
			cat $temp_iftop_result |grep '<='|sed -n ${num}p|grep -E 'Mb|Kb' >>$temp_stat_result
		done
		receive_flow=`cat $temp_stat_result |grep -E 'Mb|Kb'|awk '{print $4}'|tr '\n' '+' |sed -e s/Mb/*1000/g |sed s/Kb//g |sed 's/\(.*\)+$/\1\n/g'|bc`
		if [ ! "$receive_flow" ];then
			receive_flow=0
		fi
		result="${send_flow}${interval}${receive_flow}"
		rm $temp_stat_result
	fi
	rm $temp_iftop_result
	echo $result
}

write_data(){
	process_info=`top -p $pid -n 1 -b | grep $keyword`
	process_info_array=($process_info)	# 获取进程信息的数组
	
	if [ ! $process_info_array ];then
		echo "Info: Process $pid End!"
		return
	fi
	virt=`cat /proc/$pid/status | grep VmSize | awk '{print $2}'`	# 虚拟内存占用
	res=`cat /proc/$pid/status | grep VmRSS | awk '{print $2}'`	# 物理内存占用

	handle=`ls /proc/$pid/fd 2>/dev/null | wc -l`
	thread_cnt=$(awk '{print $20}' /proc/$pid/stat)	# 线程数
	free_m=$(free -m | sed -n 3p | awk '{print $4}')	# 空闲内存
	
	user=${process_info_array[1]}		# 用户名
	cmd_name=${process_info_array[11]}	# 进程名
	cpu_percent=${process_info_array[8]}	# cpu占用百分比
	
	log_name=${user}_${pid}_${cmd_name}${suffix}	# 输出文件名字
	#若文件不存在，写入文件头;若文件存在，将会直接追加	
	if [ ! -e $output_dir/$log_name ];then
		log_title="time${interval}pid${interval}handle${interval}thread${interval}virt(KB)${interval}res(KB)${interval}cpu_percent${interval}free_memory(MB)"
		if $is_net_stat;then
			log_title="${log_title}${interval}send_flow(Kb)${interval}receive_flow(Kb)"
		fi
		echo -e $log_title >$output_dir/$log_name
	fi

	#写数据
	if [ "${virt}${res}${thread_cnt}" ];then
		now=`date +"%Y/%m/%d_%H:%M:%S"`
		out_line=${now}${interval}${pid}${interval}${handle}${interval}${thread_cnt}${interval}${virt}${interval}${res}${interval}${cpu_percent}${interval}${free_m}
		#echo -e $out_line
		if [ -f $output_dir/$log_name ];then
			if $is_net_stat;then
				out_line="${out_line}${interval}`getNet`"
			fi
			echo -e $out_line >>$output_dir/$log_name
		else
			echo "Error: Fail To Print Log To $output_dir/$log_name"
		fi
	fi

	#echo "`getNet` $user"
	#echo "$out_line" >>$output_dir/$log_name
}

# 依次记录每个进程的信息
record_all_process()
{
	echo "record_all_process begin"
	
	while :
	do
		loop &
		sleep `echo "scale=2; $delay/1000" |bc`
		
		#等待后台线程结束
		#wait
	done
}

#轮询遍历符合条件的进程
loop()
{
	pids=$(ps -A | grep "$keyword\b" | awk '{print $1}')
	if [ ! "$pids" ];then			
	# 当不存在该进程时，判断是否需要继续监测
		if ! $is_continue;then
			echo "Info: Process $keyword End!"
			exit 0
		fi
	fi
	for pid in $pids
	do
		write_data &
	done
	#分核统计数据
	print_cpu_info
	wait
}

#记录分核统计数据
print_cpu_info()
{
	if $is_core_stat;then
		core_info_line=`date +"%Y/%m/%d %H:%M:%S"` # 获取当前时间
		
		core_info_line="$core_info_line `mpstat -P ALL | tail -n +5 | sed 's/.* //g' | awk '{print (100-$0)}'`"	# 获取cpu信息
		if $has_gpu;then
			core_info_line="$core_info_line `nvidia-smi -a | grep Gpu | sed s/Gpu/gpu/g | grep % | awk '{print $3}'`" # 获取gpu信息
		fi
		echo $core_info_line | sed "s/ /$interval/g">>$core_stat_file	# 输出到log文件中
	fi
}

# *************************************
# main
# *************************************
init $@
# 打印cpu信息的头
if $is_core_stat;then
	core_stat_file=$output_dir/core_info${suffix}
	core_stat_title="date time $core_stat_title `mpstat -P ALL | tail -n +5 | awk '{print "cpu_"$2}'`" # 获取cpu号
	if $has_gpu;then
		core_stat_title="$core_stat_title `nvidia-smi -a | grep Gpu | sed s/Gpu/gpu/g | grep % | awk '{print $1"_"NR-1}'`" # 获取gpu号
	fi
	echo $core_stat_title | sed "s/ /$interval/g" >$core_stat_file # 输出到log文件中
fi

record_all_process
exit 0
