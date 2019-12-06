#!/bin/bash
#Simple Solr Provisioner by Nikolai Khvatov <nikolai_khvatov@epam.com>

CONF_DIR=${ZK_CONF_DIR}
CONF_SET=${ZK_CONF_NAME}


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
  echo "Uploading ${CONF_SET} config sets to Zookeeper..."
  solr zk upconfig -n "${CONF_SET}" -d "${CONF_DIR}" -z "${ZOOKEEPER_HOST}":"${ZK_PORT}"
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
PORT=${SOLR_PORT}
SHARDS_NUM=2
SHARDS_PNODE=2
REPL_FACTOR=2
if [[ -n "${SOLR_HOST}" ]] && [[ -n "${ZOOKEEPER_HOST}" ]]; then
  echo "Active Solr host found: ${SOLR_HOST} !"
  echo "Active Zookeeper host found: ${ZOOKEEPER_HOST} !"
  echo "Checking presence of the Collection ${CONF_SET} on Solr(${SOLR_HOST})..."
  curl "http://${SOLR_HOST}:${PORT}/solr/admin/collections?action=LIST&wt=json" -s | grep -q "${CONF_SET}"
      RETVAL=$?
      if [[ "${RETVAL}" -eq 0 ]]; then
            echo "Collection ${CONF_SET} already exists, you are ready to go!"
            exit 0
      else
        echo "It looks like there is no ${CONF_SET} Collection right now, let me create it for you..."
        curl -L -v "http://${SOLR_HOST}:${PORT}/solr/admin/collections?action=CREATE&name=${CONF_SET}&numShards=${SHARDS_NUM}&replicationFactor=${REPL_FACTOR}&maxShardsPerNode=${SHARDS_PNODE}&wt=xml"
        echo "Adding ${CONF_SET} config sets to ${CONF_SET} Collection..."
        curl -L -v "http://${SOLR_HOST}:${PORT}/solr/admin/collections?action=MODIFYCOLLECTION&collection=${CONF_SET}&collection.configName=${CONF_SET}"
        echo "Collection ${CONF_SET} created and config set ${CONF_SET} added, you are ready to go!"
      fi
  else
    echo "No Zookeeper or/and Solr hosts found, collections healthcheck failed, however the actual value of ZOOKEEPER_HOST VAR was: ${ZOOKEEPER_HOST} and SOLR_HOST VAR was: ${SOLR_HOST} !"
    exit 1
  fi
}

echo "Provisioning config sets"
config_sets_provisioner || exit 1
echo "Provisioning Collection"
collections_provisioner || exit 1
