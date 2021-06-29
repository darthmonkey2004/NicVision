ipWebCam() {
	read -p "Does this camera have authentication? (y/n): " yn
	if [ "$yn" = "y" ]; then
		read -p "Enter username for video stream:" user
		read -s -p "Enter password: " pass
		addurl="rtsp://$user:$pass@$ip:$port/h264_pcm.sdp"
	else
		addurl="rtsp://$ip:$port/h264_pcm.sdp"
	fi
	echo "$addurl"
}

testIpCam() {
	if [ -n "$1" ]; then
		ip="$1"
	fi
	if [ -n "$2" ]; then
		port="$2"
	fi
	readarray ary <<< $(nmap -sV --script "rtsp-*" -p $port $ip | grep -v "Nmap done:")
	go=''
	stop=''
	start="discovered:"
	end="other responses:"
	results=()
	urls=()
	for i in "${ary[@]}"; do
		line=$(echo "$i" | cut -d $'\n' -f 1)
		test=$(echo "$line" | grep "$start")
		if [ -n "$test" ]; then
			go=1
		fi
		test=$(echo "$line" | grep "$end")
		if [ -n "$test" ]; then
			stop=1
		fi
		if [ -n "$go" ] && [ -n "$stop" ]; then
			break
		fi
		if [ -n "$go" ] && [ -z "$top" ]; then
			line=$(echo "$line" | xargs | cut -d ' ' -f 2)
			d=$(echo "$line" | grep "discovered")
			if [ -z "$d" ]; then
				results+=("$line")
			fi
		fi
	done
	pos=0
	for i in "${results[@]}"; do
		pos=$(( pos + 1 ))
		fname="temp.$pos.jpg"
		ffmpeg -loglevel quiet -stats -y -rtsp_transport tcp -i "$i" -frames:v 1 $fname
		if [ -f "$fname" ]; then
			#xdg-open "$fname"
			info=$(jpeginfo "$fname" | xargs)
			h=$(echo "$info" | cut -d ' ' -f 4)
			w=$(echo "$info" | cut -d ' ' -f 2)
			urls+=("$i($h,$w)")
			rm "$fname"
		fi
	done
	first="${urls[0]}"
	if [ -z "$first" ]; then
		urls=()
	fi
	echo "${urls[@]}"
}

getPort() { 
	url="$1"
	services=$(nmap "$url")
	rtsp=$(echo "$services" | grep "rtsp" | cut -d '/' -f 1)
	rtmp=$(echo "$services" | grep "rtmp" | cut -d '/' -f 1)
	ipwebcam=$(echo "$services" | grep "sd" | cut -d '/' -f 1)
	if [ -n "$ipwebcam" ]; then
		ret=$ipwebcam
	fi
	if [ -n "$rtmp" ]; then
		ret=$rtmp
	fi
	if [ -n "$rtsp" ]; then
		ret=$rtsp
	fi
	if [ -z "$ret" ]; then
		ret=''
	fi
	echo "$ret"
}

testAuth() {
	if [ -n "$1" ]; then
		ip="$1"
	else
		read -p "Enter ip address:" ip
	fi
	if [ -n "$2" ]; then
		auth="$2"
	else
		read -p "Enter username:password - " auth
	fi
	user=$(echo "$auth" | cut -d ':' -f 1)
	pw=$(echo "$auth" | cut -d ':' -f 2)
	if [ -f "index.html" ]; then
		rm index.html
	fi
	httpport=$(nmap $ip | grep "http" | grep "/tcp" | xargs | cut -d '/' -f 1)
	if [ ! "$httpport" -gt "0" ]; then
		echo "Couldn't get http port."
		read -p "Please enter port to try: " httpport
	fi
	wget "http://$user:$pw@$ip:$httpport/"
	success=$(ls "index.html")
	if [ -z "$success" ]; then
		echo "False"
	else
		echo "$user:$pw@$ip"
	fi
}

