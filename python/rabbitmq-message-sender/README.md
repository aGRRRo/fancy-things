## Simple RabbitMQ message sender
```Usage: ./rabbitmq-message-sender.py -i <INSTANCE_ADDRESS> -p <PORT> -u <USER> -s <PASSWORD> -v <VHOST> -r <ROUTING_KEY> -t <TARGET_TYPE> -o <TARGET_OBJECT_NAME> -m <MESSAGE>```

* -r recursive((script will iterate though whole the list and print only active hosts) or non-recursive(script will check hosts until the very first available host will be found)
* -i  Input data. Comma separated list of hosts or IPs is required.
## Examples:
* ```./rabbitmq-message-sender.py -i example.com -p 5672 -u story_teller -s abracadabra -v horror_stories -r monster -t exchange -o mexico -m "el chupacabra!"```
 
 