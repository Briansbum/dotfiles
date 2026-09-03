{ config, lib, ... }:

let
  agentCommands = {
    claude = "claude";
    pi = "pi";
  };
in
{
  options.machine.agent = {
    primary = lib.mkOption {
      type = lib.types.enum (builtins.attrNames agentCommands);
      description = "Coding agent this machine launches by default from shell helpers.";
    };

    command = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = agentCommands.${config.machine.agent.primary};
      description = "Executable for the primary coding agent.";
    };
  };
}
