for instance in controller-0 controller-1 controller-2; do
  lxc file push encryption-config.yaml ${instance}/root/
done