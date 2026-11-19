{
  config,
  pkgs,
  lib,
  ...
}:
# tandem-relay: the UDP relay of tandem, a co-op mod for Cyberpunk 2077
# (https://github.com/Banh-Canh/tandem, docs/relay.md). It forwards opaque
# UDP datagrams between a session's host and its guests and hands hosts a
# join code; it keeps nothing on disk. Run here as a Docker container
# managed by systemd (virtualisation.oci-containers).
let
  cfg = config.customNixOSModules.tandemRelay;
  # The image's user (nix/relay-image.nix in tandem: 65532:65532, no shell).
  uid = 65532;
  name = "tandem-relay";
  serviceName = "docker-${name}";
  # Where the service puts its own copy of the token file, readable by the
  # container's user only, and where the relay reads it in the container.
  runtimeTokens = "/run/${name}/host-tokens";
  containerTokens = "/etc/tandem-relay/host-tokens";
  udpPorts = [ cfg.udpPort ] ++ lib.optional (cfg.frontPort != null) cfg.frontPort;
in
{
  options.customNixOSModules.tandemRelay = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run tandem-relay, tandem's UDP co-op relay, as a Docker container.";
    };
    image = lib.mkOption {
      type = lib.types.str;
      default = "zot.rpcu.io/public/tandem-relay";
      description = "The relay's image, without its tag (published by tandem's CI).";
    };
    tag = lib.mkOption {
      type = lib.types.str;
      # TODO: pin the first tag tandem's CI publishes (`<sha8>` or a version
      # tag) once it exists; this placeholder is not a published image.
      default = "unpublished";
      description = "The image's tag: a commit (`<sha8>`) or a version.";
    };
    udpPort = lib.mkOption {
      type = lib.types.port;
      default = 27460;
      description = "UDP port players reach (`--udp`), on every address, IPv4 and IPv6.";
    };
    frontPort = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      example = 27461;
      description = ''
        UDP port of a fleet's shared entrance (`--front`, only redirects).
        Needs `peers`; a lone relay has none.
      '';
    };
    peers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "203.0.113.10:27460"
        "203.0.113.11:27460"
      ];
      description = ''
        Every replica's public `ip:port`, in shard order, the same list on
        every replica (`--peers`). Empty: a lone relay.
      '';
    };
    shard = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 0;
      description = "This replica's index in `peers` (`--shard`).";
    };
    httpListen = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:8080";
      example = "100.119.79.61:8080";
      description = ''
        TCP address of /healthz, /readyz, /metrics and /debug/vars (`--http`).
        Never a public address: the host's firewall may be off (base.nix),
        so the bind address is what keeps it private. Loopback by default;
        the host's NetBird address (wt0) to scrape it over the VPN.
      '';
    };
    hostTokensFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/tandem-relay/host-tokens";
      description = ''
        Host token file on this machine, never in the Nix store: one hex
        token per line (`tandem-relay token` makes one), root-owned, 0600.
        The service gives the container a read-only copy at each start (the
        relay reads it once: restart the service after changing it). Until
        the file exists the service is skipped, not failed.
      '';
    };
    drainTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 10;
      description = ''
        Seconds running sessions may go on after SIGTERM (`--drain-timeout`).
        Short for a lone relay: games hold their players through 20 s of
        silence and get their session back once the relay is up again.
      '';
    };
    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "--max-sessions=512" ];
      description = "More arguments for `tandem-relay serve`.";
    };
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open the relay's UDP ports (IPv4 and IPv6) in the NixOS firewall.
        Never the HTTP port. Has no effect while the firewall is disabled.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.frontPort != null -> cfg.peers != [ ];
        message = "customNixOSModules.tandemRelay.frontPort needs peers (--front only redirects to them).";
      }
      {
        assertion = !lib.hasPrefix builtins.storeDir cfg.hostTokensFile;
        message = "customNixOSModules.tandemRelay.hostTokensFile must not be in the Nix store (world-readable).";
      }
    ];

    virtualisation.docker.enable = true;
    virtualisation.oci-containers = {
      backend = "docker";
      containers.${name} = {
        image = "${cfg.image}:${cfg.tag}";
        user = "${toString uid}:${toString uid}";
        log-driver = "journald";
        # The image's entrypoint is tandem-relay; this replaces its `serve`.
        cmd = [
          "serve"
          "--udp=:${toString cfg.udpPort}"
          "--http=${cfg.httpListen}"
          "--host-tokens=${containerTokens}"
          "--drain-timeout=${toString cfg.drainTimeout}s"
        ]
        ++ lib.optional (cfg.frontPort != null) "--front=:${toString cfg.frontPort}"
        ++ lib.optionals (cfg.peers != [ ]) [
          "--peers=${lib.concatStringsSep "," cfg.peers}"
          "--shard=${toString cfg.shard}"
        ]
        ++ cfg.extraArgs;
        volumes = [ "${runtimeTokens}:${containerTokens}:ro" ];
        # Host networking: the relay must see each player's real source
        # address (it limits join code lookups and rates per source, and
        # sends replies to the address a datagram came from). Published UDP
        # ports go through Docker's NAT or userland proxy, which can show
        # every player as the bridge's address; it also gives IPv6 for free.
        networks = [ "host" ];
        extraOptions = [
          "--read-only"
          "--cap-drop=ALL"
          "--security-opt=no-new-privileges"
          # The same ceiling as tandem's systemd unit and Kubernetes base.
          "--memory=128m"
          "--pids-limit=64"
          # `docker stop` waits for the drain, then a little more.
          "--stop-timeout=${toString (cfg.drainTimeout + 5)}"
        ];
        # No health check: the image has no shell and the binary no probe
        # subcommand. Check it from the host: curl http://<httpListen>/healthz
      };
    };

    systemd.services.${serviceName} = {
      unitConfig.ConditionPathExists = cfg.hostTokensFile;
      serviceConfig = {
        # The container runs with --rm, so systemd restarts it, not Docker.
        Restart = lib.mkForce "always";
        RestartSec = "10s";
        RuntimeDirectory = name;
        # Only dockerd (root) reads it, to bind-mount the copy.
        RuntimeDirectoryMode = "0700";
        ExecStartPre = [
          "${pkgs.coreutils}/bin/install -m 0400 -o ${toString uid} -g ${toString uid} ${cfg.hostTokensFile} ${runtimeTokens}"
        ];
      };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedUDPPorts = udpPorts;
    };
  };
}
