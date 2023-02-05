#postgres_rabbitmq \
#deploy Rabbitmq \
###Install the RabbitMQ operator \

kubectl apply -f https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml


###Check if the components are healthy in the rabbitmq-system namespace \

kubectl get all -o wide -n rabbitmq-system \

####Once the rabbitmq-cluster-operator is healthy and all the related components are created \
###let us now proceed with the installation of a RabbitMQ Cluster in our Kubernetes. \


cd postgres_rabbitmq \
kubectl apply -f rabbitmqcluster.yaml \


####Let us now check the status of our RabbitmqCluster. \

kubectl describe RabbitmqCluster production-rabbitmqcluster \

####Now let us explore the resources created by the RabbitMqCluster \

kubectl get all -l app.kubernetes.io/part-of=rabbitmq \

####RabbitMQ has a Cluster Management Web UI exposed at port 15672 \

kubectl get svc production-rabbitmqcluster -o jsonpath='{.status.loadBalancer.ingress[0].ip}' \

#postgres


##username
echo -n 'root' | base64
##password
echo -n 'mypassword' | base64

kubectl apply -f postgres-secret.yaml
kubectl apply -f postgres-configmap.yaml
kubectl apply -f postgres-deploy.yaml
kubectl get all
kubectl get pods
psql -h 192.168.39.196 -U root --password -p 5432 mydb

jdbc:postgresql://${DB_HOST}:5432/${DB_NAME}
rmq_url="amqp://guest:guest@192.168.29.165:5672/"


