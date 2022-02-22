https://github.com/kelseyhightower/kubernetes-the-hard-way

1. Provision teh resources. Basically we will be deploying 7 LXC containers: 3 master nodes, 3 workers nodes and a load balancer. First we will create de Load Balancer container and configure the Load Balancer. The  we can go with the controller nodes. We will use lxc commands to launch the containers:
sudo snap install lxd -> We install lxc
sudo lxd init -> We configure lxd to start using it. All by default except name of storage backend which is dir.
lxc profile copy default k8s
lxc profile edit k8s-> k8s-profile-config.yaml
lxc network edit lxdbr0 -> lxdbr0-network-config.yaml
lxc launch images:centos/7 haproxy -> We create the container
lxc list -> We got the linux containers
sudo lxc launch ubuntu:18.04 controller-0 --profile k8s -> We create a master node. We apply that porofile 
sudo lxc launch ubuntu:18.04 controller-1 --profile k8s
sudo lxc launch ubuntu:18.04 controller-2 --profile k8s
sudo lxc launch ubuntu:18.04 worker-0 --profile k8s
sudo lxc launch ubuntu:18.04 worker-1 --profile k8s
sudo lxc launch ubuntu:18.04 worker-2 --profile k8sbecause we want to restrict all the containers to have 2CPU/2GB RAm, and that is what that profile does.
lxc config device add worker-0 kmsg disk source=/dev/kmsg path=/dev/kmsg -> Create a mount binding for kubelet to work
lxc config device add worker-1 kmsg disk source=/dev/kmsg path=/dev/kmsg -> Create a mount binding for kubelet to work
lxc config device add worker-2 kmsg disk source=/dev/kmsg path=/dev/kmsg -> Create a mount binding for kubelet to work
lxc exec haproxy bash -> We login to haproxy container and setup haproxy
    yum install -y haproxy net-tools -> net-tools to use netstat and netstat to verify the ports whether are processes running or not.
    netstat -nltp -> No services running at this point on this node
    vi /etc/haproxy/haproxy.cfg -> Config haproxy. We delete frontend and backend
        frontend k8s
          bind 10.240.0.56:6443 -> 6443 is the port of API server. We will be connecting to the load balancer on port 6443 so that would load balance to the APi server on all the master nodes on port 6443
          mode tcd
          default_backend k8s

        backend k8s
          balance roundrobin -> Fisrt request go to controller-0 second to controller-1 third to controller-2, fouth to controller-0...
          mode tcp
          option tcplog
          option tcp-check
          server controller-0 10.240.0.108:6443 check
          server controller-1 10.240.0.106:6443 check
          server controller-2 10.240.0.142:6443 check
    systemctl enable haproxy
    systemctl start haproxy
    systemctl status haproxy
    netstat -nltp -> Shows haproxy lstening on port 6443
    exit
1-  Client tools
    wget -q --show-progress --https-only --timestamping \
  https://storage.googleapis.com/kubernetes-the-hard-way/cfssl/1.4.1/linux/cfssl \
  https://storage.googleapis.com/kubernetes-the-hard-way/cfssl/1.4.1/linux/cfssljson
    chmod +x cfssl cfssljson
    sudo mv cfssl cfssljson /usr/local/bin/
    Install kubectl 
2-  Generate TLS certificates
     mkdir play
     cd play
     https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/04-certificate-authority.md
     We got cert generators iside play/generators folder. Some ip addresses are written manually so they may change and also the way ip address is achieved in kubelet-cert-generator.sh
     We migrate certs to nodes:
      worker-migrator.sh -> To move ca.pem and worker certs - lxc exec worker-1 ls
      controller-migrator.sh -> To move ca.pem, ca-key.pem, service-account certs and api server certs - lxc exec controller-2 ls
3- Generate the kubernetes configuration files for authentication
    KUBERNETES_PUBLIC_ADDRESS=10.240.0.56 -> Set on sh
    We got config generators isnide play/kubeconfig/generators folder. 
    We migrate configs to nodes:
      worker-migrator.sh -> To move kube-proxy.kubeconfig and worker-2.kubeconfig - lxc exec worker-1 ls
      controller-migrator.sh -> To move admin.kubeconfig, kube-scheduler.kubeconfig and kube-controller-manager.kubeconfig - lxc exec controller-2 ls
4- Generating the Data Encryption Config and Key
    ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64) -> Set on sh
    We got encryuption generators isnide play/encryption/generators folder. 
    We migrate configs to controller nodes:
      encryption-migrator.sh -> To move encryption-config.yaml to controller nodes. It is needed becasue etcd isnide controllers use it - lxc exec controller-1 ls
