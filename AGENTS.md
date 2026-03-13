# Hephaestus Agents

Hephaestus is RPCU's NixOS-based operating system for reproducible, declarative cloud infrastructure. This document describes all agents deployed in the system.

## Overview

An "agent" in Hephaestus refers to any autonomous system service or component that manages infrastructure operations. These include Kubernetes services, VPN agents, deployment orchestrators, and cloud initialization services. All agents operate within the NixOS declarative paradigm where configuration is reproducible, version-locked, and atomic.

---

## Agents

### 1. Kubelet - Kubernetes Node Agent

**Type:** Kubernetes system service agent  
**Location:** `nixosModules/kubernetes/default.nix` (Lines 195-227)  
**Version:** v1.35.2 (configurable)  
**Status:** Enabled when `customNixOSModules.kubernetes.enable = true`

**Purpose:** Manages container lifecycle, pod operations, and node coordination on Kubernetes nodes.

**Features:**
- Pod lifecycle management
- Container runtime integration (containerd)
- CNI networking plugin support
- Health checks and probes
- Storage volume management
- Node status reporting

**Systemd Configuration:**
- Always restart with 10-second delay
- Integrated with containerd, CNI plugins, and system utilities
- Listens on node's private IP address

---

### 2. SSH Agent - SSH Credential Management

**Type:** System service agent  
**Location:** `base.nix` (Lines 166-169)  
**Status:** Enabled globally

**Purpose:** Manages SSH keys and authentication for Git operations and remote deployments.

**Configuration:**
```nix
programs = {
  ssh.startAgent = true;
  gnupg.agent.enableSSHSupport = false;
};
```

**Used for:**
- Colmena deployments
- Git operations
- Remote access

---

### 3. QEMU Guest Agent - Virtual Machine Management

**Type:** Cloud/Virtualization guest agent  
**Location:** `profiles/kaas/default.nix` (Lines 65-74)  
**Profile:** kaas (Kubernetes-as-a-Service - cloud deployments)  
**Status:** Force-enabled on cloud instances

**Purpose:** Enables host-to-guest communication for KVM/QEMU VMs.

**Capabilities:**
- VM lifecycle reporting
- Hot-plug device support
- Guest memory status
- File operations

---

### 4. Cloud-Init - Cloud Instance Initialization

**Type:** Cloud provisioning/initialization agent  
**Location:** `profiles/kaas/default.nix` (Lines 75-78)  
**Status:** Enabled on cloud deployments

**Purpose:** Bootstraps cloud instances with network configuration and service initialization.

**Configuration:**
```nix
services.cloud-init = {
  enable = true;
  network.enable = true;
};
```

**Features:**
- Network configuration automation
- User/SSH key setup
- Package installation
- Cloud provider metadata integration
- Boot completion signaling

**Boot Flow:** Waits for `/var/lib/cloud/instance/boot-finished` before proceeding

---

### 5. Netbird - Network Mesh VPN Agent

**Type:** Network mesh/VPN agent  
**Locations:**
- `nixosModules/rpcuIaaSCP.nix` (Line 407)
- `profiles/sunraku/default.nix` (Line 15)

**Status:** Enabled on RpcuIaaSCP cluster nodes and sunraku VPS

**Purpose:** Provides secure peer-to-peer network connectivity across infrastructure.

**Features:**
- WireGuard-based encryption
- Point-to-point mesh networking
- Centralized control, decentralized data plane
- Inter-cluster node communication
- VPN connectivity for remote infrastructure

---

### 6. Colmena - Infrastructure Orchestration Framework

**Type:** Distributed configuration management agent  
**Location:** `hive.nix`  
**Status:** Active (deployment framework)

**Purpose:** Manages declarative NixOS configuration across multiple nodes.

**Managed Nodes:**
- **lucy** - Control Plane Primary (IP: 10.0.0.2, Priority: 100, baremetal)
- **makise** - Control Plane Secondary (IP: 10.0.0.3, Priority: 99, baremetal)
- **quinn** - Control Plane Tertiary (IP: 10.0.0.4, Priority: 98, baremetal)
- **sunraku** - Infrastructure VPS

**Features:**
- Build-on-target capability
- Local deployment support (`colmena apply-local`)
- Per-node target configuration
- Shared NixPkgs across all nodes

---

### 7. Ginx - Continuous Deployment/GitOps Agent

**Type:** GitOps/continuous deployment agent  
**Location:** `nixosModules/ginx.nix`  
**Status:** Optional (configurable)

**Purpose:** Watches remote Git repository and automatically deploys updates.

**Configuration:**
```nix
services.ginx = {
  enable = true;
  ExecStart = "ginx --source https://github.com/rpcu/hephaestus -b main -n 60 ...";
  Restart = "always";
};

timers.ginx-timer = {
  OnUnitActiveSec = "5min";
};
```

**Features:**
- 60-second polling interval
- 5-minute systemd timer trigger
- Exit-on-failure mode
- Automatic restart on failure
- Integration with colmena for deployment

**Deployment Flow:**
```
Git Repository Update
  ↓ ginx polls (60s) / timer (5min)
  ↓ colmena apply-local
  ↓ SSH Agent authenticates
  ↓ Configuration Applied
```

---

### 8. Kubeadm - Kubernetes Cluster Bootstrap Agent

**Type:** Kubernetes bootstrap/cluster initialization agent  
**Location:** `nixosModules/kubernetes/default.nix` (Lines 31-72)  
**Version:** v1.35.2 (configurable)

