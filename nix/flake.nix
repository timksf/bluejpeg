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
            cocotbext-axi = pkgs.python313Packages.buildPythonPackage rec {
                pname = "cocotbext-axi";
                version = "0.1.28";
                pyproject = true;

                src = pkgs.fetchPypi {
                    pname = "cocotbext_axi";
                    inherit version;
                    hash = "sha256-XQYhhbm7VHaDmh2BaCHEUzskX1b3sXGz85Ew4miRrjc=";
                };

                build-system = [pkgs.python313Packages.setuptools];

                propagatedBuildInputs = with pkgs.python313Packages; [
                    cocotb
                    cocotb-bus
                ];
            };
            python = pkgs.python313.withPackages (ps:
                with ps; [
                    cocotb
                    cocotbext-axi
                    pytest
                ]);
            architecture-tex = pkgs.texlive.combine {
                inherit (pkgs.texlive)
                    scheme-small
                    latexmk
                    standalone
                    xcolor
                    pgf;
            };
            in { 
                devShell = with pkgs; pkgs.mkShellNoCC {
                    packages = [python] ++ (with pkgs; [
                        architecture-tex
                        poppler-utils
                        xorg.libX11.dev
                        libpng
                        libz
                        imagemagick
                        gcc13
                        cmake
                        ninja
                        bluespec
                        iverilog
                        vscode-extensions.ms-vscode.cmake-tools
                    ]);
                };
            }
        );
}
