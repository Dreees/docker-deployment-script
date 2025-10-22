# Automated Docker Deployment Script 

A **Bash-based automation tool** that securely pulls your codebase from Git repositories such as GitHUb, Gitea and GitLab then deploys it via Docker on a remote server, and sets up **Nginx** as a reverse proxy.

## Features

- Secure Git authentication using Personal Access Token (PAT)  
- Automated Docker build and deployment on a remote host  
- Dynamic Nginx reverse proxy configuration  
- Validation of container health and app reachability  
- Timestamped logging and error handling  

## Prerequisites

Before running the script, ensure the following:

- Your **local machine** should have bash, git, ssh and rsync installed:

- Your **remote server** runs **Ubuntu 18.04+ / Debian 10+** 

- You have a **Personal Access Token (PAT)** with permissions to clone the target repo
            a **Dockerfile** or **docker-compose.yml** in your repository
            an **SSH key** that allows passwordless login to the remote server 


##  Usage

Provide the  details below  when prompted
- Git repository URL:
- Personal Access Token (PAT)	
- Branch name: (defaults to main)
- Remote server username	e.g. ubuntu, ec2-user, or root
- Remote server IP of the target host
- SSH key path	Full path to your SSH private key file
- Application internal port
