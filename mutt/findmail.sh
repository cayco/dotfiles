#!/bin/sh

MESSAGE=$(cat)

NEWALIAS=$(echo "${MESSAGE}" | grep -m 1 ^"From: " | sed s/[\,\"\'\<\>]//g | awk '{$1=""; if (NF == 3) {print $0;} else if (NF == 2) {print $0 $0;} else if (NF > 3) {print $0;}}')


if grep -Fxq "$NEWALIAS" $HOME/.mutt/aliases.txt; then
    :
else
    echo "$NEWALIAS" >> $HOME/.mutt/aliases.txt
    ~/.mutt/addcontact $NEWALIAS 
fi

echo "${MESSAGE}"
