import sys

with open("nixosModules/rpcuIaaSCP/osconfig.nix", "r") as f:
    content = f.read()

injection = """    services.ovn-br-ex = lib.mkIf cfg.enable {
      description = "Set OVN br-ex link up and configure MASQUERADE";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [ iproute2 iptables ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        # Wait for br-ex to appear since OVN creates it dynamically
        while ! ip link show br-ex >/dev/null 2>&1; do
          sleep 2
        done
        ip link set br-ex up
        # Add MASQUERADE rule for external traffic if not already present
        if ! iptables -t nat -C POSTROUTING -o ${primaryInterface} -j MASQUERADE 2>/dev/null; then
          iptables -t nat -A POSTROUTING -o ${primaryInterface} -j MASQUERADE
        fi
      '';
    };
"""

target = "    services.kubelet.serviceConfig.Environment = lib.mkIf cfg.enable ("
new_content = content.replace(target, injection + target)

with open("nixosModules/rpcuIaaSCP/osconfig.nix", "w") as f:
    f.write(new_content)
