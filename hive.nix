let
  sources = import ./npins;
  pkgs = import sources.nixpkgs {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = true;
    };
  };
  createConfiguration = parent: {
    networking.hostName = parent.hostName;
    deployment = {
      buildOnTarget = true;
      # Allow local deployment with `colmena apply-local`
      allowLocalDeployment = true;
      targetUser = builtins.getEnv "USER";
      targetHost = parent.host;
      inherit (parent) tags;
    };
    imports = [ ./profiles/${parent.hostName}/configuration.nix ];
  };
in
{
  meta = {
    nixpkgs = pkgs;
  };
  lucy = createConfiguration {
    hostName = "lucy";
    host = "94.130.137.123";
    tags = [
      "rpcu"
      "baremetal"
    ];
  };
  makise = createConfiguration {
    hostName = "makise";
    host = "94.130.162.42";
    tags = [
      "rpcu"
      "baremetal"
    ];
  };
  quinn = createConfiguration {
    hostName = "quinn";
    host = "176.9.219.89";
    tags = [
      "rpcu"
      "baremetal"
    ];
  };
}