scanIP() {
	if [ -z "$1" ]; then
		read -p "Enter ip: " ip
	else
		ip="$1"
	fi
	port=$(getPort $ip)
	if [ -z "$port" ]; then
		skip=1
	elif [ -n "$port" ]; then
		skip=0
		echo "Possible camera found at '$ip:$port'..."
	fi
	if [ "$skip" = "0" ]; then
		echo "Starting scan on port $port at $ip. This may take a moment, please wait..."
		if [ "$port" -eq "9876" ]; then
			addurl=$(ipWebCam)
		else
			urls=$(testIpCam $ip $port)
			urls=($urls)
			pos=0
			ary=()
			ct="${#urls[@]}"
			if [ "$ct" = "0" ]; then
				secs=0
				attempts=1
				while [ "$attempts" != "3" ]; do
					echo "Unable to get good urls for camera at '$ip', retrying in 15 seconds (attempt $attempt/3)..."
					sleep 15
					urls=$(testIpCam $ip $port)
					urls=($urls)
					pos=0
					ary=()
					ct="${#urls[@]}"
					if [ "$ct" = "0" ]; then
						attempts=$(( attempts + 1 ))
					else
						read -p "Authentication probably required. Please enter string as 'user:pass' now..." auth
						urls=$(testIpCam "$auth:$ip" $port)
						urls=($urls)
						ct="${#urls[@]}"
						if [ "$ct" = "0" ]; then
							echo "Still failed. Aborting validation for 'ip:$port' ('$user:$pass')..."
							break
						fi
					fi
				done
			fi
			ct="${#urls[@]}"
			echo "Good urls: $ct"
			if [ "$ct" == 0 ]; then
				echo "Couldn't find good urls. Skipping..."
				skip=1
			else
				skip=0
			fi
			if [ "$skip" == "0" ]; then
				for u in "${urls[@]}"; do
					pos=$(( pos + 1 ))
					echo "$pos. $u"
				done
				read -p "Enter a number of the resolution/url to use: " num
				#adjust entered number to account for arrays starting at 0
				num=$(( num - 1 ))
				addurl="${urls[$num]}"
				src=$(echo "$addurl" | cut -d '(' -f 1)
				if [ -z "$src" ]; then
					echo "Error: No url parsed. (addurl='$addurl'). Skipping..."
				fi
			fi
		fi
		ary=()
		IFS=$'\n' readarray data <<< $(python3 -c "import nv; print (nv.readConfToShell())")
		ct="${#data[@]}"
		echo "Current configured camera sources: '$ct'"
		fi
		pos=0
		echo "$ct current cameras in list!"
		for url in "${ary[@]}"; do
			pos=$(( pos + 1 ))
			url=$(echo "$url" | cut -d $'\n' -f 1)
			echo "Adding url '$url' to camera config file..."
			python3 -c "import nv; cams = nv.CAMERAS; ct = len(cams) + 1; cams[ct] = '$url'; nv.writeConf(cams); print(nv.readConfToShell())"
		done

		echo "$result"
}

scanNetwork() {
	iprange="$subnet.0/24"
	readarray iplist <<< $(nmap -sn $iprange | grep "$subnet")
	hosts=()
	for i in "${iplist[@]}"; do
		testname=$(echo $i | grep "(*)")
		if [ -n "$testname" ]; then
			ip=$(echo $i | cut -d ' ' -f 6 | cut -d ')' -f 1 | cut -d '(' -f 2)
		else
			ip=$(echo $i | cut -d ' ' -f 5)
		fi
		hosts+=("$ip")
	done
	echo "${hosts[@]}"
}

cams_autoAdd() {
	localip=$(ifconfig | grep "192.168." | xargs | cut -d ' ' -f 2)
	if [ -z "$localip" ]; then
		echo "Error: No network hardware seems to be connected. Solve this problem and try again."
		exit 1
	fi
	net1=$(echo "$localip" | cut -d '.' -f 1)
	net2=$(echo "$localip" | cut -d '.' -f 2)
	net3=$(echo "$localip" | cut -d '.' -f 3)
	subnet="$net1.$net2.$net3"
	echo "Executing search on local subnet ($subnet)..."
	hosts=$(scanNetwork)
	hosts=($hosts)
	echo "Scan complete. Found total of "${#hosts[@]}" online hosts. Beginning service discovery..."
	for host in "${hosts[@]}"; do
		skip=0
		cams=$(python3 -c "import nv; print (nv.CAMERAS)")
		exists=$(echo "$cams" | grep "$host")
		if [ -n "$exists" ]; then
			test=$(echo "$exists" | cut -d '/' -f 3)
			if [ "$test" = "$host" ]; then
				read -p "Host '$host' already exists in config file. Add anyway? (y/n): " yn
				if [ "$yn" = "n" ] || [ -z "$yn" ]; then
					skip=1
				else
					skip=0
				fi
			fi
		fi
		if [ "$skip" = "0" ]; then
			scanIP "$host"
		fi
	done
	echo "Local network cameras configured!"
	read -p "Run camera server? (y/n): " yn
	if [ "$yn" = "y" ]; then
		runServer;
		exit 0
	else
		echo "Exiting..."
		exit 0
	fi
}

runServer() {
	python3 nv.py& disown
	sleep 5
	xdg-open "http://$localip:5000/"
}
jpeginfo=$(which jpeginfo)
if [ -z "$jpeginfo" ]; then
	sudo apt-get install -y jpeginfo
fi
dir=$(pwd)
conf=$(python3 -c "import nv; print (nv.CONF)")
if [ ! -f "$conf" ]; then
	echo "Camera configuration file not found. Creating..."
	touch "$conf"
fi
if [ -z "$1" ]; then
	com=cams_autoAdd
else
	function="$1"
	echo "Executing function '$function'..."
	if [ -n "$2" ]; then
		com="$function $2"
		if [ -n "$3" ]; then
			com="$com $3"
		fi
	else
		com="$function"
	fi
fi
$com;
echo "Finished! Exiting..."
exit 0
