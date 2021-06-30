#!/bin/bash

dir="$HOME/Nicole/NicVision"
if [ ! -d "$dir" ]; then
	mkdir "$dir"
fi
dir="$HOME/.local/lib/python3.6/site-packages"
cd "$dir"
if [ ! -d "$dir" ]; then
	git clone "https://github.com/darthmonkey2004/nv.git"
fi

hasnv=$(which nv)
if [ -z "$hasnv" ]; then
	sudo mv "$dir/nv/nv.run" "/usr/local/bin/nv"
fi
sudo apt-get install -y curl nmap
. "$dir/nv/scancams.sh"
. "$dir/nv/mkconf.sh"
python3 "$dir/nv/mkhtml.py"
echo "Done! To start: run 'nv'. To end: run 'nv kill'."
exit 0
