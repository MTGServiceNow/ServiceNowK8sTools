### NOTE: MY POSTINGS REFLECT MY OWN VIEWS AND DO NOT NECESSARILY REPRESENT THE VIEWS OF MY EMPLOYER

# Configuring a Kubernetes service account for Kubernetes discovery

## Why? 

Discovering your Kubernetes resources and mapping out the dependencies within your CMDB can be incredibly powerful.  Especially as we start utilizing [tag based service mapping](https://docs.servicenow.com/bundle/paris-it-operations-management/page/product/service-mapping/concept/tag-based-mapping.html).  However, in order to ensure you configure discovery as securely as possible it important to understand how kubernetes RBAC works and what permissions are required for discovery.  

## How? 

Overview: 

- Kubernetes RBAC
- Create Service Account
- Create the Cluster Role 
- Bind the role to the service account.  

## Kuberenetes RBAC

[Kubernetes role based access control](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) is a somewhat complex beast.  We'll focus today on the concepts specifically needed for enabling this access.  

The most important concept is that there are a few key terminologies we need to pay attention to: 

- API Groups  
- Resources
- Verbs


API Groups:  These are groupings of API namespaces.  
Resources: Resource types that the role is allowed to access.  (Pods, Services, Namespaces, etc.)
Verbs: Actions against those specific API Groups and resources (Get, List, Watch, Update, Create, Delete) 

So therefore you have to provide access to the specific API Groups against the right resources and allowing only the verbs necessary to get discovery completed successfully.  


## Create Service Account

We'll need to create a service account within the kubernetes infrastructure which can utilize the new permissions we'll create.  To that end we can deploy the following yaml file to create it.  

```
apiVersion: v1
kind: ServiceAccount
metadata:
  name: discovery
  namespace: kube-system
```

This creates a new service account called "discovery" within the kube-system namespace.  

## Create the Cluster Role 

Now that we have the service account, we'll need to create a role that the service account can assume.  The role contains the privileges and then we'll bind that role to the service account in the next step.  

In order to create the role we'll deploy the following yaml file:  

``` 
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: kubernetes-discovery
  namespace: kube-system
rules:
  # Allow Discovery to see all namespsaces, services, pods, and nodes.
  - apiGroups: [""]
    resources: ["namespaces","services","pods","nodes"]
    verbs: ["get","list"]
  # Allow Discovery to see the kube-controller-manager.
  - apiGroups: [""]
    resources: ["endpoints"]
    resourceNames: ["kube-controller-manager"]
    verbs: ["get","list"]
```

You can see the comments in the yaml that call out which rules are providing access to which resources.  You'll also notice that the only verbs provided are get and list.  As a result, it has absolutely no access to do things like create, update, patch or delete.  

## Bind the Role to the Service Account 

We've created the role and the service account.  Now lets bind them together.  

```
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: discovery
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kubernetes-discovery
subjects:
  - kind: ServiceAccount
    name: discovery
    namespace: kube-system
```


## Apply it to the cluster 

Ok, so we've defined the service account, the role and the rolebinding.  Let's now apply it all to the cluster.  

I've taken all of the above yaml snippets and put them into a single yaml file: discovery_specific_rbac.yaml 

Then apply it with the following command: 

``` 
kubectl apply -f discover_specific_rbac.yaml
```

That outputs something like this:  

```
serviceaccount/discovery created
clusterrole.rbac.authorization.k8s.io/kubernetes-discovery created
clusterrolebinding.rbac.authorization.k8s.io/discovery created
```

## Get the Bearer Token

Now that we've created a service account and bound the correct role to it, we'll need to get the Bearer token that the discovery process uses to access the Kubernetes API endpoint.  

In order to do that, we'll need to view the secrets associated with that service account.  

```
kubectl describe serviceaccount discovery -n kube-system
```

Which outputs something like this: 

```
Name:                discovery
Namespace:           kube-system
Labels:              <none>
Annotations:         <none>
Image pull secrets:  <none>
Mountable secrets:   discovery-token-gcfjq
Tokens:              discovery-token-gcfjq
Events:              <none>
```

The thing we're looking for there is the "Tokens:" line.  We'll need to view that in order to see the base64 encoded bearer token for this service account.  

```
kubectl describe secret -n kube-system discovery-token-gcfjq
```

Which will output something like this: 

```
Name:         discovery-token-gcfjq
Namespace:    kube-system
Labels:       <none>
Annotations:  kubernetes.io/service-account.name: discovery
              kubernetes.io/service-account.uid: 9830c904-8cb9-4248-8c5c-dc0479668f9d

Type:  kubernetes.io/service-account-token

Data
====
ca.crt:     1765 bytes
namespace:  11 bytes
token:      <huge string of letters and numbers>
```

The bearer token that you're looking for is the \<huge string of letters and numbers\>.  

Thats what you'll put into your ServiceNow Instance as a Kubernetes credential.  

