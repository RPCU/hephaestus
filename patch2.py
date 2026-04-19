import sys

with open("nixosModules/rpcuIaaSCP/osconfig.nix", "r") as f:
    content = f.read()

# Revert previous patch
old_injection = """    services.ovn-br-ex = lib.mkIf cfg.enable {
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
content = content.replace(old_injection, "")

new_injection = """    services.ovn-br-ex = lib.mkIf cfg.enable {
      description = "Set OVN br-ex link up and configure MASQUERADE";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [ iproute2 iptables ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "5s";
      };
      script = ''
        # Wait for br-ex to appear since OVN creates it dynamically
        while ! ip link show br-ex >/dev/null 2>&1; do
          sleep 5
        done
        
        # Bring the interface up
        ip link set br-ex up
        
        # Add MASQUERADE rule for external traffic if not already present
        if ! iptables -t nat -C POSTROUTING -o ${primaryInterface} -j MASQUERADE 2>/dev/null; then
          iptables -t nat -A POSTROUTING -o ${primaryInterface} -j MASQUERADE
        fi
        
        # Keep service running and watch for device deletion
        ip monitor link dev br-ex | while read -r line; do
          if echo "$line" | grep -q "Deleted"; then
            exit 1
          fi
        done
      '';
    };
"""

target = "    services.kubelet.serviceConfig.Environment = lib.mkIf cfg.enable ("
new_content = content.replace(target, new_injection + target)

with open("nixosModules/rpcuIaaSCP/osconfig.nix", "w") as f:
    f.write(new_content)
