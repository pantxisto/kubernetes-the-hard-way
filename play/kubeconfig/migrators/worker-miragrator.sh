for instance in worker-0 worker-1 worker-2; do
  lxc file push ${instance}.kubeconfig kube-proxy.kubeconfig ${instance}/root/
done