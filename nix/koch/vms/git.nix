# Git repository store VM.
# The host's /data/state-store/git is exposed as /data/git; alex's home in
# the guest is /data/git/alex. There are deliberately no other users.
{
  inputs,
}:
import ./mk-service-vm.nix {
  inherit inputs;
  name = "git";
  modules = [
    ({ pkgs, ... }:
      {
        users.users.alex = {
          uid = 1000;
          isNormalUser = true;
          home = "/data/git/alex";
          shell = pkgs.bashInteractive;
          openssh.authorizedKeys.keyFiles = [ ../../common/alex-yubikey.pub ];
        };

        programs.git.enable = true;
        services.openssh = {
          enable = true;
          settings = {
            PasswordAuthentication = false;
            KbdInteractiveAuthentication = false;
            PermitRootLogin = "no";
          };
        };

        virtualisation.sharedDirectories.git = {
          source = "/data/state-store/git";
          target = "/data/git";
          securityModel = "none";
        };

        systemd.tmpfiles.rules = [
          "d /data/git 0755 alex users -"
          "d /data/git/alex 0700 alex users -"
        ];

        koch-vm = {
          memory = 512;
          vcpus = 2;
          ports = [
            # SSH is published on a distinct host port because koch itself
            # already owns port 22. Tailscale DNS points git.koch at koch.
            { guestPort = 22; hostPort = 2222; bind = "all-interfaces"; }
          ];
        };
      })
  ];
}
