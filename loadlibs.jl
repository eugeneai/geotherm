using Pkg

packages = "Revise CSV XLSX DataFrames Plots 
  Debugger Formatting LaTeXStrings 
  Interpolations Optim"

pkgs=split(packages)

for p in pkgs
    Pkg.add(p)
end
