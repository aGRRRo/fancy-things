#!/bin/bash
#Simple Solr Provisioner by Nikolai Khvatov <n.hvatov@gmail.com>
# SOLR_HOST_LIST && ZK_HOST_LIST - can be lists.


availability_check_zk () {
PORT="${ZK_PORT}"
IFS="," read -ra HOSTS <<< "${ZK_HOST_LIST}"
LEN=${#HOSTS[@]}
  for (( i=0; i<"$LEN"; i++)); do
    if [[ $(echo ruok | nc "${HOSTS[$i]}" "${PORT}") == "imok" ]]; then
      ZK_ACTIVE=${HOSTS[$i]}
      echo "${ZK_ACTIVE}"
      exit
    fi
  done
}

availability_check_solr () {
IFS="," read -ra HOSTS <<< "${SOLR_HOST_LIST}"
LEN=${#HOSTS[@]}
  for (( i=0; i<"$LEN"; i++)); do
    SOLR_HOST="${HOSTS[$i]}"
    solr status &> /dev/null
    RETVAL=$?
    if [[ "${RETVAL}" -eq 0 ]]; then
      SOLR_ACTIVE="${HOSTS[$i]}"
      echo "${SOLR_ACTIVE}"
      exit
    fi
  done
}

SOLR_HOST=$(availability_check_solr)
ZOOKEEPER_HOST=$(availability_check_zk)

config_sets_provisioner () {
if [[ -n "${ZOOKEEPER_HOST}" ]]; then
  echo "Active Zookeeper host found: ${ZOOKEEPER_HOST} !"
  echo "Uploading ${ZK_CONF} config sets to Zookeeper!"
  solr zk upconfig -n "${ZK_CONF}" -d "${ZK_CONF}" -z "${ZOOKEEPER_HOST}":"${ZK_PORT}"
    RETVAL=$?
    if [[ "${RETVAL}" -eq 0 ]]; then
      echo "Configs successfully uploaded!"
    else
      echo "Something bad happened within config sets upload!"
      exit 1
   fi
  else
    echo "No Zookeeper host found, no config sets uploaded, however the actual value of ZOOKEEPER_HOST VAR was: ${ZOOKEEPER_HOST} !"
    exit 1
  fi
}


collections_provisioner () {
if [[ -n "${SOLR_HOST}" ]] && [[ -n "${ZOOKEEPER_HOST}" ]]; then
  echo "Active Solr host found: ${SOLR_HOST} !"
  echo "Active Zookeeper host found: ${ZOOKEEPER_HOST} !"
  #export SOLR_HOST
  echo "Checking presence of the Collection ${ZK_CONF} on Solr(${SOLR_HOST})"
  solr healthcheck -c "${ZK_CONF}" -z "${ZOOKEEPER_HOST}" &> /dev/null
      RETVAL=$?
      if [[ "${RETVAL}" -eq 0 ]]; then
            echo "Collection ${ZK_CONF} already exists"
      else
        echo "It looks like there no address_${ZK_CONF_REG} Collection right now, let me create it for you..."
        solr create -c "${ZK_CONF}" -n "${ZK_CONF}" -shards 2
      fi
  else
    echo "No Zookeeper or/and Solr hosts found, collections healthcheck failed, however the actual value of ZOOKEEPER_HOST VAR was: ${ZOOKEEPER_HOST} !"
    exit 1
  fi
}

echo "Provisioning config sets"
config_sets_provisioner || exit 1
echo "Provisioning Collection"
collections_provisioner || exit 1
