{
    description = "Nix Flake with modern CPP compiler and bsc";

    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/25.11";
        flake-utils.url = "github:numtide/flake-utils";
    };

    outputs = { self, flake-utils, nixpkgs } :
        flake-utils.lib.eachSystem ["x86_64-linux"] (system: 
            let
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
                        #sim
                        cocotb
                        cocotbext-axi
                        numpy
                        pillow
                        pytest
                        pytest-asyncio
                    ]);
            in {
                devShells.default = with pkgs; pkgs.mkShellNoCC {
                    packages = [python] ++ (with pkgs; [
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