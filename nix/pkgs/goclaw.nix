{ lib, buildGoModule, go_1_26, goclaw-src }:

buildGoModule.override { go = go_1_26; } {
  pname = "goclaw";
  version = "1.32.0";

  src = goclaw-src;

  vendorHash = "sha256-cN14NXtIXowqJjtkS1yiFDhMFEdTsSe40RYI/RZy3I8=";

  env.CGO_ENABLED = 0;

  postPatch = ''
    # Polling reliability fix:
    # - Shorten Telegram long-poll window to avoid idle middlebox/NAT drops.
    # - Keep HTTP timeout above poll timeout, but short enough for quick recovery.
    substituteInPlace internal/channels/telegram/channel.go \
      --replace-fail 'Timeout: 30 * time.Second,' 'Timeout: 25 * time.Second,' \
      --replace-fail 'Timeout: 30,' 'Timeout: 10,'
  '';

  ldflags = [
    "-s" "-w"
    "-X github.com/nextlevelbuilder/goclaw/cmd.Version=1.32.0"
  ];

  # Tests need a running PostgreSQL
  doCheck = false;

  postInstall = ''
    mkdir -p $out/share/goclaw
    cp -r $src/migrations $out/share/goclaw/migrations
    cp -r $src/skills $out/share/goclaw/skills
    cp $src/Dockerfile.sandbox $out/share/goclaw/Dockerfile.sandbox
  '';

  meta = with lib; {
    description = "Multi-agent AI gateway with PostgreSQL backend";
    homepage = "https://github.com/nextlevelbuilder/goclaw";
    mainProgram = "goclaw";
  };
}
