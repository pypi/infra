# adapted from https://stevesloka.com/2017/05/19/access-minikube-services-from-host/

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "sorry, support for $(uname -s) not available"
    exit 1
fi

if [[ "0" == "$(defaults read /Library/Preferences/com.apple.mDNSResponder.plist AlwaysAppendSearchDomains)" ]]; then
    echo <<EOF
Unable to configure DNS for cluster access, you must set the following flag and reboot MacOS:

    sudo defaults write /Library/Preferences/com.apple.mDNSResponder.plist AlwaysAppendSearchDomains -bool YES

This allows us to set a resolver up for the cluster.local domain!
EOF
    exit 1
fi

echo "writing to /etc/resolver/svc.cluster.local"
echo ""
cat <<EOF
    nameserver 10.96.0.10
    domain svc.cluster.local
    search svc.cluster.local default.svc.cluster.local
    options ndots:5
EOF
echo ""
echo "you'll need to enter your administrator password"...
echo

sudo bash -c 'cat <<EOF >/etc/resolver/svc.cluster.local
nameserver 10.96.0.10
domain svc.cluster.local
search svc.cluster.local default.svc.cluster.local
options ndots:5
EOF'

#for interface in $(ifconfig 'bridge0' | grep member | awk '{print $2}'); do
#    echo "Adding hostfilter to bridge0 for $interface"
#    sudo ifconfig bridge0 -hostfilter $interface
#done

echo "Deleting any existing routes for 10.96.0.0/12"
sudo route -n delete 10.96/12 > /dev/null 2>&1
echo "Adding for 10.96.0.0/12 via $(minikube ip)"
sudo route -n add 10.96.0.0/12 $(minikube ip) > /dev/null 2>&1

echo "Preparing pkcs12 bundle for TLS client auth"
openssl pkcs12 -export -clcerts -in $HOME/.minikube/client.crt -inkey $HOME/.minikube/client.key -out $HOME/.minikube/client.p12 -passout pass:minikube

echo "Importing minikubeCA into your login Keychain"
echo "You'll be prompted for your administrator password"
set -x
security add-trusted-cert -d -r trustRoot -k $HOME/Library/Keychains/login.keychain $HOME/.minikube/ca.crt
set +x

echo "Importing minikube client key and cert to your login Keychain"
echo "When prompted for "
set -x
security import $HOME/.minikube/client.p12 -k $HOME/Library/Keychains/login.keychain
set +x
