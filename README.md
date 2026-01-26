# Installation

#### - Easy Install and upgrades

<p align=left>

Build the iso with the following command:

```bash
nix-shell
buildIso <partitions profile> <true or false cloud-init or name of the profile>
```

Build the qcow2 with the following command:

```bash
nix-shell
buildQcow2 <profile>
```

**NOTE**

Then just run the iso in a fresh VM, it will auto install the generic profile.

Customization is done via the `profiles` directories, you can apply another profile later on by changing the hostname. Colmena looks for the hostname.

The hostname must match the name of the profile.

Install or upgrade with a simple command:

```bash
colmena apply
```

It is possible to test the iso in a vm by doing the following:

```bash
nix-shell
runIso <partitions profile> <true or false, enable cloud-init>
```

The whole installation will roll before your eyes.

#### - Kubernetes

To upgrade kubernetes version you must do the following:

##### Upgrade the control plane and kubelet configs

You first need to check if the requested kubernetes version is available in the npins/sources.json.

If not run:

```bash
npins add --name kubeadm-v1.31.1 github kubernetes kubernetes --at v1.31.1 # The naming is as important as the version pinned !!!
npins add --name kubelet-v1.31.1 github kubernetes kubernetes --at v1.31.1 # The naming is as important as the version pinned !!!
```

Then set the option in the module of your profile `kubernetes.version.kubeadm`.

Now run:

```bash
colmena apply # or merge to main to auto-apply it.
```

Then for the first controlplane:

```bash
colmena exec --on <cp0> "sudo kubeadm upgrade apply v1.31.1 -y -v=9"
```

Then for others and workers:

```bash
colmena exec --on <worker01>,<worker02> "sudo kubeadm upgrade node -v=9"
```

##### Upgrade kubelet

Then set the option in the module of your profile `kubernetes.version.kubelet`.

Now run:

```bash
colmena apply # or merge to main to auto-apply it.
```

#### - Adding a User to the Team (rpcu)

To add yourself to the `rpcu` team, follow these steps:

1.  **Create your user directory:**
    Create a new directory in `users/rpcu/` matching your desired username.
    ```bash
    mkdir -p users/rpcu/<your-username>
    ```

2.  **Create a `default.nix`:**
    Inside your new directory, create a `default.nix` file. You can add your personal configurations here.
    ```nix
    # users/rpcu/<your-username>/default.nix
    { ... }:
    {
      # imports = [ ./gitConfig.nix ]; # Optional: Add other imports if needed
    }
    ```

3.  **Register your user:**
    Edit `users/rpcu/default.nix` and add a new `mkUser` block to the `imports` list.
    ```nix
    # users/rpcu/default.nix
    {
      # ... existing imports
      imports = [
        # ... other users
        (mkUser {
          username = "<your-username>";
          userImports = [ ./<your-username> ];
          authorizedKeys = [
            "ssh-ed25519 AAAA..." # Your public SSH key(s)
          ];
        })
      ];
    }
    ```

