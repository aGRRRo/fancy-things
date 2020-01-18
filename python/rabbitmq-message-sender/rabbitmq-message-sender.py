#!/usr/bin/python3
import pika
import argparse

# Warning!
# If you push a message to queue which is not exists it will be created!
# If you push a message to exchange which is not exists it will be NOT created!
print('Warning!')
print('If you push a message to queue which is not exist it will be created!')
print('If you push a message to exchange which is not exist it will be NOT created!')

param = argparse.ArgumentParser()
param.add_argument('-i', '--instance', help='RabbitMQ Instance IP or Host')
param.add_argument('-p', '--port', help='RabbitMQ Port')
param.add_argument('-u', '--user', help='User login for RabbitMQ auth')
param.add_argument('-s', '--secret', help='User password for RabbitMQ auth')
param.add_argument('-v', '--vhost', help='RabbitMQ Vhost')
param.add_argument('-r', '--routing_key', help='RabbitMQ Vhost')
param.add_argument('-t', '--type',  help='RabbitMQ destination type Queue or Exchange', default='queue')
param.add_argument('-o', '--object', help='RabbitMQ Exchange/Queue name name')
param.add_argument('-m', '--message', help='RabbitMQ Message')
args = param.parse_args()
conn = pika.BlockingConnection
auth = pika.PlainCredentials


def send_message():
    host = args.instance
    port = args.port
    vhost = args.vhost
    routing_key = args.routing_key
    object_type = args.type
    object = args.object
    credentials = auth(args.user, args.secret)
    message = args.message
    connection = conn(pika.ConnectionParameters(host, port, vhost, credentials))
    channel = connection.channel()
    if object_type == 'exchange' and object and message:
        channel.basic_publish(exchange=object,
                              routing_key=routing_key,
                              body=message)
        print(" [+] Sent {} to {} exchange".format(message, object))
        connection.close()
    elif object_type == 'queue' and object and message:
        channel.queue_declare(queue=object),
        channel.basic_publish(exchange='',
                              routing_key=routing_key,
                              body=message)
        print(" [+] Sent {} to {} queue".format(message, object))
        connection.close()
    else:
        print('A whole lotta nothing was sent. Wrong parameters set or message is empty')
        exit(1)


if __name__ == '__main__':
    send_message()
