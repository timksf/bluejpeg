{
    description = "Nix Flake with modern CPP compiler and bsc";

    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/25.11";
        flake-utils.url = "github:numtide/flake-utils";
    };

    outputs = { self, flake-utils, nixpkgs } :
        flake-utils.lib.eachSystem ["x86_64-linux"] (system: let
            pkgs = import nixpkgs {
                inherit system;
            };
            in { 
                devShell = with pkgs; pkgs.mkShellNoCC {
                    packages = with pkgs; [
                        xorg.libX11.dev
                        libpng
                        libz
                        imagemagick
                        gcc13
                        cmake
                        ninja
                        bluespec
                        vscode-extensions.ms-vscode.cmake-tools
                    ];
                };
            }
        );
}