5-  Bootstrapping the etcd Cluster
    lxc exec controller-0 bash
    wget -q --show-progress --https-only --timestamping \
  "https://github.com/etcd-io/etcd/releases/download/v3.4.15/etcd-v3.4.15-linux-amd64.tar.gz" -> Download the etcd container image
    {
      tar -xvf etcd-v3.4.15-linux-amd64.tar.gz
      sudo mv etcd-v3.4.15-linux-amd64/etcd* /usr/local/bin/
    } -> extract and install the etcd server and the etcdctl command line utility
    {
      sudo mkdir -p /etc/etcd /var/lib/etcd
      sudo chmod 700 /var/lib/etcd
      sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/
    } -> create dir and copy pems there.
    INTERNAL_IP=10.240.0.108 -> Set on sh
    ETCD_NAME=$(hostname -s) -> That wopulkd be controller-0
    We got service generators isnide play/etcd folder. 
    sudo systemctl daemon-reload
    sudo systemctl enable etcd
    sudo systemctl start etcd

6-  Bootstrap master nodes
    Download API server, controller manager and scheduler
    lxc exec controller-0 bash
    sudo mkdir -p /etc/kubernetes/config -> Create te folder for the kubernetes configuration
    wget -q --show-progress --https-only --timestamping \
  "https://storage.googleapis.com/kubernetes-release/release/v1.21.0/bin/linux/amd64/kube-apiserver" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.21.0/bin/linux/amd64/kube-controller-manager" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.21.0/bin/linux/amd64/kube-scheduler" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.21.0/bin/linux/amd64/kubectl" -> Download kubectl, kube-apiserver, kube-controller-manager and kube-scheduller
    {
      chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl
      sudo mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/
    } -> Set executable permission and move under usr/loca/bin (install binaries)
    {
      sudo mkdir -p /var/lib/kubernetes/

      sudo mv ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem \
        service-account-key.pem service-account.pem \
        encryption-config.yaml /var/lib/kubernetes/
    } -> create dir and store certificates
    INTERNAL_IP=10.240.0.108
    KUBERNETES_PUBLIC_ADDRESS=10.240.0.56
    We got kube-apiserver service generator isnide play/kubeAPI/generators folder. 
    sudo mv kube-controller-manager.kubeconfig /var/lib/kubernetes/ -> Move the kube-controller-manager kubeconfig into place
    We got kube-controller-manager service generator isnide play/kubeControllerManager/generators folder. 
    sudo mv kube-scheduler.kubeconfig /var/lib/kubernetes/ -> Move the kube-scheduler kubeconfig into place.
    We got kube-scheduler configuration generator isnide play/kubeScheduler/generators folder.  
    We got kube-scheduler service generator isnide play/kubeScheduler/genersators folder. 
    {
      sudo systemctl daemon-reload
      sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler
      sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler
    } -> Start the controller services
    kubectl cluster-info --kubeconfig admin.kubeconfig -> Verification
    We got clusterRole generator isnide play/kubeletRBAC/generators folder. Only need to be executed on one controller node.
    We got clusterRoleBinding generator isnide play/kubeletRBAC/generators folder. Only need to be executed on one controller node.

