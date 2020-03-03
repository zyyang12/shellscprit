int=0
count=172800
#count表示脚本运行的秒数
reserve=10
#保留文本行数
while(( $count>$int ))
do
	value=`sed -n "$=" linshi.log`
	#echo $value
	if(($value>$reserve))
	then
		delvalue=$((value-reserve))
	else
		delvalue=0
	fi
	#echo $delvalue
	sed -i "1,${delvalue}d" linshi.log
    let "int++"	
	sleep 1s
done
