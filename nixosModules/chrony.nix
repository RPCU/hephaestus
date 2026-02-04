{
  config,
  pkgs,
  lib,
}:
let
  cfg = config.customNixOSModules.chrony;
in
{
  options.customNixOSModules.chrony = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''Enable chrony and predefined optimised config.'';
    };

    # TODO implement best configuration for vms.
    vmconfig = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''Use predefined settings for vms'';
    };
  };

  config = lib.mkIf cfg.enable {
    # Disable systemd-timesyncd to avoid conflicts
    services.timesyncd.enable = false;

    services.chrony = {
      enable = true;
      enableRTCTrimming = true;
      
      # Using ntp pools
      servers = [
        "ntp1.hetzner.de"
        "ntp2.hetzner.com"
        "ntp3.hetzner.net"
        "0.europe.pool.ntp.org"
        "1.europe.pool.ntp.org"
        "3.europe.pool.ntp.org"
        "4.europe.pool.ntp.org"
        "time.cloudflare.com"
        "time.google.com"
      ];

      extraConfig = ''
        # Record the rate at which the system clock gains/losses time to a file
        # so it can be compensated for immediately after a reboot.
        driftfile /var/lib/chrony/drift

        # Allow the system clock to be stepped in the first 3 updates 
        # if its offset is larger than 1 second.
        makestep 1.0 3

        # Threshold for frequency error (in ppm).
        # If a source claims the clock is drifting more than 100ppm, 
        # Chrony will ignore it.
        maxupdateskew 100.0

        # Maximum allowed 'distance' (delay + dispersion) in seconds.
        # If the network path is too noisy, Chrony won't use that source.
        maxdistance 1.0

        # Specify the directory for log files.
        logdir /var/log/chrony

        # Only allow the private network to connect to the ntp server.
        allow 10.0.0.0/24
        deny all
      '';
    };
  };
}
