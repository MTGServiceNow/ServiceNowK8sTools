### NOTE: MY POSTINGS REFLECT MY OWN VIEWS AND DO NOT NECESSARILY REPRESENT THE VIEWS OF MY EMPLOYER

# Deploying a containerized MID server in a Kubernetes cluster - Rome Update

## Update

This is an updated version of a [blog article](https://community.servicenow.com/community?id=community_article&sys_id=5362f0a4db1ae4546621d9d968961901) I wrote in 2021 covering this process.  However, at that time we hadn't yet released the officially supported container image.  Additionally, I've found a more secure method of providing the MID servers access to the cluster resources and so I've updated that here as well.  


## Why? 

The ServiceNow MID server is an incredibly powerful appliance to enable everything from discovery to metrics and event ingestion.  

However, managing them individually can be an additional burden.  Especially as its capabilities continue to evolve and the recommendation is to scale them horizontally.  

As of the ServiceNow Rome release we now officially support a containerized MID server and provide the docker recipe to build it.  

Let's talk about some of the pros and cons to this approach before we dive into the how.  

### Pros

- **Speed**:  A containerized MID server is incredibly quick to deploy and configure.  
- **Availability**: Configuring this as a deployment within a kubernetes cluster ensure that kubernetes is managing the state of the MID server container and will restart or re-deploy it if a catastrophic failure occurs.  
- **Livestock not Pets**: When you know you can quickly and easily deploy a fresh MID server why waste time troubleshooting potential issues?  Kill it, redeploy, move on.  
- **Proximity**:  Especially if you're looking at discovering your kubernetes infrastructure, deploying a MID server into your cluster(s) ensures that you're keeping the network distance between the MID server and the discovered resources as short as possible.  
- **Ease**:  Once you've got this process down, it's incredibly simple to execute.  

### Cons

- **No Windows Discovery**:  Since the container image is based on a linux root you won't be able to utilize this container to discover windows resources.  It simply doesn't have access to the right toolset and protocols to complete that task.  
- **Cluster Resource Scaling**: In order to discover Kubernetes properly via this method you'll need a MID server container deployed in each cluster.  While each MID server is lightweight, this still could result in a large quantity of MID servers and management.  

## How? 

There are a couple pre-requisites that this article assumes: 

- You have a way of building a docker image from a file (working docker installation locally or access to a Cloud Shell from one of the various providers)
- You have a container registry where the built container can be stored and eventually deployed into your K8s infrastructure.  
- You have a working kubernetes cluster deployed. 
- You have a kubectl client configured to connect to said cluster.  

Once you've got the pre-requisites out of the way, I'll share the [YAML](https://github.com/MTGServiceNow/ServiceNowK8sTools/tree/main/Rome) files I've built for this and then talk through their methodology.  

Overview - 

- Build and Publish Container Image
- Build Namespace
- Build Kubernetes Secret
- Configure Deployment Manifest
- Deploy the MID server
- Update and Validate the MID server

## Build Container Image


If you're using a local docker instance or docker running in a cloud shell then you can use the instructions in the [docs](https://docs.servicenow.com/bundle/rome-servicenow-platform/page/product/mid-server/concept/containerized-mid.html) to build the container.  

However, since I'm going to be deploying this in Azure I'll use Azure's Container Registry (ACR or acr from here on out) I'll be using their custom build and push capability as documented [here](https://docs.microsoft.com/en-us/azure/container-registry/container-registry-tutorial-quick-task).

First download the docker recipe file from your instance.  I downloaded mine into a separate directory called "mid_build".  On your >= Rome instance go to "MID Server" -> "Downloads".  Under "Linux Docker Recipe" hit "Copy Link".  Then use wget to download that recipe to the location where you're going to build your image.  Then unzip the package.  

Here's what that all looked like for me: 

```
mkdir mid_build
cd mid_build
wget https://install.service-now.com/glide/distribution/builds/package/app-signed/mid-linux-container-recipe/2021/10/28/mid-linux-container-recipe.rome-06-23-2021__patch3-10-20-2021_10-28-2021_1851.linux.x86-64.zip  
unzip mid-linux-container-recipe.rome-06-23-2021__patch3-10-20-2021_10-28-2021_1851.linux.x86-64.zip
```

Now, if you haven't created your container registry yet you can do so like this: 

```
az acr create --name <Registry Name> --resource-group <myresourcegroup> --sku Standard
```

Now in one single command build and publish the image to your registry.  

```
az acr build --image romemid --registry <Registry Name> .
```

Note that you can call the image whatever you'd like but you'll need to mark that information down for later use.  

Write down the full url of your new image for use later as `<image tag>`.  The format of the url is `<registry name>.azurecr.io/<image>:<tag>`  Unless you specify a tag during the build process the tag will be "latest".  

## Ensure K8s Cluster has access to Container Repository

You'll need to ensure that the Kubernetes cluster you're deploying into has rights to access the container registry where you've published the image.  This process will be dramatically different depending on which provider you're using for both the container registry and the K8s cluster.  

In this case since I'm using Azure services for both its a simple matter of reconfiguring my existing cluster.  

```
az aks update -n <K8s Cluster Name> -g <Resource Group> --attach-acr <Container Registry Name> 
```
This process will take a few minutes to reconfigure the cluster.  Once completed you can now deploy your container within the cluster.  

## Build Namespace

I recommend creating a [Namespace](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/) to be able to collect all of the ServiceNow tools into a single namespace.  I use this in my clusters in order to maintain separation of the tools from the standard workloads.  

Build a YAML manifest file containing the following:  

```
kind: Namespace
apiVersion: v1
metadata:
  name: servicenow
  labels:
    name: servicenow
```

Once that's completed deploy the namespace with the following command: 

```
kubectl apply -f <YOUR_FILE_NAME>
```

Then you can confirm that its been deployed with the following command: 

```
kubectl get namespaces
```

## Build Kubernetes Secret

Kubernetes has a built in method for storing encrypted information that can be shared among pods securely. This is great if you want to manage passwords or utilize the same username and password across multiple pods but have it accessed securely.  

What we'll be doing in this case is building a [Kubernetes Secret](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/) to store the MID server password that's used for the MID to login to your ServiceNow instance.  Once that's completed we'll import that password into the pod as an environment variable for the MID server software to use.  

Here's how:  

```
kubectl create secret generic -n servicenow mid-server-secret \
--from-literal=SN_PASSWD='<MIDUSER_PASSWORD_HERE>'
```

## Configure Deployment Manifest

Now that we've got the namespace, service account, and the secret created we can build the deployment manifest for the MID server itself.  We'll create a new manifest file for deploying the mid server.  

Note that there are some variables in the file below.  This is to configure the MID server at run time to connect to the instance.  Also note the `<image tag>`.  This is the location of your published container image you created earlier.  

```
apiVersion: apps/v1 
kind: Deployment 
metadata: 
  name: mid-deployment 
  namespace: servicenow 
spec: 
  selector: 
    matchLabels: 
      app: mid 
  replicas: 1 
  template: 
    metadata: 
      labels: 
        app: mid 
      name: mid 
    spec: 
      containers:
        - name: mid-server 
          imagePullPolicy: IfNotPresent 
          image: <image tag> #location of the image.
          resources:
            requests:
              cpu: 50m
              memory: 300M
          env: 
            - name: MID_INSTANCE_URL 
            # URL that your MID server will access to login to your instance.  
              value: “” 
            - name: MID_INSTANCE_USERNAME 
            # Username that the MID server will use to login to your instance.  
              value: “” 
            - name: MID_INSTANCE_PASSWORD 
            # Password for the aforementioned account.
              valueFrom:
               secretKeyRef:
                  name: mid-server-secret
                  key: SN_PASSWD
            - name: MID_SECRETS_FILE 
            # This is the location within the container where a secrets file has been mounted into the container.  That secrets file should contain key value pairs of these variables that can be used to configure the MID server.  
              value: "" 
            - name: MID_SERVER_NAME 
            # Name by which the MID server will report itself to the ServiceNow instance.  "Friendly Name"
              value: ""
            - name: MID_PROXY_HOST 
            # If the MID server needs to use a proxy for outbound communications this will be the IP address or hostname of that proxy server. 
              value: "" 
            - name: MID_PROXY_PORT 
            # If the MID server needs to use a proxy for outbound communications this will be the port number it'll use to connect to that proxy server.  
              value: "" 
            - name: MID_PROXY_USERNAME 
            # If the MID server needs to login to the proxy server for outbound communications this will be the username.
              value: "" 
            - name: MID_PROXY_PASSWORD 
            # If the MID server needs to login to the proxy server for outbound communications this will be the password.
              value: "" 
            - name: MID_MUTUAL_AUTH_PEM_FILE 
            # This is the file path within the container where a fully prepared PEM file has been mounted for use with Mutual TLS authentication to the ServiceNow platform.  If this is populated with a valid PEM file, the MID server won't attempt to authenticate with username and password.  
              value: "" 
```

Note that there are other environment variables that are passed into the pod as part of the `env:` block.  Those could also be stored in secrets or a config map.  But for simplicity's sake we're adding them to the manifest directly.  

## Deploy the MID Server

Once you've got the manifest built it's now time to deploy it.  We'll use the kubectl apply command in order to do so.  It's helpful to remember that if there are no net new changes to the manifest, kubectl won't execute any changes on the cluster.  

```
kubectl apply -f <YOUR_FILE_NAME>
```

Once that's completed you should see your pod running with the following command: 

```
kubectl get pods -n servicenow
```

The output should look similar to this: 

```
NAME                             READY   STATUS    RESTARTS   AGE
mid-deployment-ffd9f9845-bl7d2   1/1     Running   0          17m
```

## Update and Validate the MID Server

Once the pod shows that its in a running state, you should be able to log in to your instance to verify the MID server and validate it as you would any other MID server.  

## Closing

You now have a fully running and containerized MID server based on the official Rome Docker Recipe.  Note that this is configured purely for outbound communications.  In order to configure this for Operational Intelligence or for Agent Client Collector connectivity we'll need to configure a kubernetes service to route and allow those inbound requests.  Look for an upcoming blog post on that topic! 