**Purpose:** Initializes and manages Kubernetes cluster bootstrap and node operations.

#### Associated Scripts:

**a) initKubeadm** - Cluster Initialization
- Location: `nixosModules/rpcuIaaSCP.nix` (Lines 102-156)
- Deploys kube-vip for HA
- Initializes cluster from bootstrap.yaml
- Extracts join credentials (token + certificate key)
- Configures kubectl access
- Applies node labels

**b) joinCPKubeadm** - Control Plane Node Join
- Location: `nixosModules/rpcuIaaSCP.nix` (Lines 158-197)
- Arguments: TOKEN CERTIFICATE_KEY
- Populates join configuration from template
- Joins node as control plane member
- Deploys node's kube-vip
- Applies node labels

**c) kubeadm-upgrade** - Automated Cluster Upgrades
- Location: `nixosModules/kubernetes/default.nix` (Lines 54-72)
- Scheduled via 5-minute systemd timer
- Detects version mismatches
- Upgrades control plane or worker nodes
- Uses kubectl for version detection

---

### 9. Kube-VIP - Kubernetes API Server HA Agent

**Type:** Kubernetes HA/virtual IP management  
**Location:** `nixosModules/rpcuIaaSCP.nix` (Lines 79-100)  
**Image:** `ghcr.io/kube-vip/kube-vip:v1.0.4`

**Purpose:** Manages virtual IP for Kubernetes API server with failover.

**Configuration:**
- Virtual IP: 10.0.0.5:6443
- Interface: VLAN 4000 on primary network
- Features: ARP-based, leader election, service load balancing

**Functions:**
- API server endpoint failover
- Control plane HA
- Service LoadBalancer support
- Runs as static pod via kubelet

---

## Deployment Architecture

### Cluster Initialization Flow
```
initKubeadm (user command)
  ↓ installKubevip
  ↓ kubeadm init (bootstraps control plane)
  ↓ kubelet (manages static pods)
  ↓ Cluster Ready
```

### Node Joining Flow
```
joinCPKubeadm TOKEN CERT_KEY
  ↓ installKubevip
  ↓ kubeadm join
  ↓ kubelet (joins cluster)
  ↓ Node Integrated
```

### Continuous Deployment Flow
```
Git Repository Update
  ↓ ginx polls (60s) / timer (5min)
  ↓ colmena apply-local
  ↓ SSH Agent authenticates
  ↓ Configuration Applied
```

### Cloud Instance Bootstrap Flow
```
KVM/QEMU Launch
  ↓ qemu-guest-agent (VM state)
  ↓ cloud-init (network + bootstrap)
  ↓ Boot completion signal
  ↓ Final colmena configuration
  ↓ System Ready
```

---

## Module Dependencies

```
hive.nix (Colmena deployment framework)
  ├─ base.nix (shared base configuration)
  │  ├─ kubernetes/default.nix (conditionally)
  │  ├─ networkManager.nix
  │  ├─ chrony.nix
  │  ├─ ginx.nix (conditionally)
  │  ├─ rpcuIaaSCP.nix (conditionally)
  │  └─ SSH Agent (always)
  │
  ├─ profiles/*/default.nix (node-specific config)
  │  ├─ lucy/default.nix (RpcuIaaSCP + cluster config)
  │  ├─ makise/default.nix (RpcuIaaSCP + cluster config)
  │  ├─ quinn/default.nix (RpcuIaaSCP + cluster config)
  │  ├─ sunraku/default.nix (VPS + netbird)
  │  └─ kaas/default.nix (cloud VM + cloud-init)
  │
  └─ users/rpcu/* (user configurations)
```

---

## Summary

| Agent | Type | Status | Scope | Purpose |
|-------|------|--------|-------|---------|
| **Kubelet** | K8s Node | ACTIVE | All k8s nodes | Pod/container lifecycle |
| **SSH Agent** | System | ACTIVE | All nodes | Auth for deployments |
| **QEMU Guest** | Cloud | ACTIVE | kaas profile | VM management |
| **Cloud-Init** | Cloud Init | ACTIVE | kaas profile | Instance bootstrap |
| **Netbird** | Network VPN | ACTIVE | RpcuIaaSCP + sunraku | Mesh VPN connectivity |
| **Colmena** | Orchestration | ACTIVE | All (deployment) | Config management |
| **Ginx** | GitOps | OPTIONAL | Configurable | Continuous deployment |
| **Kubeadm** | K8s Bootstrap | ACTIVE | k8s nodes | Cluster init/join |
| **Kube-VIP** | K8s HA | ACTIVE | Control plane | API server virtual IP |

---

## Key Insights

1. **Agent Framework:** NixOS declarative system with systemd service integration
2. **Orchestration:** Colmena manages all distributed deployments; Ginx provides GitOps automation
3. **Kubernetes:** Full k8s cluster with HA via Kube-VIP + VRRP keepalived
4. **Network:** Netbird mesh provides secure inter-node communication; VLAN 4000 for cluster management
5. **Cloud Support:** Cloud-init + QEMU guest agent for cloud deployments (kaas profile)
6. **Deployment Model:** Pull-based (Git → Ginx → Colmena) with declarative NixOS configuration
7. **HA Setup:** 3-node control plane with virtual IP failover and leader election

All agents operate within the NixOS declarative paradigm where configuration is reproducible, version-locked, and atomic.
