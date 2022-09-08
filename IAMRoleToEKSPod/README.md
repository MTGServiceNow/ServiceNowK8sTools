### NOTE: MY POSTINGS REFLECT MY OWN VIEWS AND DO NOT NECESSARILY REPRESENT THE VIEWS OF MY EMPLOYER

# Passing an IAM Role into a Kubernetes Pod for Discovery Purposes

## Why? 

Given that most organizations do NOT want to allow username and password or API token access to the AWS API, the best method is to setup the ability for a MID server to assume an IAM role with the proper access. 

This is something we do regularly with MID servers running inside an EC2 instance.  However, the process to assign a role to a containerized MID server hasn't been documented.  

This will allow organizations to use containerized MID servers for credentialless AWS discovery as well as the new capabiliy in San Diego to automatically discover EKS clusters without managing credentials in the ServiceNow platform.  

## How?

I followed the documentation [here](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html) in order to configure this the first time.  

### Overview

1. Create an IAM OIDC Provider for your cluster.  
1. Setup the role and attach the serviceaccount to the role.  
1. Configure the MID server to run as that serviceaccount.

### Create an IAM OIDC Provider

Let's check to see if you have an existing OIDC provider for your cluster.  This command pulls in the OIDC Provider ID for your cluster and stores it into a variable.  

```
oidc_id=$(aws eks describe-cluster --name <cluster_name> --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)
```

Then, see if you already have an IAM OIDC Provider for your cluster.  

```
aws iam list-open-id-connect-providers | grep $oidc_id
```

If that returns an ID, then you already have an IAM Provider and you won't need to create a new one.  However, if it returns nothing you'll need to create one with the following command:

```
eksctl utils associate-iam-oidc-provider --cluster <cluster_name> --approve
```

### Setup the role and attach the serviceaccount to the role

In this particular case, I'm not going to create a new policy as I'm using the existing AWS Policy "ReadOnlyAccess" for discovery purposes.  The ReadOnlyAccess role gives the ability to read any document in an S3 bucket so most organizations wouldn't use this policy in a production configuration.  Most customers will use ViewOnlyAccess.  However, ViewOnlyAccess doesn't contain the necessary policies to discover EKS clusters.  Organizations may opt to build a custom role with only the necessary permissions.  However, for demonstration purposes the below will suffice.  

```
eksctl create iamserviceaccount --name <serviceaccountname> --namespace <namespace> --cluster <cluster_name> --role-name "<iamrolename>"  --attach-policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess --approve
```

Now, confirm it was setup correctly by running this command:  

```
aws iam get-role --role-name <iamrolename> --query Role.AssumeRolePolicyDocument
```

You should get output similar to this: 

```
Statement:
- Action: sts:AssumeRoleWithWebIdentity
  Condition:
    StringEquals:
      oidc.eks.us-west-2.amazonaws.com/id/XXXXXXXXXXXX:aud: sts.amazonaws.com
      oidc.eks.us-west-2.amazonaws.com/id/XXXXXXXXXXXX:sub: system:serviceaccount:<namespace>:<serviceaccountname>
  Effect: Allow
  Principal:
    Federated: arn:aws:iam::XXXXXXX:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/XXXXXXXXXXXX
Version: '2012-10-17'
```

Also, describe the role from inside the Kubernetes cluster.  You should see something similar to this:

```
Name:                <serviceaccountname>
Namespace:           <namespace>
Labels:              app.kubernetes.io/managed-by=eksctl
Annotations:         eks.amazonaws.com/role-arn: arn:aws:iam::XXXXXXXXXXXX:role/<iamrolename>
Image pull secrets:  <none>
Mountable secrets:   <serviceaccountname>-token-msvj4
Tokens:              <serviceaccountname>-token-msvj4
Events:              <none>
```

### Configure the MID server to run as that serviceaccount.

For questions on building the MID server and deploying it into a cluster please see my other article [here](https://github.com/MTGServiceNow/ServiceNowK8sTools/tree/main/Rome).

In order for the MID server to run as a particular Kubernetes service account you'll need to register the pod with a service account.  See below for example.  

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: deploymentmid
spec:
  selector:
    matchLabels:
      app: MIDServerManagement
      provider: ServiceNow
      type: DeploymentMID
  replicas: 1
  template:
    metadata:
      labels:
        app: MIDServerManagement
        provider: ServiceNow
        type: DeploymentMID
    spec:
      serviceAccountName: "k8smiddeploymentaccount"
      containers:
        - name: mid_server
          imagePullPolicy: Always
          image: <IMAGEURL:TAG>
          env:
            - name: MID_INSTANCE_URL 
              value: “<FULL INSTANCE URL>” 
            - name: MID_INSTANCE_USERNAME 
              value: “<MID SERVER USERNAME>” 
            - name: MID_INSTANCE_PASSWORD 
              valueFrom:
               secretKeyRef:
                  name: mid-server-secret
                  key: SN_PASSWD
            - name: MID_SECRETS_FILE 
              value: "" 
            - name: MID_SERVER_NAME 
              value: "<FRIENDLY MID SERVER NAME>"
            - name: MID_PROXY_HOST 
              value: "" 
            - name: MID_PROXY_PORT 
              value: "" 
            - name: MID_PROXY_USERNAME 
              value: "" 
            - name: MID_PROXY_PASSWORD 
              value: "" 
            - name: MID_MUTUAL_AUTH_PEM_FILE 
              value: "" 
```

Note the "serviceAccountName:" line. That's the configuration that tells Kubernetes that this pod is running as a specific serviceaccount and has all the necessary rights and permissions.  

Now that this has been completed, any calls to the AWS API can utilize the permissions provided by the IAM role in the "Setup role" step.  

For clarity's sake, the permissions inheritance looks like this:  Pod -> ServiceAccount -> IAM Role.

## Conclusion

Once this is all setup you should be able to use this containerized MID server to do AWS discovery with Temporary credentials as well as EKS discovery utilizing a temporary bearer token.  

Enjoy! 
