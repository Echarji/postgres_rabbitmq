# postgres_rabbitmq
#deploy Rabbitmq
###Install the RabbitMQ operator 
kubectl apply -f https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml
###Check if the components are healthy in the rabbitmq-system namespace
kubectl get all -o wide -n rabbitmq-system
####Once the rabbitmq-cluster-operator is healthy and all the related components are created 
###let us now proceed with the installation of a RabbitMQ Cluster in our Kubernetes.
cd postgres_rabbitmq
kubectl apply -f rabbitmqcluster.yaml
####Let us now check the status of our RabbitmqCluster.
kubectl describe RabbitmqCluster production-rabbitmqcluster
####Now let us explore the resources created by the RabbitMqCluster
kubectl get all -l app.kubernetes.io/part-of=rabbitmq
####RabbitMQ has a Cluster Management Web UI exposed at port 15672
kubectl get svc production-rabbitmqcluster -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
