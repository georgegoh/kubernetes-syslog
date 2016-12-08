# kubernetes-syslog
Docker container for pushing container logs in kubernetes to an external syslog server.

## Building

~~~~
docker build -t kubernetes-syslog:<version> .
~~~~

## Preparing the image for the cluster

### Docker build machine outside of kubernetes
If you're building on a machine outside of your kubernetes cluster, you need to export the docker image into a tar file:

~~~~
docker save -o kubernetes-syslog-<version>.tar kubernetes-syslog:<version>
~~~~

Then save it into a machine within the kubernetes cluster:

~~~~
docker load -i kubernetes-syslog-<version>.tar
~~~~

### Tag and upload the image into the internal registry (specific to Red Hat OpenShift)

~~~~
export USERNAME=<your username>
oc login --username=${USERNAME}
docker login -u ${USERNAME} -e user@example.com -p "`oc whoami -t`" <REGISTRY-IP>:<PORT>
docker tag kubernetes-syslog-<version>.tar <REGISTRY-IP>:<PORT>/<PROJECT_NAMESPACE>/kubernetes-syslog:<version>
docker push <REGISTRY-IP>:<PORT>/<PROJECT_NAMESPACE>/kubernetes-syslog:<version>
~~~~

## Deploying

If you don't already have a project, then create one:

~~~~
oc login -u system:admin

oadm new-project logging-loginsight
oc project logging-loginsight
~~~~

Create a service account for deploying the pods and assign the appropriate permissions:

~~~~
oc create -f - <<API
apiVersion: v1
kind: ServiceAccount
metadata:
  name: logging-loginsight-fluentd
API

oadm policy add-scc-to-user privileged system:serviceaccount:logging-loginsight:logging-loginsight-fluentd

oadm policy add-cluster-role-to-user cluster-reader system:serviceaccount:logging-loginsight:logging-loginsight-fluentd
~~~~

Create the FluentD config:
~~~~
cat > fluent.conf << EOF
<system>
  log_level warn
</system>

<source>
  @type tail
  @label @KUBERNETES
  path /var/log/containers/*.log
  pos_file /var/log/kubernetes-logging-containers.log.pos
  time_format %Y-%m-%dT%H:%M:%S
  tag kubernetes.*
  format json
  keep_time_key true
  read_from_head true
</source>

<label @KUBERNETES>
  <filter kubernetes.**>
    @type kubernetes_metadata
    kubernetes_url "#{ENV['K8S_HOST_URL']}"
    bearer_token_file /var/run/secrets/kubernetes.io/serviceaccount/token
    ca_file /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    include_namespace_id true
  </filter>
  <filter kubernetes.**>
    @type flatten_hash
    separator _
  </filter>
  <filter kubernetes.**>
    @type record_transformer
    enable_ruby
    <record>
      hostname ${(kubernetes_host rescue nil) || File.open('/etc/docker-hostname') { |f| f.readline }.rstrip}
      message ${(message rescue nil) || log}
      version 1.2.0
    </record>
    remove_keys log,stream
  </filter>

  <match **>
     @type remote_syslog
     #remote_syslog "#{ENV['SYSLOG_HOST']}"
     host "#{ENV['SYSLOG_HOST']}"
     port "#{ENV['SYSLOG_PORT']}"
     tag fluent-kubernetes-syslog-1
     severity info
  </match>
</label>
EOF
~~~~

Create a ConfigMap to use for FluentD:
~~~~
kubectl create configmap fluent-config --from-file=fluent.conf
~~~~

Create a DaemonSet config:

~~~~
cat > fluentd-daemonset.yaml << EOF
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  namespace: logging-loginsight
  name: fluent-syslog-daemonset
spec:
  selector:
      matchLabels:
        name: fluent-syslog-daemonset
  template:
    metadata:
      labels:
        name: fluent-syslog-daemonset
    spec:
      containers:
      - env:
        - name: K8S_HOST_URL
          value: 'https://kubernetes.default.svc.cluster.local'
        - name: SYSLOG_HOST
          value: '<INSERT SYSLOG SERVER HERE>'
        - name: SYSLOG_PORT
          value: '514'
        image: 172.30.90.125:5000/logging-loginsight/fluent-syslog:<VERSION>
        imagePullPolicy: IfNotPresent
        name: fluent-syslog
        resources: {}
        securityContext:
          privileged: true
        terminationMessagePath: /dev/termination-log
        volumeMounts:
        - name: config
          mountPath: /fluentd/etc
        - name: dockerhostname
          readOnly: true
          mountPath: /etc/docker-hostname
        - name: varlog
          mountPath: /var/log
        - name: varlogcontainers
          readOnly: true
          mountPath: /var/log/containers
        - name: varlibdockercontainers
          readOnly: true
          mountPath: /var/lib/docker/containers
      serviceAccountName: logging-loginsight-fluentd
      serviceAccount: logging-loginsight-fluentd
      terminationGracePeriodSeconds: 30
      volumes:
      - name: config
        configMap:
          name: fluent-config
          items:
            - key: fluent.conf
              path: fluent.conf
      - name: dockerhostname
        hostPath:
          path: /etc/hostname
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlogcontainers
        hostPath:
          path: /var/log/containers
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
~~~~

Deploy the DaemonSet:
~~~~
kubectl create -f daemonset.yaml
~~~~
