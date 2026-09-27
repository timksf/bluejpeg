# BlueJPEG architecture diagram

Build the TikZ source with the repository's Nix development shell:

```sh
nix --extra-experimental-features 'nix-command flakes' develop ./nix \
  --command latexmk -pdf -interaction=nonstopmode -halt-on-error \
  -output-directory=assets/architecture \
  assets/architecture/bluejpeg-architecture.tex
```

The flake provides `latexmk`, TikZ/PGF, the standalone document class, and
Poppler (`pdftoppm`/`pdfinfo`) for render-based review.
