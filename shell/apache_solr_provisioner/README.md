## Apache Solr provisioner
* This script can help you to upload config sets to Solr (via Zookeeper)
* This script can check Collection existence and in case it is absent, will create it and attach previously uploaded config set.
* You can use either single host/IP either comma separated list for SOLR_HOST_LIST && ZK_HOST_LIST vars ("google.com,www.example.com,example.net,93.184.216.34")

** Following variables should be declared before script execution:
 - ZK_PORT (Zookeeper port)
 - ZK_HOST_LIST (Comma separated Zookeeper hosts/ip list)
 - SOLR_HOST_LIST (Comma separated Solr hosts/ip list)
 - ${ZK_CONF}" (Config name)
```Usage: ./solr_provisioner.sh``` 
  
 

 
 