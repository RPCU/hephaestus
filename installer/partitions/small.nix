{
  disk ? "/dev/sda",
}:
{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = disk;
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "512M";
            type = "EF00";
            priority = 1;
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "defaults" ];
              extraArgs = [
                "-n"
                "BOOT"
              ];
            };
          };
          primary = {
            size = "100%";
            content = {
              type = "lvm_pv";
              vg = "vg1";
            };
          };
        };
      };
    };
    lvm_vg = {
      vg1 = {
        type = "lvm_vg";
        lvs = {
          var = {
            size = "5G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/var";
              mountOptions = [
                "noatime"
              ];
              extraArgs = [
                "-L"
                "VAR"
              ];
            };
          };
          nix = {
            size = "30G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/nix";
              mountOptions = [
                "noatime"
              ];
              extraArgs = [
                "-L"
                "NIX"
              ];
            };
          };
          root = {
            size = "2G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              extraArgs = [
                "-L"
                "ROOT"
              ];
            };
          };
        };
      };
    };
  };
}
