#!/bin/bash

# Creating log file
log_file="errors.log"

# System Update && Upgrade
system_update() {
    echo "Updating system..."
    sudo dnf -y update > /dev/null 2> $log_file
    echo "Upgrading system..."
    sudo dnf -y upgrade > /dev/null 2> $log_file
}

# Kubectl installation
kubectl_install() {
    # Check if kubectl is installed and if the user wants to install it
    if ! which kubectl &> /dev/null; then
        read -r -p "kubectl is not installed. Do you want to install it? [y/n] " answer
        if [ "$answer" == "y" ]; then
        echo "Installing kubectl..."
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" > /dev/null 2> $log_file
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256" > /dev/null 2> $log_file

        # Checking for successful installation
        if echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check --quiet; then
            sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
            if ! which kubectl &> /dev/null; then
                echo "kubectl installation failed." | tee -a "$log_file"
                exit 1
            else
                echo "kubectl installed successfully."
            fi
        else
            echo "sha256sum check failed for kubectl. Not installing." | tee -a "$log_file"
            exit 1
        fi

        else
            echo "Exiting..."
            exit 1
        fi
    fi
}

# Kind installation
kind_install() {
    # Check if kind is installed and if the user wants to install it
    if ! which kind &> /dev/null; then
        read -r -p "kind is not installed. Do you want to install it? [y/n] " answer
        if [ "$answer" == "y" ]; then
            echo "Installing kind..."
            [ "$(uname -m)" = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64 > /dev/null 2> $log_file
            chmod +x ./kind
            sudo mv ./kind /usr/local/bin/kind

            # Checking for successful installation
            if ! which kind &> /dev/null; then
                echo "Kind installation failed." | tee -a "$log_file"
                exit 1
            else
                echo "Kind installed successfully."
            fi
        else
            echo "Exiting..."
            exit 1
        fi
    fi
}

# Helm installation
helm_install() {
    # Check if helm is installed and if the user wants to install it
    if ! which helm &> /dev/null; then
        read -r -p "helm is not installed. Do you want to install it? [y/n] " answer
        if [ "$answer" == "y" ]; then
            echo "Installing helm..."
            sudo dnf -y install helm > /dev/null 2> $log_file

            # Checking for successful installation
            if ! which helm &> /dev/null; then
                echo "Helm installation failed." | tee -a "$log_file"
                exit 1
            else
                echo "Helm installed successfully."
            fi

        else
            echo "Exiting..."
            exit 1
        fi
    fi
}

# Yq command installation
yq_install() {
    # Check if yq is installed
    if ! which yq &> /dev/null; then
        pip install yq > /dev/null 2> $log_file

        # Checking for successful installation
        if ! which yq &> /dev/null; then
            echo "Yq installation failed." >> "$log_file"
            exit 1
        fi
    fi
}

# Creating Cluster
create_cluster() {
    echo "Creating cluster..."

    # Check if the cluster already exists
    if kind get clusters 2>/dev/null | grep -q 'cluster1'; then
        echo "Cluster 'cluster1' already exists."
        return
    fi

    # Create the kind config file
    cat <<EOF > ~/kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: cluster1 
nodes:
- role: control-plane
  image: kindest/node:v1.25.3@sha256:f52781bc0d7a19fb6c405c2af83abfeb311f130707a0e219175677e366cc45d1
- role: worker
  image: kindest/node:v1.25.3@sha256:f52781bc0d7a19fb6c405c2af83abfeb311f130707a0e219175677e366cc45d1
EOF
    # Creating the cluster
    kind create cluster --config ~/kind-config.yaml > /dev/null 2> $log_file
    sleep 5
    
    # Checking for successful creation
    if ! kubectl get nodes &> /dev/null; then
        echo "Cluster creation failed." | tee -a "$log_file"
        exit 1
    else
        echo "Cluster created successfully."
    fi
}

# Installing MetalLB
metalLB_install() {
    echo "Installing MetalLB..."
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml > /dev/null 2> $log_file
    sleep 90

    # Getting the subnet of the kind network for the MetalLB config (ipv4)
    subnet=$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' kind | grep -oP '(\d{1,3}\.){3}\d{1,3}/\d{1,2}')

    # Extract the network base (First two octates) and define the IP range for MetalLB
    network_base=$(echo "$subnet" | cut -d'.' -f1-2)
    ip_range="$network_base.255.200-$network_base.255.250"

    # Create the MetalLB config file
    cat <<EOF > metallb-config.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: example
  namespace: metallb-system
spec:
  addresses:
  - $ip_range
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: empty
  namespace: metallb-system
EOF

    # Apply the MetalLB config
    kubectl apply -f metallb-config.yaml > /dev/null 2> $log_file
    sleep 5

    # Checking for successful installation
    if ! kubectl get pods -n metallb-system &> /dev/null; then
        echo "MetalLB installation failed." | tee -a "$log_file"
        exit 1
    else
        echo "MetalLB installed successfully."
    fi
}

# Installing Nginx Ingress Controller
nginx_ingress_install() {
    echo "Installing Nginx Ingress Controller..."
    helm pull oci://ghcr.io/nginxinc/charts/nginx-ingress --untar --version 1.1.3 &> /dev/null
    cd nginx-ingress || exit 1
    kubectl apply -f crds/ > /dev/null 2> $log_file
    helm install my-release oci://ghcr.io/nginxinc/charts/nginx-ingress --version 1.1.3 > /dev/null 2> $log_file
    sleep 20

    # Checking for successful installation
    if ! helm list -f my-release &> /dev/null; then
        echo "Nginx Ingress Controller installation failed." | tee -a "$log_file"
        exit 1
    else
        echo "Nginx Ingress Controller installed successfully."
    fi
}

# Mail installation
mail_install() {
    # Check if mail is installed
    if ! which mail &> /dev/null; then
        sudo dnf -y install mailx sendmail > /dev/null 2> $log_file

        # Checking for successful installation
        if ! which mail &> /dev/null; then
            echo "Mail installation failed." >> "$log_file"
            exit 1
        fi
    fi
}

# Prequsites check
system_check() {
    # Check if the script is running as root
    if [ "$USER" != "root" ]; then
        echo "Please run the script as root."
        exit 1
    fi

    # Preparing For Installations
    system_update

    # Checking for kubectl
    kubectl_install

    # Checking for kind
    kind_install

    # Checking for yq
    yq_install

    # Checking for helm
    helm_install

    # Creating cluster
    create_cluster

    # Installing MetalLB
    metalLB_install

    # Installing Nginx Ingress Controller
    nginx_ingress_install

    # Installing mail
    mail_install
}

# Changing mongo replicas
change_mongo() {
    # Check if the app is already installed
    # grep -q '^app\s' is a regex that checks if the output of helm list starts with "app"
    if helm list | grep -q '^app\s'; then
        echo "App is already installed. Cannot install the app with the same name."
        exit 1
    fi

    # Checking if the passong arg isn't another flag or empty
    file="/home/ortuser19/Desktop/ex5/k8s/app/values.yaml"
    answer=$1
    if [[ -z "$answer" || "$answer" == -* ]]; then
        echo "Option -m requires an argument."
        exit 1
    
    # Changing the number of replicas
    else
        echo "Changing mongo replicas to $answer..."
        sleep 2
        yq -Y -i ".db.replicas = $answer" "$file"
    fi
}

# Changing app replicas
change_app() {
    # Check if the app is already installed
    if helm list | grep -q '^app\s'; then
        echo "App is already installed. Cannot install the app with the same name."
        exit 1
    fi

    # Checking if the passong arg isn't another flag or empty
    file="/home/ortuser19/Desktop/ex5/k8s/app/values.yaml"
    answer=$1
    if [[ -z "$answer" || "$answer" == -* ]]; then
        echo "Option -a requires an argument."
        exit 1
    
    # Changing the number of replicas
    else
        echo "Changing app replicas to $answer..."
        sleep 2
        yq -Y -i ".app.replicas = $answer" "$file"
    fi
}

# Cleanup
cleanup() {
    # Delete the cluster
    kind delete cluster --name cluster1
    sleep 5
    echo "All components uninstalled successfully."
    exit 0
}

# Help
help() {
    echo "Usage: $0 [ -m <mongo_replicas> ] [ -a <app_replicas> ] [ -d ]"
    echo "Options:"
    echo "  -m <mongo_replicas>  Change the number of mongo replicas."
    echo "  -a <app_replicas>    Change the number of app replicas."
    echo "  -d                   Delete the app."
    exit 1

}

# Checking for running app and mongo pods
check_namespace() {
    namespace=$1
    pods=$(kubectl get pods -n "$namespace")

    # Checking if the pods are running
    if echo "$pods" | grep -q "Running"; then
        if [ "$namespace" == "mongo" ]; then
            echo "MongoDB is initialized."
        elif [ "$namespace" == "vote-app" ]; then
            echo "App is initialized."
        fi
    else
        if [ "$namespace" == "mongo" ]; then
            echo "MongoDB is not initialized." >> "$log_file"
        elif [ "$namespace" == "vote-app" ]; then
            echo "App is not initialized." >> "$log_file"
        fi
    fi
}

# Sending Mail With The Erros
send_mail() {
    address="dshwartzman5@gmail.com"
    # Sends mail only if the log file is not empty
    if [ -s "$log_file" ]; then
        echo "Sending mail with the errors..."
        mail -s "Errors" "$address" < "$log_file"
    fi
}

# Creating app
create_app() {
    # Check if the app is already installed
    if helm list | grep -q '^app\s'; then
        echo "App is already installed. Cannot install the app with the same name."
        exit 1
    fi

    helm_chart="/home/ortuser19/Desktop/ex5/k8s/app/"
    echo "Creating app..."
    helm install app "$helm_chart" > /dev/null 2> $log_file
    sleep 20
    # Checking mongo
    check_namespace mongo
    sleep 20
    #Checking app
    check_namespace vote-app
    sleep 3

    ingress_ip=$(kubectl get ing -n vote-app | awk '{print $4}' | tail -n1)
    echo "$ingress_ip ds-vote-app.octopus.lab" | sudo tee -a /etc/hosts > /dev/null
    echo "App created successfully."; echo "You can access the app at http://ds-vote-app.octopus.lab."
}

# Creating monitoring function
monitor() {
    while true; do
        # Check if the application is running
        if ! kubectl get deployment vote-app -n vote-app > /dev/null 2>&1; then
            echo "The application is not running. Stopping the monitoring function."
            break
        fi

        # Get the names of the pods
        pods=$(kubectl get pods -n vote-app -o jsonpath='{.items[*].metadata.name}')

        # Loop over the pods and get their logs
        for pod in $pods; do
            kubectl logs "$pod" -n vote-app --since=1h 2>> "$log_file"
        done

        # Check the log file for new entries
        send_mail

        # Clear the log file
        echo "" > "$log_file"

        sleep 3600  # wait for 1 hour
    done
}

# main

# Checking for help flag or empty input
if [ "$1" == "--help" ] || [ -z "$1" ]; then
    help
fi

# Check if the first argument is -d for cleanup
if [ "$1" == "-d" ]; then
    cleanup
fi

# Running system check
system_check

# Parsing the flags for other options
while getopts ":m:a:" opt; do
  case ${opt} in
    m)
        change_mongo "$OPTARG"     
        ;;
    a)
        change_app "$OPTARG"
        ;;
    *)
      echo "Invalid option: -$OPTARG"
      help
      ;;
  esac
done

# Running app
create_app
monitor &