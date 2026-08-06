{
  description = "OCI Free Tier Infrastructure with Proxmox and Talos K8s";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        # Python environment for helper scripts (Dagger SDK not available in nixpkgs for this platform).
        pythonEnv = pkgs.python312.withPackages (ps: with ps; [
          requests
          pyyaml
        ]);

      in {
        # Development shell
        devShells.default = pkgs.mkShell {
          name = "oci-free-tier-dev";

          buildInputs = with pkgs; [
            # Infrastructure tools
            opentofu
            kubectl
            kubernetes-helm
            talosctl

            # Security tools
            sops
            age

            # Image building
            packer
            qemu

            # Orchestration & CI/CD
            go-task        # Task runner
            pythonEnv      # Python helper environment

            # Utilities
            jq
            yq-go
            gh
            git
            curl

            # OCI CLI
            oci-cli

            # Linting/formatting
            terraform-ls
            tflint
            shellcheck
            yamllint

            # Pre-commit
            pre-commit
          ];

          shellHook = ''
            echo "🚀 OCI Free Tier Manager - Development Environment"
            echo ""
            echo "Available commands:"
            echo "  task --list              - Show all available tasks"
            echo "  task build:images        - Build Packer images with Dagger"
            echo "  task deploy:all          - Full deployment (all phases)"
            echo "  task validate            - Run validation checks"
            echo ""

            # Initialize pre-commit hooks if not already installed
            if [ ! -f .git/hooks/pre-commit ]; then
              echo "Installing pre-commit hooks..."
              pre-commit install
            fi

            echo "Environment ready! Run 'task --list' to see all tasks."
          '';
        };
      }
    );
}
