## Host availability checker
* You can use either single host/IP either comma separated list ("google.com,www.example.com,example.net,93.184.216.34")


```Usage: ./zk_checker-v3.sh -r -i <Input data>```

* -r recursive((script will iterate though whole the list and print only active hosts) or non-recursive(script will check hosts until the very first available host will be found)
* -i  Input data. Comma separated list of hosts or IPs is required.
## Examples:
* ```./zk_checker-v3.sh -i www.example.com,example.net,93.184.216.34```

* ```./zk_checker-v3.sh -ri www.example.com,example.net,93.184.216.34```
 
  
 * Using predefined var(export NEW_HOSTS="www.example.com,example.net,93.184.216.34")
 
    ```./zk_checker-v3.sh -ri <<< echo $NEW_HOSTS ```
 
 