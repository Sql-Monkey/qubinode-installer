#!/bin/bash
###
# Collecting system information status
###
echo ""

CHECK_COCKPIT_SERVICE=$(systemctl status cockpit | grep inactive 2> /dev/null)
if [[ ! -z $CHECK_COCKPIT_SERVICE ]]; then
    echo "Cockpit service is not running."
    ansible-playbook /opt/openshift-home-lab/Packages/openshift-home-lab/tasks/check_cockpit_service.yml
fi

customcli=$(ls /opt/openshift-home-lab/Packages/openshift-home-lab/custom_cli_tools | grep _ | tr '\r\n' ' ')
for i in /opt/openshift-home-lab/Packages/openshift-home-lab/custom_cli_tools/*
do
   echo "line: ${i}"
   if [[ $i != *".TBL"*  ]]; then
     checkforscript=$(ls /usr/local/bin/${i}  2> /dev/null)
     if [[ -z $checkforscript ]]; then
       echo "Copying $i to /usr/local/bin/"
       chmod +x ${i}
       mv ${i} /usr/local/bin/
     fi
   fi
done

CHECKFOR_OCP_INSTALLATION=$(virsh list | grep running | wc -l)
CHECKFOR_OCP_INSTALLATION_SHUTDOWN=$(virsh list | grep shutdown | wc -l)
CHECKFOR_OCP_INSTALLATION_POWERED_DOWN=$(virsh list --all | grep 'shut off' | wc -l)
if [[ $CHECKFOR_OCP_INSTALLATION -eq 7 ]] ; then
    echo "OpenShift KVM Nodes are up and running." | tee /var/log/openshift_bootstrap_service.log
    DOMAINNAME=$(cat inventory.rhel.openshift | grep search_domain| awk '{print $1}' | cut -d'=' -f2)
    OCP_STATUS=$(curl --write-out %{http_code} --silent --output /dev/null "https://master.$DOMAINNAME:8443" --insecure)
    if [[ OCP_STATUS -eq 200 ]];  then
      echo "Openshift Console URL:  https://master.$DOMAINNAME:8443"
    else
      echo "Testing if nodes are online"
      source /opt/openshift-home-lab/Packages/openshift-home-lab/bootstrap_env
      ansible-playbook -i inventory.vm.provision tasks/wait_for_me.yml  --extra-vars "rhel_user=$SSH_USERNAME" && echo "To troubleshoot cluster run ssh $SSH_USERNAME@master scripts/check_system_state.sh both"|| exit 1
      echo "Openshift Console URL:  https://master.$DOMAINNAME:8443"
    fi

elif [[ $CHECKFOR_OCP_INSTALLATION_POWERED_DOWN -eq 7 ]] ; then
    echo "Warning OpenShift KVM nodes are deployed but they are powered down." | tee /var/log/openshift_bootstrap_service.log
    read -p "Would you like to start them up?" -n 1 -r | tee /var/log/openshift_bootstrap_service.log
    echo    # (optional) move to a new line
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        echo "starting up KVMs" | tee /var/log/openshift_bootstrap_service.log
        NODENAMES=$(virsh list --all | grep 'shut off' | awk '{print $2}')
        for n in $NODENAMES; do
          echo "Starting up node: $n" | tee /var/log/openshift_bootstrap_service.log
          virsh start $n | tee /var/log/openshift_bootstrap_service.log
        done
    fi
elif [[ $CHECKFOR_OCP_INSTALLATION_SHUTDOWN -eq 7 ]] ; then
    echo "Warning OpenShift KVM nodes are deployed but they are not running." | tee /var/log/openshift_bootstrap_service.log
    read -p "Would you like to start them up?" -n 1 -r | tee /var/log/openshift_bootstrap_service.log
    echo    # (optional) move to a new line
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
      echo "starting up KVMs" | tee /var/log/openshift_bootstrap_service.log
      NODENAMES=$(virsh list --all | grep shutdown | awk '{print $2}')
      for n in $NODENAMES; do
        echo "Starting up node: $n" | tee /var/log/openshift_bootstrap_service.log
        virsh start $n | tee /var/log/openshift_bootstrap_service.log
      done
    fi
else
  CHECKFOR_DNS=$(virsh list | grep running | grep dnsserver | wc -l)
  if [[ $CHECKFOR_DNS -ne 1 ]]; then
    echo "Warning OpenShift KVM master and worker nodes are not found.  " | tee /var/log/openshift_bootstrap_service.log
    read -p "Would you like to deploy a new Openshift cluster?  " -n 1 -r
    echo    # (optional) move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
        echo "Deploying Openshift cluster" | tee /var/log/openshift_bootstrap_service.log
        cd /opt/openshift-home-lab/Packages/openshift-home-lab/
        bash /opt/openshift-home-lab/Packages/openshift-home-lab/bootstrap.sh | tee /var/log/openshift_bootstrap_install.log
    fi
  else
    echo "Start bootstrap script" | tee /var/log/openshift_bootstrap_service.log
    cd /opt/openshift-home-lab/Packages/openshift-home-lab/
    bash /opt/openshift-home-lab/Packages/openshift-home-lab/bootstrap.sh | tee /var/log/openshift_bootstrap_install.log
  fi
fi