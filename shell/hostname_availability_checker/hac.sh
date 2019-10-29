#!/bin/bash

helper()
{
   echo ""
   echo "Usage: $0 -r -i <Input data>"
   echo -e "\t-r recursive((script will iterate though whole list and print active hosts) or non-recursive(script will check hosts until first available one)"
   echo -e "\t-i  Input data. Comma separated list of hosts or IPs is required\nExample: \"www.example.com,example.net,93.184.216.34\""
   exit 1 # Exit script after printing help
}

while getopts "ri:" opt
do
   case "$opt" in
       r ) parameter1="true" ;;
       i ) parameter2="$OPTARG" ;;
       ? ) helper ;; # Print helpFunction in case parameter is non-existent
   esac
done

if [[ -z "$parameter2" ]]
then
   echo -e "No argument supplied\nComma separated list of hosts or IPs is required\nExample: \"www.example.com,example.net,93.184.216.34\""
   helper
fi

IFS="," read -ra HOSTS <<< "$parameter2"
LEN=${#HOSTS[@]}

availability_check () {
  for (( i=0; i<"$LEN"; i++)); do
    if [[ $(ping -q -c1 "${HOSTS[$i]}" 2>/dev/null) ]]; then
      RESULT=${HOSTS[$i]}
      echo "${RESULT}"
      exit
    fi
  done
}

availability_check_recursive () {
  for (( i=0; i<"$LEN"; i++)); do
    if [[ $(ping -q -c1 "${HOSTS[$i]}" 2>/dev/null) ]]; then
      RESULT=${HOSTS[$i]}
      echo "${RESULT}"
    fi
  done
}

if [[ "$parameter1" ]]; then
    availability_check_recursive
  else
    availability_check
fi