7-  Bootstrap the worker nodes
    lxc exec worker-0 bash
    {
      sudo apt-get update
      sudo apt-get -y install socat conntrack ipset
    } -> Update and install dependencies. The socat binary enables support for the kubectl port-forward command
    sudo swapon --show -> It not empty do the next step
    sudo swapoff -a -> Disable swap is recommended to ensure kubernetes can provide proper resouce allocation
    and quality of service. If enabled by default kubelet will fail.
    wget -q --show-progress --https-only --timestamping \
  https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.21.0/crictl-v1.21.0-linux-amd64.tar.gz \
  https://github.com/opencontainers/runc/releases/download/v1.0.0-rc93/runc.amd64 \
  https://github.com/containernetworking/plugins/releases/download/v0.9.1/cni-plugins-linux-amd64-v0.9.1.tgz \
  https://github.com/containerd/containerd/releases/download/v1.4.4/containerd-1.4.4-linux-amd64.tar.gz \
  https://storage.googleapis.com/kubernetes-release/release/v1.21.0/bin/linux/amd64/kubectl \
  https://storage.googleapis.com/kubernetes-release/release/v1.21.0/bin/linux/amd64/kube-proxy \
  https://storage.googleapis.com/kubernetes-release/release/v1.21.0/bin/linux/amd64/kubelet _> Download worker binaries: kubectl, kube-proxy, kubelet, containerd, cni-plugins, runc and crictl.
  sudo mkdir -p \
  /etc/cni/net.d \
  /opt/cni/bin \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes \
  /var/run/kubernetes -> Create isntallation directories
  {
    mkdir containerd
    tar -xvf crictl-v1.21.0-linux-amd64.tar.gz
    tar -xvf containerd-1.4.4-linux-amd64.tar.gz -C containerd
    sudo tar -xvf cni-plugins-linux-amd64-v0.9.1.tgz -C /opt/cni/bin/
    sudo mv runc.amd64 runc
    chmod +x crictl kubectl kube-proxy kubelet runc 
    sudo mv crictl kubectl kube-proxy kubelet runc /usr/local/bin/
    sudo mv containerd/bin/* /bin/
  } -> Install the worker binaries
  CNI networeking:
    POD_CIDR=10.200.0.0/24 -> Set POD cidr range for the worker
    We got bridget network configiguration file generator isnide play/bridge/generators folder
    We got loopback network configiguration file generator isnide play/loopback/generators folder
  Configure containerd:
    sudo mkdir -p /etc/containerd/
    We got contyainerd configiguration file generator isnide play/containerd/generators folder 
    We got contyainerd service file generator isnide play/containerd/generators folder 
  Configure kubelet:
    {
      sudo mv ${HOSTNAME}-key.pem ${HOSTNAME}.pem /var/lib/kubelet/
      sudo mv ${HOSTNAME}.kubeconfig /var/lib/kubelet/kubeconfig
      sudo mv ca.pem /var/lib/kubernetes/
    }
    We got kubelet configiguration file generator isnide play/kubelet/generators folder 
    We got kubelet service file generator isnide play/kubelet/generators folder 
  Configure kubernetes proxy:
    sudo mv kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig
    We got kubeProxy configiguration file generator isnide play/kubeProxy/generators folder 
    We got kubeProxy service file generator isnide play/kubeProxy/generators folder 
  Start the worker services:
    kubectl get nodes -o wide
  Verification:
    lxc exec controller-o bash
    kubectl get nodes --kubeconfig admin.kubeconfig
  Configuring kubectl for remote access:
    mkdir ~/.kube
    lxc file pull controller-0/root/admin.kubeconfig ~/.kube/config -> Change cluster server ip address to the api address of haproxy
    kubectl version -> Verification
    kubectl get nodes -o wide

7-  Pod Network Routes
    watch kubectl get pods -o wide
    kubectl run myshell -it --rm --image busybox -- sh
    kubectl run myshell2 -it --rm --image busybox -- sh
      hostname -i
      ping 10.200.2.2 -> ping the other pod to check that there is not pod connection
    sudo route add -net 10.200.0.0 netmask 255.255.255.0 gw 10.240.0.236
    sudo route add -net 10.200.1.0 netmask 255.255.255.0 gw 10.240.0.113
    sudo route add -net 10.200.2.0 netmask 255.255.255.0 gw 10.240.0.37
    ip route show -> We show routes added to lxdbr0 bridge
    kubectl run myshell -it --rm --image busybox -- sh
    kubectl run myshell2 -it --rm --image busybox -- sh
      hostname -i
      ping 10.200.2.2 -> now the ping is working
8-  Deploying the DNS Cluster Add-on:
    kubectl -n kube-system get all -> No resources found
    kubectl apply -f https://storage.googleapis.com/kubernetes-the-hard-way/coredns-1.8.yaml
    kubectl -n kube-system get all -> Everything is running
9-  Smoke Test:
    kubectl create secret generic kubernetes-the-hard-way \
  --from-literal="mykey=mydata" -> We create a secret
    sudo ETCDCTL_API=3 etcdctl get \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/kubernetes.pem \
  --key=/etc/etcd/kubernetes-key.pem\
  /registry/secrets/default/kubernetes-the-hard-way | hexdump -C -> The etcd key should be prefixed with k8s:enc:aescbc:v1:key1, which indicates the aescbc provider was used to encrypt the data with the key1 encryption key.
  kubectl create deployment nginx --image=nginx
  kubectl port-forward nginx-6799fc88d8-25m6g 8080:80 -> We can go to localhost:8080 and see nginx
  kubectl logs nginx-6799fc88d8-25m6g -> Logs are working fine
  kubectl scale deploy nginx --replicas 2 -> Scalation working
  kubectl expose deployment nginx --port 80 --type NodePort -> We cans ee on chrom that wprker-ip:svc-ndoeport shows nginx
  kubectl delete svc nginx
  kubectl delete deploy nginx
  lxc stop --all && lxc delete haproxy ...
    