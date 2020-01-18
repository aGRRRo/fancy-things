## Simple RabbitMQ message sender
### usage: 
    rabbitmq-message-sender.py [-h] [-i INSTANCE] [-p PORT] [-u USER]
                                  [-s SECRET] [-v VHOST] [-r ROUTING_KEY]
                                  [-t TYPE] [-o OBJECT] [-m MESSAGE]

# Examples:
* ```./rabbitmq-message-sender.py -i example.com -p 5672 -u story_teller -s abracadabra -v horror_stories -r monster -t exchange -o mexico -m "el chupacabra!"```
 
 