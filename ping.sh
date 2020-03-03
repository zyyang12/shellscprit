#!/bin/bash
#服务器网络状态监控
int=0
count=172800
#count表示脚本运行的秒数
while(( $count>$int ))
do
	ping -n 2 172.31.103.101
	if [ $? -eq 0 ]
	then
		echo -e $int" yes \c" >>ping.log
		echo `date` >>ping.log
	else
		echo -e $int"no \c" >>ping.log
		echo `date` >>ping.log
	fi
	let "int++"
	sleep 1s
	echo $int
done
