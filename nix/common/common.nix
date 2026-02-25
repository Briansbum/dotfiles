{ pkgs, config, ... }:

{
  # Common packages that should be available on all systems
  home.packages = with pkgs; [
    autojump
    flyctl
    kubeswitch
    obsidian
    opencode
  ];

  # Shared program configurations
  programs = {
    # Still need to enable more shared config
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    # Fish shell configuration
    fish = {
      enable = true;

      # Shell initialization (runs for all shells)
      shellInit = ''
        # User-installed Go binaries
        fish_add_path -p "$HOME/go/bin"
        
        # uv (Python package manager)
        fish_add_path "$HOME/.local/bin"
        
        # Krew kubectl plugin manager
        fish_add_path "$HOME/.krew/bin"
      '';

      # Interactive shell initialization
      interactiveShellInit = ''
        # Vi key bindings
        set -g fish_key_bindings fish_vi_key_bindings
      '';

      # Simple aliases and abbreviations
      shellAbbrs = {
        # Kubernetes abbreviations (from OMF kubectl plugin)
        k = "kubectl";
        kaf = "kubectl apply -f";
        keti = "kubectl exec -ti";
        kcuc = "kubectl config use-context";
        kcsc = "kubectl config set-context";
        kcdc = "kubectl config delete-context";
        kccc = "kubectl config current-context";
        kcsccn = "kubectl config set-context --current --namespace";
        kcgc = "kubectl config get-contexts";
        kdel = "kubectl delete";
        kdelf = "kubectl delete -f";
        kgp = "kubectl get pods";
        kgpa = "kubectl get pods --all-namespaces";
        kgpw = "kubectl get pods --watch";
        kgpwide = "kubectl get pods -o wide";
        kep = "kubectl edit pods";
        kdp = "kubectl describe pods";
        kdelp = "kubectl delete pods";
        kgpall = "kubectl get pods --all-namespaces -o wide";
        kgpl = "kubectl get pods -l";
        kgpn = "kubectl get pods -n";
        kgs = "kubectl get svc";
        kgsa = "kubectl get svc --all-namespaces";
        kgsw = "kubectl get svc --watch";
        kgswide = "kubectl get svc -o wide";
        kes = "kubectl edit svc";
        kds = "kubectl describe svc";
        kdels = "kubectl delete svc";
        kgi = "kubectl get ingress";
        kgia = "kubectl get ingress --all-namespaces";
        kei = "kubectl edit ingress";
        kdi = "kubectl describe ingress";
        kdeli = "kubectl delete ingress";
        kgns = "kubectl get namespaces";
        kens = "kubectl edit namespace";
        kdns = "kubectl describe namespace";
        kdelns = "kubectl delete namespace";
        kcn = "kubectl config set-context --current --namespace";
        kgcm = "kubectl get configmaps";
        kgcma = "kubectl get configmaps --all-namespaces";
        kecm = "kubectl edit configmap";
        kdcm = "kubectl describe configmap";
        kdelcm = "kubectl delete configmap";
        kgsec = "kubectl get secret";
        kgseca = "kubectl get secret --all-namespaces";
        kdsec = "kubectl describe secret";
        kdelsec = "kubectl delete secret";
        kgd = "kubectl get deployment";
        kgda = "kubectl get deployment --all-namespaces";
        kgdw = "kubectl get deployment --watch";
        kgdwide = "kubectl get deployment -o wide";
        ked = "kubectl edit deployment";
        kdd = "kubectl describe deployment";
        kdeld = "kubectl delete deployment";
        ksd = "kubectl scale deployment";
        krsd = "kubectl rollout status deployment";
        kgrs = "kubectl get replicaset";
        kdrs = "kubectl describe replicaset";
        kers = "kubectl edit replicaset";
        krh = "kubectl rollout history";
        kru = "kubectl rollout undo";
        kgss = "kubectl get statefulset";
        kgssa = "kubectl get statefulset --all-namespaces";
        kgssw = "kubectl get statefulset --watch";
        kgsswide = "kubectl get statefulset -o wide";
        kess = "kubectl edit statefulset";
        kdss = "kubectl describe statefulset";
        kdelss = "kubectl delete statefulset";
        ksss = "kubectl scale statefulset";
        krsss = "kubectl rollout status statefulset";
        kpf = "kubectl port-forward";
        kga = "kubectl get all";
        kgaa = "kubectl get all --all-namespaces";
        kl = "kubectl logs";
        klf = "kubectl logs -f";
        kcp = "kubectl cp";
        kgno = "kubectl get nodes";
        keno = "kubectl edit node";
        kdno = "kubectl describe node";
        kdelno = "kubectl delete node";
      };

      # Fish functions organized by category
      functions = {
        # ============ Text Editors & Notes ============
        vim = {
          description = "alias vim=nvim";
          body = ''
            truncate -s0 ~/.local/state/nvim/lsp.log 2>/dev/null
            nvim $argv
          '';
        };

        v = {
          description = "fuzzy find in the current directory and open the selected file for editing";
          body = ''
            truncate -s0 ~/.local/state/nvim/lsp.log 2>/dev/null
            nvim (fd -H -t f . | rg -v '.git/' | fzf)
          '';
        };

        o = {
          description = "open opencode at the current directory";
          body = "opencode";
        };

        notes = {
          description = "alias notes=nvim ~/notes";
          body = "nvim ~/notes $argv";
        };

        # ============ Navigation & Directory Management ============
        l = {
          description = "alias l=ls -lsah";
          body = "ls -lsah $argv";
        };

        f = {
          description = "fuzzy find a directory and cd into it";
          body = ''
            set dir (fd --type d | fzf)
            cd $dir
          '';
        };

        ff = {
          description = "finds dirs in ~/devel to a max-depth of 2, can take a query string to start the search";
          body = ''
            if test (count $argv) -ne 0
              set dir (fd --type d --max-depth 2 . "$HOME/devel" | fzf --query $argv)
            else
              set dir (fd --type d --max-depth 2 . "$HOME/devel" | fzf)
            end
            if test -n "$dir"
              cd $dir
              ensure_prepare_commit_msg
              if git status >/dev/null 2>&1
                git fetch
              end
            end
          '';
        };

        j = {
          description = "jump to directory using autojump";
          body = ''
            set dir (autojump $argv)
            if test -n "$dir"
              cd $dir
            end
          '';
        };

        fv = {
          description = "runs ff and opens it in nvim";
          body = ''
            ff $argv
            nvim .
          '';
        };

        # ============ Git Operations ============
        b = {
          description = "alias b with git worktree and fzf";
          body = ''
            set gitroot (git rev-parse --show-toplevel)
            set t (ls "$gitroot/.." | fzf --select-1 --walker=dir,hidden,follow --print-query | tail -n 1)
            if not test -e "$gitroot/../$t"
              git worktree add -b "$t" "$gitroot/../$t"
            end
            cd "$gitroot/../$t"
          '';
        };

        ensure_prepare_commit_msg = {
          description = "ensure prepare-commit-msg hook is linked";
          body = ''
            if test -d .git -a ! -f .git/hooks/prepare-commit-msg
              ln -s $HOME/devel/dotfiles/main/scripts/prepare_commit_msg .git/hooks/prepare-commit-msg >/dev/null 2>&1
            end
          '';
        };

        # ============ Docker & Container Tools ============
        ch = {
          description = "run crush inside of a sandboxed docker container";
          body = ''
            docker-volume-sandbox -d (pwd) -i crushtainer -e GEMINI_API_KEY=(op read op://employee/gemini_api_key/credential)
          '';
        };

        docker-volume-sandbox = {
          description = "Run a container with a volume seeded from a local directory, sync back on exit";
          body = ''
            argparse 'h/help' 'd/dir=' 'i/image=' 'm/mount=' 'e/env=+' -- $argv
            or return 1

            if set -q _flag_help
              echo "Usage: docker-volume-sandbox -d <host-dir> -i <image> [-m <mount-point>] [-e VAR=val]..."
              echo ""
              echo "Options:"
              echo "  -d, --dir     Host directory to seed volume from (required)"
              echo "  -i, --image   Docker image to run (required)"
              echo "  -m, --mount   Mount point inside container (default: /input)"
              echo "  -e, --env     Environment variable to pass (can be repeated)"
              return 0
            end

            if not set -q _flag_dir; or not set -q _flag_image
              echo "Error: --dir and --image are required"
              return 1
            end

            set -l host_dir (realpath $_flag_dir)
            set -l image $_flag_image
            set -l mount_point (set -q _flag_mount; and echo $_flag_mount; or echo "/input")
            set -l volume_name "sandbox-"(random)

            # Build env var args
            set -l env_args
            if set -q _flag_env
              for e in $_flag_env
                set -a env_args -e $e
              end
            end

            echo "Creating volume $volume_name..."
            docker volume create $volume_name
            or return 1

            echo "Seeding volume from $host_dir..."
            docker run --rm \
              -v $volume_name:/data \
              -v $host_dir:/source:ro \
              alpine cp -a /source/. /data/
            or begin
              docker volume rm $volume_name
              return 1
            end

            echo "Running $image with volume mounted at $mount_point..."
            docker run -it --rm \
              $env_args \
              -v $volume_name:$mount_point \
              $image $argv

            echo "Copying volume contents back to $host_dir..."
            docker run --rm \
              -v $volume_name:/data:ro \
              -v $host_dir:/dest \
              alpine cp -a /data/. /dest/

            echo "Cleaning up volume..."
            docker volume rm $volume_name
          '';
        };

        # ============ Kubernetes Helpers ============
        kucc = {
          description = "alias kucc=kubectl config unset current-context";
          body = "kubectl config unset current-context";
        };

        # ============ Infrastructure as Code ============
        tf = {
          description = "alias tf=tofu";
          body = "tofu $argv";
        };

        tg = {
          description = "alias tg=terragrunt";
          body = "terragrunt $argv";
        };

        rmterra = {
          description = "recursively find and delete .terragrunt-cache dirs";
          body = ''
            set dirs (fd -t d -H '.terragrunt-cache')
            for d in $dirs
              rm -rf "$d"
            end
          '';
        };

        # ============ Cloud & AWS ============
        was = {
          description = "run docctor aws export and eval the result";
          body = ''
            if not command -q docctor
              echo "docctor is not installed" >&2
              return 1
            end
            eval (docctor aws export)
          '';
        };

        # ============ System & Utilities ============
        mist = {
          description = "alias mist=ollama run mistral";
          body = "ollama run mistral $argv";
        };

        stern = {
          description = "alias stern for multi-pod log tailing";
          body = "command stern $argv";
        };
      };
    };
  };

  # Services
  services = {
    # SSH agent
    ssh-agent = {
      enable = true;
      enableFishIntegration = true;
    };
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}
