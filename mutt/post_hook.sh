#!/bin/bash

bin=notmuch

function notmuch {    
    echo $1
    while [ 1 -gt 0 ]; do
	result=`$bin $1 2>&1` 
	regex="already locked"

	if [[ $result =~ $regex ]]; then
	    echo "Xapian DB busy.  Retrying in 2 seconds"
	else
	    if [ -n "$result" ]; then
		echo $result
	    fi
	    return
	fi

	sleep 2
    done
}

function tag_new { notmuch "tag $1 tag:inbox and ($2)"; }
function blacklist { tag_new "-inbox -unread +delete" $1; }

notmuch new

#blacklist "from:xxx at example.com or from yyy at example.com"

# voicemail
#tag_new "-inbox +voicemail"  "from:ast at example.com"

# friends
#tag_new "+friend +mathieu" "mathieu or ejm2106 or emily at example.com"
#tag_new "+friend +balktick" "balktick"

# open community services
#tag_new "+ocs" "open community services or opencommunityservices"
   

## Mark mine unread
tag_new "-unread" "from:cayco@cayco.pl"
tag_new "-unread" "from:krzysztof.kajkowski@codilime.com"
tag_new "-unread" "from:krzysztof.kajkowski@gmail.com"

## Remove inbox tag
#tag_new "-inbox" "tag:sflc or tag:hv or tag:list or tag:osm or tag:okos or tag:friend or tag:bklib"

